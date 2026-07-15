import '../core/geo/geo_bounds.dart';

enum OfflineAreaStatus { planned, downloading, paused, complete, failed }

/// How an offline area's tiles were obtained. `rasterTiles` is the per-tile
/// HTTP download; `convertedVector` is free vector data downloaded and
/// rasterized to PNG on the device. Both produce raster tiles rendered by
/// `flutter_map`.
enum OfflineSourceFormat { rasterTiles, convertedVector }

class OfflineArea {
  const OfflineArea({
    required this.id,
    required this.name,
    required this.bounds,
    required this.minZoom,
    required this.maxZoom,
    required this.providerId,
    required this.status,
    required this.totalTiles,
    required this.completedTiles,
    required this.actualBytes,
    required this.createdAt,
    required this.updatedAt,
    this.lastError,
    this.sourceFormat = OfflineSourceFormat.rasterTiles,
  });

  final String id;
  final String name;
  final GeoBounds bounds;
  final int minZoom;
  final int maxZoom;
  final String providerId;
  final OfflineAreaStatus status;
  final int totalTiles;
  final int completedTiles;
  final int actualBytes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? lastError;
  final OfflineSourceFormat sourceFormat;

  double get progress => totalTiles == 0 ? 0 : completedTiles / totalTiles;
}
