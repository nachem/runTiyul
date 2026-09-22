import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../core/geo/distance.dart';
import '../core/geo/polyline_snap.dart';
import 'route_maneuver_planner.dart';
import 'trail_network.dart';
import 'trail_router.dart';

class ForwardRouteRecoveryResult {
  const ForwardRouteRecoveryResult({
    required this.path,
    required this.reconnectPoint,
    required this.reconnectAlongRouteMeters,
    required this.pathDistanceMeters,
    required this.initialBearingDegrees,
  });

  final List<LatLng> path;
  final LatLng reconnectPoint;
  final double reconnectAlongRouteMeters;
  final double pathDistanceMeters;
  final double initialBearingDegrees;
}

class ForwardRouteRecovery {
  const ForwardRouteRecovery({
    this.maxTrailSnapMeters = 25,
    this.reconnectToleranceMeters = 8,
    this.minimumReconnectAheadMeters = 30,
    this.candidateStepMeters = 30,
    this.maximumSearchAheadMeters = 3000,
    this.maximumInitialTurnDegrees = 75,
    this.distance = const GeoDistance(),
    this.maneuverPlanner = const RouteManeuverPlanner(),
  });

  final double maxTrailSnapMeters;
  final double reconnectToleranceMeters;
  final double minimumReconnectAheadMeters;
  final double candidateStepMeters;
  final double maximumSearchAheadMeters;
  final double maximumInitialTurnDegrees;
  final GeoDistance distance;
  final RouteManeuverPlanner maneuverPlanner;

  ForwardRouteRecoveryResult? advance(
    ForwardRouteRecoveryResult previous, {
    required LatLng position,
    required double headingDegrees,
  }) {
    final projection = nearestOnPolyline(position, previous.path);
    if (projection == null || projection.distanceMeters > maxTrailSnapMeters) {
      return null;
    }
    final path = [
      projection.point,
      ...previous.path.skip(projection.segmentIndex + 1),
    ];
    final bearing = _initialBearing(path);
    if (bearing == null ||
        _headingDifference(bearing, headingDegrees) >
            maximumInitialTurnDegrees) {
      return null;
    }
    return ForwardRouteRecoveryResult(
      path: path,
      reconnectPoint: previous.reconnectPoint,
      reconnectAlongRouteMeters: previous.reconnectAlongRouteMeters,
      pathDistanceMeters: distance.pathLengthMeters(path),
      initialBearingDegrees: bearing,
    );
  }

  ForwardRouteRecoveryResult? recover({
    required LatLng position,
    required double headingDegrees,
    required List<LatLng> plannedRoute,
    required double completedRouteMeters,
    required TrailNetwork network,
  }) {
    if (plannedRoute.length < 2 ||
        network.isEmpty ||
        !headingDegrees.isFinite) {
      return null;
    }
    final router = TrailRouter(network);
    final current = router.snap(position, maxMeters: maxTrailSnapMeters);
    if (current == null) return null;

    final routeLength = distance.pathLengthMeters(plannedRoute);
    final searchStart = completedRouteMeters + minimumReconnectAheadMeters;
    final searchEnd = math.min(
      routeLength,
      searchStart + maximumSearchAheadMeters,
    );
    if (searchStart > routeLength) return null;

    final candidateDistances = <double>[];
    for (
      var along = searchStart;
      along <= searchEnd;
      along += candidateStepMeters
    ) {
      candidateDistances.add(along);
    }
    if (candidateDistances.isEmpty || candidateDistances.last < searchEnd) {
      candidateDistances.add(searchEnd);
    }

    final targets = <TrailAnchor>[];
    for (final along in candidateDistances) {
      final routePoint = maneuverPlanner.pointAlong(plannedRoute, along);
      targets.addAll(
        router.snapCandidates(routePoint, maxMeters: reconnectToleranceMeters),
      );
    }
    final best = router.buildConnectedLegToAny(
      current,
      targets,
      headingDegrees: headingDegrees,
      maximumInitialTurnDegrees: maximumInitialTurnDegrees,
      maximumDistanceMeters: maximumSearchAheadMeters * 2,
    );
    if (best == null || best.path.length < 2) return null;
    final reconnect = _firstForwardReconnect(
      best.path,
      plannedRoute,
      minimumAlongMeters: searchStart,
    );
    if (reconnect == null) return null;
    final initialBearing = _initialBearing(reconnect.path);
    if (initialBearing == null ||
        _headingDifference(initialBearing, headingDegrees) >
            maximumInitialTurnDegrees) {
      return null;
    }
    return ForwardRouteRecoveryResult(
      path: reconnect.path,
      reconnectPoint: reconnect.point,
      reconnectAlongRouteMeters: reconnect.alongRouteMeters,
      pathDistanceMeters: distance.pathLengthMeters(reconnect.path),
      initialBearingDegrees: initialBearing,
    );
  }

  ({List<LatLng> path, LatLng point, double alongRouteMeters})?
  _firstForwardReconnect(
    List<LatLng> path,
    List<LatLng> plannedRoute, {
    required double minimumAlongMeters,
  }) {
    for (var index = 1; index < path.length; index++) {
      final projection = nearestOnPolyline(
        path[index],
        plannedRoute,
        distance: distance,
      );
      if (projection == null ||
          projection.distanceMeters > reconnectToleranceMeters) {
        continue;
      }
      final along = maneuverPlanner.alongRoute(plannedRoute, projection);
      if (along < minimumAlongMeters) continue;
      return (
        path: path.sublist(0, index + 1),
        point: path[index],
        alongRouteMeters: along,
      );
    }
    return null;
  }

  double? _initialBearing(List<LatLng> path) {
    for (var index = 1; index < path.length; index++) {
      if (distance.metersBetween(path.first, path[index]) < 3) continue;
      return distance.bearingDegrees(path.first, path[index]);
    }
    return null;
  }

  double _headingDifference(double left, double right) {
    var difference = (left - right).abs() % 360;
    if (difference > 180) difference = 360 - difference;
    return difference;
  }
}
