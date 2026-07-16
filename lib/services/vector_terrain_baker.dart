import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:http/http.dart' as http;

import '../core/geo/tile_math.dart';
import 'map_provider.dart';
import 'terrain_contour_service.dart';

/// Adds topographic relief to a vector tile after it has been rasterized.
abstract interface class VectorTerrainBaker {
  Future<Uint8List> bake(Uint8List basePng, TileCoordinate coordinate);

  /// Clears per-area in-memory work between conversions.
  void reset();

  void dispose();
}

/// Test/opt-out implementation that leaves the rasterized vector tile intact.
class PassthroughVectorTerrainBaker implements VectorTerrainBaker {
  const PassthroughVectorTerrainBaker();

  @override
  Future<Uint8List> bake(Uint8List basePng, TileCoordinate coordinate) async =>
      basePng;

  @override
  void reset() {}

  @override
  void dispose() {}
}

/// Fetches Terrarium elevation only while a vector offline area is being built,
/// then bakes contours and hillshade into the final PNG. Raw elevation bytes are
/// never written to disk and this service is not used by online/raster maps.
class TerrariumVectorTerrainBaker implements VectorTerrainBaker {
  TerrariumVectorTerrainBaker({
    required this.config,
    this.service = const TerrainContourService(),
    http.Client? client,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  final MapProviderConfig config;
  final TerrainContourService service;
  final http.Client _client;
  final bool _ownsClient;

  /// The contour band mirrors common topographic maps: no dense global/regional
  /// contours below z10, and z13 terrain is overzoomed for deeper vector tiles.
  static const int minTerrainZoom = 10;
  static const int maxTerrainZoom = 13;
  static const int _maxOverlayCacheEntries = 64;

  final Map<String, Future<Uint8List?>> _overlayCache = {};

  @override
  Future<Uint8List> bake(Uint8List basePng, TileCoordinate coordinate) async {
    if (coordinate.z < minTerrainZoom) return basePng;

    final sourceZoom = coordinate.z > maxTerrainZoom
        ? maxTerrainZoom
        : coordinate.z;
    final zoomDelta = coordinate.z - sourceZoom;
    final sourceX = coordinate.x >> zoomDelta;
    final sourceY = coordinate.y >> zoomDelta;
    final overlay = await _overlayFor(sourceZoom, sourceX, sourceY);
    if (overlay == null) return basePng;
    return _composite(
      basePng: basePng,
      overlayPng: overlay,
      coordinate: coordinate,
      sourceZoom: sourceZoom,
      sourceX: sourceX,
      sourceY: sourceY,
    );
  }

  Future<Uint8List?> _overlayFor(int z, int x, int y) {
    final key = '$z/$x/$y';
    final existing = _overlayCache[key];
    if (existing != null) return existing;
    if (_overlayCache.length >= _maxOverlayCacheEntries) {
      _overlayCache.clear();
    }
    return _overlayCache[key] = _downloadAndRender(z, x, y);
  }

  Future<Uint8List?> _downloadAndRender(int z, int x, int y) async {
    http.Response? response;
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        response = await _client
            .get(
              config.tileUri(z, x, y),
              headers: const {'User-Agent': 'TrailRunner/1.0'},
            )
            .timeout(const Duration(seconds: 15));
        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          return service.renderTerrariumPng(response.bodyBytes);
        }
        if (response.statusCode == 404) return null;
        lastError = HttpException(
          'Terrain request returned HTTP ${response.statusCode}.',
        );
        if (response.statusCode < 500 && response.statusCode != 429) break;
      } on Object catch (error) {
        lastError = error;
      }
      await Future<void>.delayed(Duration(milliseconds: 300 * (attempt + 1)));
    }
    throw lastError ?? const HttpException('Terrain download failed.');
  }

  Future<Uint8List> _composite({
    required Uint8List basePng,
    required Uint8List overlayPng,
    required TileCoordinate coordinate,
    required int sourceZoom,
    required int sourceX,
    required int sourceY,
  }) async {
    final baseCodec = await ui.instantiateImageCodec(basePng);
    final overlayCodec = await ui.instantiateImageCodec(overlayPng);
    final baseFrame = await baseCodec.getNextFrame();
    final overlayFrame = await overlayCodec.getNextFrame();
    final base = baseFrame.image;
    final overlay = overlayFrame.image;
    try {
      final width = base.width.toDouble();
      final height = base.height.toDouble();
      final destination = ui.Rect.fromLTWH(0, 0, width, height);
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder, destination);
      canvas.drawImageRect(
        base,
        ui.Rect.fromLTWH(0, 0, width, height),
        destination,
        ui.Paint(),
      );

      final zoomDelta = coordinate.z - sourceZoom;
      final factor = 1 << zoomDelta;
      final subX = coordinate.x - (sourceX << zoomDelta);
      final subY = coordinate.y - (sourceY << zoomDelta);
      final sourceWidth = overlay.width / factor;
      final sourceHeight = overlay.height / factor;
      final source = ui.Rect.fromLTWH(
        subX * sourceWidth,
        subY * sourceHeight,
        sourceWidth,
        sourceHeight,
      );
      canvas.drawImageRect(
        overlay,
        source,
        destination,
        ui.Paint()..filterQuality = ui.FilterQuality.low,
      );

      final image = await recorder.endRecording().toImage(
        base.width,
        base.height,
      );
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        return bytes!.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    } finally {
      base.dispose();
      overlay.dispose();
      baseCodec.dispose();
      overlayCodec.dispose();
    }
  }

  @override
  void reset() => _overlayCache.clear();

  @override
  void dispose() {
    _overlayCache.clear();
    if (_ownsClient) _client.close();
  }
}
