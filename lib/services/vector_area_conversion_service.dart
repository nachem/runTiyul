import 'dart:io';
import 'dart:typed_data';

import '../core/geo/tile_math.dart';
import '../data/app_repository.dart';
import '../models/offline_area.dart';
import 'map_provider.dart';
import 'tile_store.dart';
import 'vector_terrain_baker.dart';
import 'vector_tile_rasterizer.dart';
import 'vector_tile_source.dart';

/// Downloads free vector map data and converts a selected area's tiles into
/// raster PNGs on the device, storing them in the local [TileStore] so the
/// existing offline renderer and storage management keep working unchanged.
///
/// This is the on-device realization of "download the free maps, convert if
/// needed, and save what is possible to render locally": each vector tile is
/// rasterized by [VectorTileRasterizer] at download time. It mirrors
/// `OfflineDownloadService` so status, progress and cancellation behave the
/// same as a per-tile raster download.
class VectorAreaConversionService {
  VectorAreaConversionService({
    required this.repository,
    required this.store,
    required this.config,
    VectorTileRasterizer? rasterizer,
    VectorTerrainBaker? terrainBaker,
    Future<VectorTileSource> Function(String source)? openSource,
  }) : rasterizer = rasterizer ?? VectorTileRasterizer(),
       terrainBaker = terrainBaker ?? const PassthroughVectorTerrainBaker(),
       _openSource = openSource ?? _defaultOpenSource;

  final AppRepository repository;
  final TileStore store;
  final MapProviderConfig config;
  final VectorTileRasterizer rasterizer;
  final VectorTerrainBaker terrainBaker;
  final Future<VectorTileSource> Function(String source) _openSource;
  final Set<String> _cancelled = {};

  static Future<VectorTileSource> _defaultOpenSource(String source) async {
    if (HttpVectorTileSource.looksLikeTileUrl(source)) {
      return HttpVectorTileSource.open(source);
    }
    final file = await VectorSourceStore.ensureLocal(source);
    return MbtilesVectorTileSource.openFile(file);
  }

  void cancel(String areaId) => _cancelled.add(areaId);

  Future<OfflineArea> convert(
    OfflineArea initial,
    TilePlan plan, {
    required void Function(OfflineArea area) onProgress,
    String? sourceOverride,
  }) async {
    final source = (sourceOverride != null && sourceOverride.isNotEmpty)
        ? sourceOverride
        : config.vectorSourceUrl;
    if (source.isEmpty) {
      throw StateError('No vector source is configured for conversion.');
    }
    terrainBaker.reset();
    _cancelled.remove(initial.id);
    var area = _copyArea(
      initial,
      status: OfflineAreaStatus.downloading,
      lastError: null,
    );
    await repository.saveOfflineArea(area);
    onProgress(area);

    var completed = 0;
    var bytes = 0;
    Object? firstError;
    VectorTileSource? tileSource;
    try {
      tileSource = await _openSource(source);
      for (final coordinate in plan.coordinates) {
        if (_cancelled.contains(area.id) || firstError != null) break;
        try {
          final written = await _writeTile(area, tileSource, coordinate);
          completed++;
          bytes += written;
          area = _copyArea(area, completedTiles: completed, actualBytes: bytes);
          await repository.saveOfflineArea(area);
          onProgress(area);
        } on Object catch (error) {
          firstError ??= error;
        }
      }
    } on Object catch (error) {
      firstError ??= error;
    } finally {
      await tileSource?.close();
    }

    if (_cancelled.contains(area.id)) {
      area = _copyArea(area, status: OfflineAreaStatus.paused);
    } else if (firstError != null) {
      area = _copyArea(
        area,
        status: OfflineAreaStatus.failed,
        lastError: firstError.toString(),
      );
    } else {
      area = _copyArea(area, status: OfflineAreaStatus.complete);
    }
    await repository.saveOfflineArea(area);
    onProgress(area);
    return area;
  }

  Future<int> _writeTile(
    OfflineArea area,
    VectorTileSource source,
    TileCoordinate coordinate,
  ) async {
    final namespace = offlineTileNamespace(
      config.id,
      OfflineSourceFormat.convertedVector,
    );
    final file = store.fileFor(
      namespace,
      coordinate.z,
      coordinate.x,
      coordinate.y,
    );
    // Re-render even when an older converted tile exists: the render style now
    // includes baked topography, and retaining a pre-topography PNG would leave
    // overlapping or resumed areas visually inconsistent.
    Uint8List png;
    final sourceMax = source.maxZoom;
    if (coordinate.z <= sourceMax) {
      final mvt = await source.readTile(
        coordinate.z,
        coordinate.x,
        coordinate.y,
      );
      // A null tile means the source has no data there (for example open sea);
      // there is nothing to rasterize, so skip it without failing. A present
      // but empty tile still rasterizes to the theme background.
      if (mvt == null) return 0;
      png = await rasterizer.rasterize(mvt, coordinate.z);
    } else {
      // No tiles exist above the source maximum. Read the covering parent tile
      // and over-render it so the saved child remains sharp.
      final dz = coordinate.z - sourceMax;
      final parentX = coordinate.x >> dz;
      final parentY = coordinate.y >> dz;
      final mvt = await source.readTile(sourceMax, parentX, parentY);
      if (mvt == null) return 0;
      png = await rasterizer.rasterizeOverzoom(
        mvt,
        sourceZ: sourceMax,
        sourceX: parentX,
        sourceY: parentY,
        targetZ: coordinate.z,
        targetX: coordinate.x,
        targetY: coordinate.y,
      );
    }
    png = await terrainBaker.bake(png, coordinate);
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.part');
    await temporary.writeAsBytes(png, flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);

    final length = await file.length();
    await repository.attachTile(
      areaId: area.id,
      tileKey: '$namespace/${coordinate.key}',
      providerId: namespace,
      zoom: coordinate.z,
      x: coordinate.x,
      y: coordinate.y,
      relativePath: store.relativePath(file),
      byteCount: length,
    );
    return length;
  }

  void dispose() => terrainBaker.dispose();

  OfflineArea _copyArea(
    OfflineArea area, {
    OfflineAreaStatus? status,
    int? completedTiles,
    int? actualBytes,
    String? lastError,
  }) {
    return OfflineArea(
      id: area.id,
      name: area.name,
      bounds: area.bounds,
      minZoom: area.minZoom,
      maxZoom: area.maxZoom,
      providerId: area.providerId,
      status: status ?? area.status,
      totalTiles: area.totalTiles,
      completedTiles: completedTiles ?? area.completedTiles,
      actualBytes: actualBytes ?? area.actualBytes,
      createdAt: area.createdAt,
      updatedAt: DateTime.now().toUtc(),
      lastError: lastError,
      sourceFormat: area.sourceFormat,
    );
  }
}
