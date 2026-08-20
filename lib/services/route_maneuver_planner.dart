import 'package:latlong2/latlong.dart';

import '../core/geo/distance.dart';
import '../core/geo/polyline_snap.dart';

enum ManeuverKind {
  straight,
  bearLeft,
  turnLeft,
  sharpLeft,
  uTurn,
  bearRight,
  turnRight,
  sharpRight,
}

class RouteManeuver {
  const RouteManeuver({
    required this.point,
    required this.alongRouteMeters,
    required this.turnDegrees,
    required this.isJunction,
  });

  final LatLng point;
  final double alongRouteMeters;

  /// Signed heading change: negative is left, positive is right.
  final double turnDegrees;
  final bool isJunction;

  int get roundedDegrees => turnDegrees.abs().round();

  ManeuverKind get kind {
    final magnitude = turnDegrees.abs();
    if (magnitude <= 15) return ManeuverKind.straight;
    if (magnitude >= 150) return ManeuverKind.uTurn;
    if (turnDegrees < 0) {
      if (magnitude <= 55) return ManeuverKind.bearLeft;
      if (magnitude <= 110) return ManeuverKind.turnLeft;
      return ManeuverKind.sharpLeft;
    }
    if (magnitude <= 55) return ManeuverKind.bearRight;
    if (magnitude <= 110) return ManeuverKind.turnRight;
    return ManeuverKind.sharpRight;
  }
}

class RouteManeuverPlanner {
  const RouteManeuverPlanner({
    this.turnLookaroundMeters = 15,
    this.minimumGeometryTurnDegrees = 30,
    this.junctionRouteToleranceMeters = 25,
    this.mergeDistanceMeters = 20,
    this.distance = const GeoDistance(),
  });

  final double turnLookaroundMeters;
  final double minimumGeometryTurnDegrees;
  final double junctionRouteToleranceMeters;
  final double mergeDistanceMeters;
  final GeoDistance distance;

  List<RouteManeuver> plan(
    List<LatLng> route, {
    List<LatLng> junctions = const [],
  }) {
    if (route.length < 2) return const [];
    final routeLength = distance.pathLengthMeters(route);
    if (routeLength <= turnLookaroundMeters * 2) return const [];
    final candidates = <RouteManeuver>[];

    for (final junction in junctions) {
      final projection = nearestOnPolyline(junction, route, distance: distance);
      if (projection == null ||
          projection.distanceMeters > junctionRouteToleranceMeters) {
        continue;
      }
      final along = alongRoute(route, projection);
      if (!_canSampleTurn(along, routeLength)) continue;
      candidates.add(
        RouteManeuver(
          point: projection.point,
          alongRouteMeters: along,
          turnDegrees: turnAt(route, along),
          isJunction: true,
        ),
      );
    }

    var along = 0.0;
    for (var index = 1; index < route.length - 1; index++) {
      along += distance.metersBetween(route[index - 1], route[index]);
      if (!_canSampleTurn(along, routeLength)) continue;
      final turn = turnAt(route, along);
      if (turn.abs() < minimumGeometryTurnDegrees) continue;
      candidates.add(
        RouteManeuver(
          point: route[index],
          alongRouteMeters: along,
          turnDegrees: turn,
          isJunction: false,
        ),
      );
    }

    candidates.sort(
      (left, right) => left.alongRouteMeters.compareTo(right.alongRouteMeters),
    );
    final merged = <RouteManeuver>[];
    for (final candidate in candidates) {
      if (merged.isEmpty ||
          candidate.alongRouteMeters - merged.last.alongRouteMeters >
              mergeDistanceMeters) {
        merged.add(candidate);
        continue;
      }
      final previous = merged.removeLast();
      final strongest = candidate.turnDegrees.abs() > previous.turnDegrees.abs()
          ? candidate
          : previous;
      merged.add(
        RouteManeuver(
          point: strongest.point,
          alongRouteMeters: strongest.alongRouteMeters,
          turnDegrees: strongest.turnDegrees,
          isJunction: previous.isJunction || candidate.isJunction,
        ),
      );
    }
    return merged;
  }

  bool _canSampleTurn(double along, double routeLength) =>
      along >= turnLookaroundMeters &&
      along <= routeLength - turnLookaroundMeters;

  double alongRoute(List<LatLng> route, PolylineProjection projection) {
    var meters = 0.0;
    for (var index = 0; index < projection.segmentIndex; index++) {
      meters += distance.metersBetween(route[index], route[index + 1]);
    }
    final segment = distance.metersBetween(
      route[projection.segmentIndex],
      route[projection.segmentIndex + 1],
    );
    return meters + segment * projection.t;
  }

  LatLng pointAlong(List<LatLng> route, double meters) {
    if (meters <= 0) return route.first;
    var remaining = meters;
    for (var index = 0; index < route.length - 1; index++) {
      final segment = distance.metersBetween(route[index], route[index + 1]);
      if (segment <= 0) continue;
      if (remaining <= segment) {
        final fraction = remaining / segment;
        return LatLng(
          route[index].latitude +
              (route[index + 1].latitude - route[index].latitude) * fraction,
          route[index].longitude +
              (route[index + 1].longitude - route[index].longitude) * fraction,
        );
      }
      remaining -= segment;
    }
    return route.last;
  }

  double turnAt(List<LatLng> route, double alongMeters) {
    final before = pointAlong(route, alongMeters - turnLookaroundMeters);
    final at = pointAlong(route, alongMeters);
    final after = pointAlong(route, alongMeters + turnLookaroundMeters);
    final incoming = distance.bearingDegrees(before, at);
    final outgoing = distance.bearingDegrees(at, after);
    var delta = outgoing - incoming;
    while (delta > 180) {
      delta -= 360;
    }
    while (delta < -180) {
      delta += 360;
    }
    return delta;
  }
}
