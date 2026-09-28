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
    required this.alongRouteMeters,
    required this.segmentBearingDegrees,
  });

  /// The closest point on the polyline.
  final LatLng point;

  /// Distance from the query point to [point], in meters.
  final double distanceMeters;

  /// Index of the segment `[segmentIndex, segmentIndex + 1]` the point lies on.
  final int segmentIndex;

  /// Fraction `[0, 1]` along that segment where [point] lies.
  final double t;

  /// Distance from the start of the polyline to [point].
  final double alongRouteMeters;

  /// Direction of travel encoded by the projected segment.
  final double segmentBearingDegrees;
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
  final projections = projectionsOnPolyline(
    query,
    polyline,
    distance: distance,
  );
  PolylineProjection? best;
  for (final projection in projections) {
    if (best == null || projection.distanceMeters < best.distanceMeters) {
      best = projection;
    }
  }
  return best;
}

/// Projects [query] onto every segment, retaining each occurrence's position
/// along the polyline. Repeated or reversed geometry therefore remains
/// distinguishable even when several projections share the same coordinate.
List<PolylineProjection> projectionsOnPolyline(
  LatLng query,
  List<LatLng> polyline, {
  GeoDistance distance = const GeoDistance(),
}) {
  if (polyline.length < 2) return const [];

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

  final projections = <PolylineProjection>[];
  var alongRouteMeters = 0.0;
  for (var i = 0; i < polyline.length - 1; i++) {
    final (ax, ay) = local(polyline[i]);
    final (bx, by) = local(polyline[i + 1]);
    final dx = bx - ax;
    final dy = by - ay;
    final lengthSq = dx * dx + dy * dy;
    final segmentMeters = distance.metersBetween(polyline[i], polyline[i + 1]);

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
    projections.add(
      PolylineProjection(
        point: foot,
        distanceMeters: meters,
        segmentIndex: i,
        t: t,
        alongRouteMeters: alongRouteMeters + segmentMeters * t,
        segmentBearingDegrees: segmentMeters == 0
            ? 0
            : distance.bearingDegrees(polyline[i], polyline[i + 1]),
      ),
    );
    alongRouteMeters += segmentMeters;
  }
  return projections;
}

/// Selects the plausible projection nearest the runner's established progress.
///
/// Spatially overlapping route legs are first kept within
/// [distanceTieToleranceMeters] of the closest segment. Prior progress prevents
/// a large backward jump, while a reliable [headingDegrees] distinguishes an
/// outbound segment from the same geometry traversed in reverse.
PolylineProjection? nearestOnPolylineForProgress(
  LatLng query,
  List<LatLng> polyline, {
  required double completedRouteMeters,
  double? headingDegrees,
  double distanceTieToleranceMeters = 12,
  bool requireForward = false,
  GeoDistance distance = const GeoDistance(),
}) {
  final projections = projectionsOnPolyline(
    query,
    polyline,
    distance: distance,
  );
  if (projections.isEmpty) return null;
  final closestDistance = projections
      .map((projection) => projection.distanceMeters)
      .reduce(math.min);
  var candidates = projections
      .where(
        (projection) =>
            projection.distanceMeters <=
            closestDistance + distanceTieToleranceMeters,
      )
      .toList(growable: false);
  if (requireForward) {
    candidates = candidates
        .where(
          (projection) => projection.alongRouteMeters >= completedRouteMeters,
        )
        .toList(growable: false);
    if (candidates.isEmpty) return null;
  }

  double score(PolylineProjection projection) {
    final progressDelta = projection.alongRouteMeters - completedRouteMeters;
    final progress = progressDelta >= 0
        ? progressDelta
        : progressDelta.abs() + 50;
    final spatial = (projection.distanceMeters - closestDistance) * 4;
    final heading = headingDegrees == null || !headingDegrees.isFinite
        ? 0
        : _headingDifference(projection.segmentBearingDegrees, headingDegrees) *
              0.5;
    return progress + spatial + heading;
  }

  var best = candidates.first;
  var bestScore = score(best);
  for (final candidate in candidates.skip(1)) {
    final candidateScore = score(candidate);
    if (candidateScore < bestScore ||
        (candidateScore == bestScore &&
            candidate.alongRouteMeters > best.alongRouteMeters)) {
      best = candidate;
      bestScore = candidateScore;
    }
  }
  return best;
}

double _headingDifference(double left, double right) {
  var difference = (left - right).abs() % 360;
  if (difference > 180) difference = 360 - difference;
  return difference;
}
