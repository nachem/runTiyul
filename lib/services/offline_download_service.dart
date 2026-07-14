import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/geo/tile_math.dart';
import '../data/app_repository.dart';
import '../models/offline_area.dart';
import 'map_provider.dart';
import 'tile_store.dart';

class OfflineDownloadService {
  OfflineDownloadService({
    required this.repository,
    required this.store,
    required this.config,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final AppRepository repository;
  final TileStore store;
  final MapProviderConfig config;
  final http.Client _client;
  final Set<String> _cancelled = {};

  void cancel(String areaId) => _cancelled.add(areaId);

  void dispose() => _client.close();

  Future<OfflineArea> download(
    OfflineArea initial,
    TilePlan plan, {
    required void Function(OfflineArea area) onProgress,
  }) async {
    if (!config.offlineDownloadsAllowed) {
      throw StateError(
        'This map provider is not configured to permit offline downloads.',
      );
    }
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
    var nextIndex = 0;
    Object? firstError;

    Future<void> worker() async {
      while (nextIndex < plan.coordinates.length &&
          !_cancelled.contains(area.id) &&
          firstError == null) {
        final coordinate = plan.coordinates[nextIndex++];
        try {
          final tileBytes = await _downloadTile(area, coordinate);
          completed++;
          bytes += tileBytes;
          area = _copyArea(area, completedTiles: completed, actualBytes: bytes);
          await repository.saveOfflineArea(area);
          onProgress(area);
        } on Object catch (error) {
          firstError ??= error;
        }
      }
    }

    await Future.wait(List.generate(4, (_) => worker()));
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

  Future<int> _downloadTile(OfflineArea area, TileCoordinate coordinate) async {
    final file = store.fileFor(
      config.id,
      coordinate.z,
      coordinate.x,
      coordinate.y,
    );
    if (!await file.exists()) {
      await file.parent.create(recursive: true);
      http.Response? response;
      Object? lastError;
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          response = await _client
              .get(
                config.tileUri(coordinate.z, coordinate.x, coordinate.y),
                headers: {'User-Agent': 'TrailRunner/1.0'},
              )
              .timeout(const Duration(seconds: 15));
          if (response.statusCode == 200 &&
              response.bodyBytes.isNotEmpty &&
              (response.headers['content-type']?.startsWith('image/') ??
                  false)) {
            break;
          }
          lastError = HttpException(
            'Tile request returned HTTP ${response.statusCode}.',
          );
          if (response.statusCode < 500 && response.statusCode != 429) break;
        } on Object catch (error) {
          lastError = error;
        }
        await Future<void>.delayed(Duration(milliseconds: 300 * (attempt + 1)));
      }
      if (response == null ||
          response.statusCode != 200 ||
          response.bodyBytes.isEmpty ||
          !(response.headers['content-type']?.startsWith('image/') ?? false)) {
        throw lastError ?? const HttpException('Tile download failed.');
      }
      final temporary = File('${file.path}.part');
      await temporary.writeAsBytes(response.bodyBytes, flush: true);
      await temporary.rename(file.path);
    }

    final length = await file.length();
    final key = '${config.id}/${coordinate.key}';
    await repository.attachTile(
      areaId: area.id,
      tileKey: key,
      providerId: config.id,
      zoom: coordinate.z,
      x: coordinate.x,
      y: coordinate.y,
      relativePath: store.relativePath(file),
      byteCount: length,
    );
    return length;
  }

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
    );
  }
}
