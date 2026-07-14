import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// A rectangular geographic bounding box in WGS84 degrees.
///
/// This is a plain-Dart value type (no Flutter dependency) so it can be used
/// throughout the domain layer. `latlong2`'s [LatLng] is reused as the shared
/// coordinate type across the app instead of introducing a duplicate point
/// type, since it has no Flutter dependency either and is already required by
/// the map rendering feature.
class GeoBounds {
  const GeoBounds({
    required this.north,
    required this.south,
    required this.east,
    required this.west,
  });

  /// Builds bounds that contain both corners, regardless of the order they
  /// are supplied in.
  factory GeoBounds.fromPoints(LatLng a, LatLng b) {
    return GeoBounds(
      north: math.max(a.latitude, b.latitude),
      south: math.min(a.latitude, b.latitude),
      east: math.max(a.longitude, b.longitude),
      west: math.min(a.longitude, b.longitude),
    );
  }

  /// Builds the smallest bounds containing every point in [points].
  ///
  /// Throws [ArgumentError] if [points] is empty.
  factory GeoBounds.fromTrack(Iterable<LatLng> points) {
    if (points.isEmpty) {
      throw ArgumentError.value(points, 'points', 'must not be empty');
    }
    var north = -90.0, south = 90.0, east = -180.0, west = 180.0;
    for (final p in points) {
      north = math.max(north, p.latitude);
      south = math.min(south, p.latitude);
      east = math.max(east, p.longitude);
      west = math.min(west, p.longitude);
    }
    return GeoBounds(north: north, south: south, east: east, west: west);
  }

  final double north;
  final double south;
  final double east;
  final double west;

  /// True if this describes a coherent, non-degenerate rectangle within
  /// valid Earth coordinate ranges.
  bool get isValid =>
      north.isFinite &&
      south.isFinite &&
      east.isFinite &&
      west.isFinite &&
      north <= 90 &&
      south >= -90 &&
      north > south &&
      east >= -180 &&
      east <= 180 &&
      west >= -180 &&
      west <= 180;

  /// True if this box spans the antimeridian (west edge is numerically east
  /// of the east edge, e.g. west=170, east=-170).
  bool get crossesAntimeridian => west > east;

  LatLng get center => LatLng((north + south) / 2, _centerLongitude());

  double _centerLongitude() {
    if (!crossesAntimeridian) return (east + west) / 2;
    var span = (east + 360) - west;
    var center = west + span / 2;
    if (center > 180) center -= 360;
    return center;
  }

  /// Returns a new [GeoBounds] expanded outward by approximately
  /// [meters] on every edge.
  GeoBounds padMeters(double meters) {
    if (meters <= 0) return this;
    const metersPerDegreeLat = 111320.0;
    final latPad = meters / metersPerDegreeLat;
    final referenceLat = math.max(north.abs(), south.abs());
    final metersPerDegreeLon =
        metersPerDegreeLat * math.cos(referenceLat * math.pi / 180).abs();
    final lonPad = metersPerDegreeLon > 1 ? meters / metersPerDegreeLon : 180.0;
    return GeoBounds(
      north: math.min(90, north + latPad),
      south: math.max(-90, south - latPad),
      east: _clampLon(east + lonPad),
      west: _clampLon(west - lonPad),
    );
  }

  double _clampLon(double lon) {
    var normalized = lon;
    while (normalized > 180) {
      normalized -= 360;
    }
    while (normalized < -180) {
      normalized += 360;
    }
    return normalized;
  }

  bool contains(LatLng point) {
    final latOk = point.latitude <= north && point.latitude >= south;
    if (!latOk) return false;
    if (!crossesAntimeridian) {
      return point.longitude <= east && point.longitude >= west;
    }
    return point.longitude >= west || point.longitude <= east;
  }

  @override
  bool operator ==(Object other) =>
      other is GeoBounds &&
      other.north == north &&
      other.south == south &&
      other.east == east &&
      other.west == west;

  @override
  int get hashCode => Object.hash(north, south, east, west);

  @override
  String toString() =>
      'GeoBounds(north: $north, south: $south, east: $east, west: $west)';
}
