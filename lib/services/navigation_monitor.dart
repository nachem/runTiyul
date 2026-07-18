import 'package:latlong2/latlong.dart';

import '../core/geo/distance.dart';
import '../core/geo/polyline_snap.dart';

/// User-configurable rules for live navigation alerts: when and whether to fire.
class NavAlertConfig {
  const NavAlertConfig({
    this.offRouteEnabled = true,
    this.offRouteMeters = 30,
    this.offRoutePersistence = 3,
    this.junctionEnabled = true,
    this.junctionMeters = 25,
    this.feedbackMode = NavFeedbackMode.toneAndVoice,
  });

  /// Whether off-route alerts fire at all.
  final bool offRouteEnabled;

  /// Distance from the route that counts as off route, in meters.
  final double offRouteMeters;

  /// Consecutive off-route fixes required before alerting (a "time" guard
  /// against a single inaccurate GPS point).
  final int offRoutePersistence;

  /// Whether junction alerts fire at all.
  final bool junctionEnabled;

  /// Proximity to a junction that triggers an alert, in meters.
  final double junctionMeters;

  /// Audio/haptic treatment used when a navigation alert fires.
  final NavFeedbackMode feedbackMode;

  NavAlertConfig copyWith({
    bool? offRouteEnabled,
    double? offRouteMeters,
    int? offRoutePersistence,
    bool? junctionEnabled,
    double? junctionMeters,
    NavFeedbackMode? feedbackMode,
  }) {
    return NavAlertConfig(
      offRouteEnabled: offRouteEnabled ?? this.offRouteEnabled,
      offRouteMeters: offRouteMeters ?? this.offRouteMeters,
      offRoutePersistence: offRoutePersistence ?? this.offRoutePersistence,
      junctionEnabled: junctionEnabled ?? this.junctionEnabled,
      junctionMeters: junctionMeters ?? this.junctionMeters,
      feedbackMode: feedbackMode ?? this.feedbackMode,
    );
  }

  Map<String, dynamic> toJson() => {
    'offRouteEnabled': offRouteEnabled,
    'offRouteMeters': offRouteMeters,
    'offRoutePersistence': offRoutePersistence,
    'junctionEnabled': junctionEnabled,
    'junctionMeters': junctionMeters,
    'feedbackMode': feedbackMode.name,
  };

  factory NavAlertConfig.fromJson(Map<String, dynamic> json) {
    const fallback = NavAlertConfig();
    return NavAlertConfig(
      offRouteEnabled:
          json['offRouteEnabled'] as bool? ?? fallback.offRouteEnabled,
      offRouteMeters:
          (json['offRouteMeters'] as num?)?.toDouble() ??
          fallback.offRouteMeters,
      offRoutePersistence:
          (json['offRoutePersistence'] as num?)?.toInt() ??
          fallback.offRoutePersistence,
      junctionEnabled:
          json['junctionEnabled'] as bool? ?? fallback.junctionEnabled,
      junctionMeters:
          (json['junctionMeters'] as num?)?.toDouble() ??
          fallback.junctionMeters,
      feedbackMode: NavFeedbackMode.values.firstWhere(
        (mode) => mode.name == json['feedbackMode'],
        orElse: () => fallback.feedbackMode,
      ),
    );
  }
}

/// How a live alert reaches a runner. Every mode retains haptic feedback.
enum NavFeedbackMode { toneAndVoice, tones, voice, hapticsOnly }

extension NavFeedbackModeCapabilities on NavFeedbackMode {
  bool get usesTone =>
      this == NavFeedbackMode.toneAndVoice || this == NavFeedbackMode.tones;

  bool get usesVoice =>
      this == NavFeedbackMode.toneAndVoice || this == NavFeedbackMode.voice;
}

/// The alert produced on a single update, if any.
enum NavAlert { none, offRoute, junction }

/// Which way the planned route turns at an upcoming junction.
enum TurnDirection { straight, left, right }

/// The navigation state after processing a position update.
class NavStatus {
  const NavStatus({
    required this.offRoute,
    this.distanceToRouteMeters,
    this.junctionAhead,
    this.junctionDistanceMeters,
    this.junctionTurn,
    this.triggered = NavAlert.none,
  });

  final bool offRoute;
  final double? distanceToRouteMeters;

  /// Location of the next on-route junction within alert range, if any.
  final LatLng? junctionAhead;

  /// Distance to [junctionAhead] measured along the route, in meters.
  final double? junctionDistanceMeters;

  /// Which way the route turns at [junctionAhead].
  final TurnDirection? junctionTurn;

  final NavAlert triggered;

  static const idle = NavStatus(offRoute: false);
}

/// Watches live position against a route and nearby junctions, emitting alert
/// transitions according to [config]. Pure and deterministic so the alert
/// timing can be unit-tested without a device.
class NavigationMonitor {
  NavigationMonitor({
    this.config = const NavAlertConfig(),
    this.distance = const GeoDistance(),
  });

  NavAlertConfig config;
  final GeoDistance distance;

  /// Max distance a junction may sit from the route to count as on-route.
  static const double _junctionOnRouteToleranceMeters = 25;

  /// How far before/after a junction to sample the route heading for a turn.
  static const double _turnLookaheadMeters = 15;

  /// Turns smaller than this are reported as "continue straight".
  static const double _straightToleranceDegrees = 20;

  int _offRouteStreak = 0;
  bool _offRouteActive = false;
  LatLng? _lastJunction;

  void reset() {
    _offRouteStreak = 0;
    _offRouteActive = false;
    _lastJunction = null;
  }

  NavStatus update(
    LatLng position, {
    List<LatLng> route = const [],
    List<LatLng> junctions = const [],
  }) {
    var triggered = NavAlert.none;

    PolylineProjection? userProjection;
    double? distanceToRoute;
    if (route.length >= 2) {
      userProjection = nearestOnPolyline(position, route);
      distanceToRoute = userProjection?.distanceMeters;
    }

    if (config.offRouteEnabled && distanceToRoute != null) {
      if (distanceToRoute > config.offRouteMeters) {
        _offRouteStreak++;
        if (!_offRouteActive && _offRouteStreak >= config.offRoutePersistence) {
          _offRouteActive = true;
          triggered = NavAlert.offRoute;
        }
      } else {
        _offRouteStreak = 0;
        _offRouteActive = false;
      }
    }

    LatLng? junctionAhead;
    double? junctionDistance;
    TurnDirection? junctionTurn;
    if (config.junctionEnabled &&
        junctions.isNotEmpty &&
        route.length >= 2 &&
        userProjection != null) {
      final userAlong = _alongRoute(route, userProjection);
      LatLng? nearest;
      var nearestAhead = double.infinity;
      double? nearestAlong;
      for (final junction in junctions) {
        final projection = nearestOnPolyline(junction, route);
        if (projection == null) continue;
        // Only junctions the route actually passes through are decision points.
        if (projection.distanceMeters > _junctionOnRouteToleranceMeters) {
          continue;
        }
        final along = _alongRoute(route, projection);
        final ahead = along - userAlong;
        // Skip junctions already passed or still beyond the advance window.
        if (ahead <= 0 || ahead > config.junctionMeters) continue;
        if (ahead < nearestAhead) {
          nearestAhead = ahead;
          nearest = projection.point;
          nearestAlong = along;
        }
      }
      if (nearest != null && nearestAlong != null) {
        junctionAhead = nearest;
        junctionDistance = nearestAhead;
        junctionTurn = _turnAt(route, nearestAlong);
        final isNew =
            _lastJunction == null ||
            distance.metersBetween(_lastJunction!, nearest) >
                _junctionOnRouteToleranceMeters;
        if (isNew && triggered == NavAlert.none) {
          triggered = NavAlert.junction;
        }
        _lastJunction = nearest;
      } else {
        _lastJunction = null;
      }
    }

    return NavStatus(
      offRoute: _offRouteActive,
      distanceToRouteMeters: distanceToRoute,
      junctionAhead: junctionAhead,
      junctionDistanceMeters: junctionDistance,
      junctionTurn: junctionTurn,
      triggered: triggered,
    );
  }

  /// Distance from the route start to [projection], measured along the route.
  double _alongRoute(List<LatLng> route, PolylineProjection projection) {
    var meters = 0.0;
    for (var i = 0; i < projection.segmentIndex; i++) {
      meters += distance.metersBetween(route[i], route[i + 1]);
    }
    final start = route[projection.segmentIndex];
    final end = route[projection.segmentIndex + 1];
    return meters + distance.metersBetween(start, end) * projection.t;
  }

  /// The point [meters] along the route from its start, clamped to the ends.
  LatLng _pointAlong(List<LatLng> route, double meters) {
    if (meters <= 0) return route.first;
    var remaining = meters;
    for (var i = 0; i < route.length - 1; i++) {
      final segment = distance.metersBetween(route[i], route[i + 1]);
      if (segment <= 0) continue;
      if (remaining <= segment) {
        final t = remaining / segment;
        return LatLng(
          route[i].latitude + (route[i + 1].latitude - route[i].latitude) * t,
          route[i].longitude +
              (route[i + 1].longitude - route[i].longitude) * t,
        );
      }
      remaining -= segment;
    }
    return route.last;
  }

  /// Classifies how the route turns at the junction [alongMeters] into the
  /// route by comparing the heading just before and just after it.
  TurnDirection _turnAt(List<LatLng> route, double alongMeters) {
    final before = _pointAlong(route, alongMeters - _turnLookaheadMeters);
    final at = _pointAlong(route, alongMeters);
    final after = _pointAlong(route, alongMeters + _turnLookaheadMeters);
    final incoming = distance.bearingDegrees(before, at);
    final outgoing = distance.bearingDegrees(at, after);
    var delta = outgoing - incoming;
    while (delta > 180) {
      delta -= 360;
    }
    while (delta < -180) {
      delta += 360;
    }
    if (delta.abs() <= _straightToleranceDegrees) return TurnDirection.straight;
    return delta > 0 ? TurnDirection.right : TurnDirection.left;
  }
}
