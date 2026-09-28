import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../core/geo/distance.dart';
import '../core/geo/polyline_snap.dart';

class NavigationBackPlan {
  NavigationBackPlan({
    required List<LatLng> path,
    required this.destination,
    this.destinationAlongRouteMeters,
  }) : path = List.unmodifiable(path);

  final List<LatLng> path;
  final LatLng destination;
  final double? destinationAlongRouteMeters;
}

/// Builds a temporary route back without changing the saved route or activity.
/// A selected route is followed in either direction; free runs retrace accepted
/// GPS breadcrumbs in reverse.
class NavigationBackPlanner {
  const NavigationBackPlanner({this.distance = const GeoDistance()});

  final GeoDistance distance;

  NavigationBackPlan? planHome({
    required List<LatLng> plannedRoute,
    required List<LatLng> breadcrumbs,
    required double completedRouteMeters,
    LatLng? currentPosition,
    double? headingDegrees,
  }) {
    if (plannedRoute.length >= 2) {
      return planToRoutePoint(
        plannedRoute: plannedRoute,
        target: plannedRoute.first,
        completedRouteMeters: completedRouteMeters,
        currentPosition: currentPosition,
        headingDegrees: headingDegrees,
      );
    }
    if (breadcrumbs.length < 2) return null;
    final reversed = _deduplicate([?currentPosition, ...breadcrumbs.reversed]);
    if (reversed.length < 2 || distance.pathLengthMeters(reversed) < 5) {
      return null;
    }
    return NavigationBackPlan(path: reversed, destination: breadcrumbs.first);
  }

  NavigationBackPlan? planToRoutePoint({
    required List<LatLng> plannedRoute,
    required LatLng target,
    required double completedRouteMeters,
    LatLng? currentPosition,
    double? headingDegrees,
  }) {
    if (plannedRoute.length < 2) return null;
    final routeLength = distance.pathLengthMeters(plannedRoute);
    final establishedProgress = completedRouteMeters
        .clamp(0, routeLength)
        .toDouble();
    final currentProjection = currentPosition == null
        ? null
        : nearestOnPolylineForProgress(
            currentPosition,
            plannedRoute,
            completedRouteMeters: establishedProgress,
            headingDegrees: headingDegrees,
            distance: distance,
          );
    final currentAlong =
        currentProjection?.alongRouteMeters ?? establishedProgress;
    final targetProjections = projectionsOnPolyline(
      target,
      plannedRoute,
      distance: distance,
    );
    if (targetProjections.isEmpty) return null;
    final closestDistance = targetProjections
        .map((projection) => projection.distanceMeters)
        .reduce(math.min);
    if (closestDistance > 50) return null;
    final candidates = targetProjections.where(
      (projection) => projection.distanceMeters <= closestDistance + 12,
    );
    PolylineProjection? destinationProjection;
    for (final candidate in candidates) {
      final selected = destinationProjection;
      if (selected == null ||
          (candidate.alongRouteMeters - currentAlong).abs() <
              (selected.alongRouteMeters - currentAlong).abs()) {
        destinationProjection = candidate;
      }
    }
    if (destinationProjection == null) return null;
    final destinationAlong = destinationProjection.alongRouteMeters;
    if ((destinationAlong - currentAlong).abs() < 5) return null;
    final path = _sliceRoute(plannedRoute, currentAlong, destinationAlong);
    if (path.length < 2 || distance.pathLengthMeters(path) < 5) return null;
    return NavigationBackPlan(
      path: path,
      destination: destinationProjection.point,
      destinationAlongRouteMeters: destinationAlong,
    );
  }

  List<LatLng> remainingPath(List<LatLng> path, double completedMeters) {
    if (path.length < 2) return path;
    final length = distance.pathLengthMeters(path);
    if (completedMeters <= 0) return path;
    if (completedMeters >= length) return [path.last];
    return _sliceRoute(path, completedMeters, length);
  }

  List<LatLng> _sliceRoute(
    List<LatLng> route,
    double fromMeters,
    double toMeters,
  ) {
    if (fromMeters > toMeters) {
      return _sliceRoute(
        route,
        toMeters,
        fromMeters,
      ).reversed.toList(growable: false);
    }
    final cumulative = <double>[0];
    for (var index = 0; index + 1 < route.length; index++) {
      cumulative.add(
        cumulative.last +
            distance.metersBetween(route[index], route[index + 1]),
      );
    }
    final points = <LatLng>[_pointAlong(route, cumulative, fromMeters)];
    for (var index = 1; index + 1 < route.length; index++) {
      if (cumulative[index] > fromMeters && cumulative[index] < toMeters) {
        points.add(route[index]);
      }
    }
    points.add(_pointAlong(route, cumulative, toMeters));
    return _deduplicate(points);
  }

  LatLng _pointAlong(
    List<LatLng> route,
    List<double> cumulative,
    double meters,
  ) {
    final clamped = meters.clamp(0, cumulative.last);
    for (var index = 0; index + 1 < route.length; index++) {
      final segmentEnd = cumulative[index + 1];
      if (clamped > segmentEnd) continue;
      final segmentLength = segmentEnd - cumulative[index];
      if (segmentLength <= 0) return route[index];
      final fraction = (clamped - cumulative[index]) / segmentLength;
      return LatLng(
        route[index].latitude +
            (route[index + 1].latitude - route[index].latitude) * fraction,
        route[index].longitude +
            (route[index + 1].longitude - route[index].longitude) * fraction,
      );
    }
    return route.last;
  }

  List<LatLng> _deduplicate(List<LatLng> points) {
    final result = <LatLng>[];
    for (final point in points) {
      if (result.isEmpty || distance.metersBetween(result.last, point) > 0.01) {
        result.add(point);
      }
    }
    return result;
  }
}
