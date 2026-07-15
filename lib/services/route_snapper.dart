import 'package:latlong2/latlong.dart';

import '../core/geo/distance.dart';
import '../core/geo/polyline_snap.dart';
import 'trail_network.dart';

/// Snaps a drawn or imported route onto nearby real trails.
///
/// This "stitches" a route to an existing trail: where the route runs within
/// [snapMeters] of a trail in the [TrailNetwork], its points are pulled onto
/// that trail. The route is densified first so the snapped line follows the
/// trail's shape rather than cutting corners. Points with no nearby trail are
/// left unchanged, so a route that leaves the trail network is preserved.
class RouteSnapper {
  const RouteSnapper({
    this.snapMeters = 25,
    this.leaveMeters = 50,
    this.densifyMeters = 10,
    this.distance = const GeoDistance(),
  });

  /// Maximum distance from a trail for a point to be pulled onto it.
  final double snapMeters;

  /// Once the route is following a trail it stays on that trail until it is
  /// more than this far away. Keeping [leaveMeters] larger than [snapMeters]
  /// adds hysteresis so a route running along a sparse trail stays glued to it
  /// instead of flicking on and off between the trail's vertices; it only
  /// leaves the trail once it is clearly off it.
  final double leaveMeters;

  /// Route segments longer than this are subdivided before snapping.
  final double densifyMeters;

  final GeoDistance distance;

  List<LatLng> snap(List<LatLng> route, TrailNetwork network) {
    if (route.length < 2 || network.isEmpty) return route;

    final densified = _densify(route);
    final snapped = <LatLng>[];
    int? currentTrail;
    for (final point in densified) {
      TrailMatch? match;
      // Prefer staying on the trail we are already following (hysteresis): only
      // detach once the point is clearly beyond [leaveMeters].
      if (currentTrail != null) {
        final projection = nearestOnPolyline(
          point,
          network.trails[currentTrail].points,
        );
        if (projection != null && projection.distanceMeters <= leaveMeters) {
          match = TrailMatch(trailIndex: currentTrail, projection: projection);
        }
      }
      // Otherwise join the nearest trail only when the point is clearly on it.
      match ??= network.nearest(point, maxMeters: snapMeters);
      if (match != null) {
        currentTrail = match.trailIndex;
        snapped.add(match.projection.point);
      } else {
        currentTrail = null;
        snapped.add(point);
      }
    }
    return _dedupe(snapped);
  }

  List<LatLng> _densify(List<LatLng> route) {
    final result = <LatLng>[route.first];
    for (var i = 1; i < route.length; i++) {
      final a = route[i - 1];
      final b = route[i];
      final meters = distance.metersBetween(a, b);
      final steps = (meters / densifyMeters).floor();
      for (var s = 1; s < steps; s++) {
        final f = s / steps;
        result.add(
          LatLng(
            a.latitude + (b.latitude - a.latitude) * f,
            a.longitude + (b.longitude - a.longitude) * f,
          ),
        );
      }
      result.add(b);
    }
    return result;
  }

  List<LatLng> _dedupe(List<LatLng> points) {
    final result = <LatLng>[];
    for (final point in points) {
      if (result.isEmpty || distance.metersBetween(result.last, point) > 0.5) {
        result.add(point);
      }
    }
    return result;
  }
}
