import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'distance.dart';

/// The closest point on a polyline to a query point, with enough context to
/// stitch a route onto it.
class PolylineProjection {
  const PolylineProjection({
    required this.point,
    required this.distanceMeters,
    required this.segmentIndex,
    required this.t,
  });

  /// The closest point on the polyline.
  final LatLng point;

  /// Distance from the query point to [point], in meters.
  final double distanceMeters;

  /// Index of the segment `[segmentIndex, segmentIndex + 1]` the point lies on.
  final int segmentIndex;

  /// Fraction `[0, 1]` along that segment where [point] lies.
  final double t;
}

const double _earthRadiusMeters = 6378137.0;
const double _degToRad = math.pi / 180.0;

/// Returns the closest point on [polyline] to [query], or null when the
/// polyline has fewer than two points.
///
/// Projection uses a local equirectangular approximation centered on [query],
/// which is accurate for the short segments in vector map tiles.
PolylineProjection? nearestOnPolyline(
  LatLng query,
  List<LatLng> polyline, {
  GeoDistance distance = const GeoDistance(),
}) {
  if (polyline.length < 2) return null;

  final lonScale = math.cos(query.latitude * _degToRad);

  // Local east/north meters relative to the query point.
  (double, double) local(LatLng p) => (
    (p.longitude - query.longitude) * _degToRad * _earthRadiusMeters * lonScale,
    (p.latitude - query.latitude) * _degToRad * _earthRadiusMeters,
  );

  LatLng fromLocal(double east, double north) => LatLng(
    query.latitude + north / (_degToRad * _earthRadiusMeters),
    query.longitude + east / (_degToRad * _earthRadiusMeters * lonScale),
  );

  PolylineProjection? best;
  for (var i = 0; i < polyline.length - 1; i++) {
    final (ax, ay) = local(polyline[i]);
    final (bx, by) = local(polyline[i + 1]);
    final dx = bx - ax;
    final dy = by - ay;
    final lengthSq = dx * dx + dy * dy;

    double t;
    if (lengthSq == 0) {
      t = 0;
    } else {
      // Project the origin (query) onto segment A->B.
      t = ((-ax) * dx + (-ay) * dy) / lengthSq;
      t = t.clamp(0.0, 1.0);
    }

    final footEast = ax + t * dx;
    final footNorth = ay + t * dy;
    final foot = fromLocal(footEast, footNorth);
    final meters = distance.metersBetween(query, foot);

    if (best == null || meters < best.distanceMeters) {
      best = PolylineProjection(
        point: foot,
        distanceMeters: meters,
        segmentIndex: i,
        t: t,
      );
    }
  }
  return best;
}
