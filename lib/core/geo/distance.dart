import 'package:latlong2/latlong.dart';

/// Geodesic distance calculations shared by route, recording, and navigation
/// features.
///
/// Wraps `latlong2`'s haversine [Distance] implementation so call sites do
/// not need to depend on the calculation method directly and so tests can
/// reason about a single seam.
class GeoDistance {
  const GeoDistance();

  static const Distance _distance = Distance(roundResult: false);

  /// Great-circle distance between [a] and [b], in meters.
  double metersBetween(LatLng a, LatLng b) {
    if (a.latitude == b.latitude && a.longitude == b.longitude) return 0;
    return _distance.as(LengthUnit.Meter, a, b);
  }

  /// Total length of the polyline formed by [points], in meters.
  double pathLengthMeters(List<LatLng> points) {
    if (points.length < 2) return 0;
    var total = 0.0;
    for (var i = 1; i < points.length; i++) {
      total += metersBetween(points[i - 1], points[i]);
    }
    return total;
  }

  /// Initial bearing from [a] to [b] in degrees, `[0, 360)`.
  double bearingDegrees(LatLng a, LatLng b) {
    final bearing = _distance.bearing(a, b);
    return (bearing + 360) % 360;
  }
}
