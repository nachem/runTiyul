import 'dart:math' as math;

import 'geo_bounds.dart';

const _maxMercatorLatitude = 85.05112878;

class TileCoordinate {
  const TileCoordinate(this.z, this.x, this.y);

  final int z;
  final int x;
  final int y;

  String get key => '$z/$x/$y';

  @override
  bool operator ==(Object other) =>
      other is TileCoordinate && other.z == z && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(z, x, y);
}

class TilePlan {
  const TilePlan(this.coordinates);

  final List<TileCoordinate> coordinates;

  int get tileCount => coordinates.length;

  int estimateBytes({int averageTileBytes = 32 * 1024}) =>
      tileCount * averageTileBytes;
}

class TilePlanner {
  const TilePlanner({this.maxTiles = 5000});

  final int maxTiles;

  TilePlan plan(GeoBounds bounds, int minZoom, int maxZoom) {
    if (!bounds.isValid) {
      throw ArgumentError.value(bounds, 'bounds', 'must be valid');
    }
    if (minZoom < 0 || maxZoom < minZoom || maxZoom > 20) {
      throw ArgumentError('Zoom range must be between 0 and 20.');
    }

    final coordinates = <TileCoordinate>[];
    for (var zoom = minZoom; zoom <= maxZoom; zoom++) {
      final north = _latToY(bounds.north, zoom);
      final south = _latToY(bounds.south, zoom);
      final ranges = bounds.crossesAntimeridian
          ? [
              (_lonToX(bounds.west, zoom), (1 << zoom) - 1),
              (0, _lonToX(bounds.east, zoom)),
            ]
          : [(_lonToX(bounds.west, zoom), _lonToX(bounds.east, zoom))];

      for (final range in ranges) {
        for (var x = range.$1; x <= range.$2; x++) {
          for (var y = north; y <= south; y++) {
            coordinates.add(TileCoordinate(zoom, x, y));
            if (coordinates.length > maxTiles) {
              throw StateError(
                'Selection exceeds the safety limit of $maxTiles tiles.',
              );
            }
          }
        }
      }
    }
    return TilePlan(coordinates);
  }

  int _lonToX(double longitude, int zoom) {
    final n = 1 << zoom;
    return (((longitude + 180) / 360) * n).floor().clamp(0, n - 1);
  }

  int _latToY(double latitude, int zoom) {
    final clamped = latitude.clamp(-_maxMercatorLatitude, _maxMercatorLatitude);
    final radians = clamped * math.pi / 180;
    final n = 1 << zoom;
    final y =
        (1 - math.log(math.tan(radians) + 1 / math.cos(radians)) / math.pi) / 2;
    return (y * n).floor().clamp(0, n - 1);
  }
}

/// Longitude of the western edge of tile column [x] at zoom [z].
double tileWestLongitude(int x, int z) => x / (1 << z) * 360.0 - 180.0;

/// Latitude of the northern edge of tile row [y] at zoom [z].
double tileNorthLatitude(int y, int z) {
  final n = math.pi * (1 - 2 * y / (1 << z));
  return math.atan((math.exp(n) - math.exp(-n)) / 2) * 180.0 / math.pi;
}

/// Whether the geographic footprint of tile [z]/[x]/[y] overlaps [bounds].
/// Antimeridian-crossing bounds are not handled here; callers exclude them.
bool tileIntersectsBounds(GeoBounds bounds, int z, int x, int y) {
  final west = tileWestLongitude(x, z);
  final east = tileWestLongitude(x + 1, z);
  final north = tileNorthLatitude(y, z);
  final south = tileNorthLatitude(y + 1, z);
  return west <= bounds.east &&
      east >= bounds.west &&
      south <= bounds.north &&
      north >= bounds.south;
}
