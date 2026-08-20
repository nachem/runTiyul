import 'package:latlong2/latlong.dart';

import '../core/geo/distance.dart';
import '../core/geo/polyline_snap.dart';
import 'route_maneuver_planner.dart';

/// User-configurable rules for live navigation alerts: when and whether to fire.
class NavAlertConfig {
  const NavAlertConfig({
    this.offRouteEnabled = true,
    this.offRouteMeters = 30,
    this.offRoutePersistence = 3,
    this.offRouteReminderSeconds = 20,
    this.junctionEnabled = true,
    this.junctionMeters = 25,
    this.progressEnabled = true,
    this.progressIntervalMode = ProgressIntervalMode.distance,
    this.progressDistanceMeters = 1000,
    this.progressIntervalMinutes = 10,
    this.feedbackMode = NavFeedbackMode.toneAndVoice,
  });

  /// Whether off-route alerts fire at all.
  final bool offRouteEnabled;

  /// Distance from the route that counts as off route, in meters.
  final double offRouteMeters;

  /// Consecutive off-route fixes required before alerting (a "time" guard
  /// against a single inaccurate GPS point).
  final int offRoutePersistence;

  /// Seconds between guidance updates while the runner remains off route.
  final int offRouteReminderSeconds;

  /// Whether junction alerts fire at all.
  final bool junctionEnabled;

  /// Proximity to a junction that triggers an alert, in meters.
  final double junctionMeters;

  /// Whether calm on-route completion/remaining updates are announced.
  final bool progressEnabled;
  final ProgressIntervalMode progressIntervalMode;
  final double progressDistanceMeters;
  final int progressIntervalMinutes;

  /// Audio/haptic treatment used when a navigation alert fires.
  final NavFeedbackMode feedbackMode;

  NavAlertConfig copyWith({
    bool? offRouteEnabled,
    double? offRouteMeters,
    int? offRoutePersistence,
    int? offRouteReminderSeconds,
    bool? junctionEnabled,
    double? junctionMeters,
    bool? progressEnabled,
    ProgressIntervalMode? progressIntervalMode,
    double? progressDistanceMeters,
    int? progressIntervalMinutes,
    NavFeedbackMode? feedbackMode,
  }) {
    return NavAlertConfig(
      offRouteEnabled: offRouteEnabled ?? this.offRouteEnabled,
      offRouteMeters: offRouteMeters ?? this.offRouteMeters,
      offRoutePersistence: offRoutePersistence ?? this.offRoutePersistence,
      offRouteReminderSeconds:
          offRouteReminderSeconds ?? this.offRouteReminderSeconds,
      junctionEnabled: junctionEnabled ?? this.junctionEnabled,
      junctionMeters: junctionMeters ?? this.junctionMeters,
      progressEnabled: progressEnabled ?? this.progressEnabled,
      progressIntervalMode: progressIntervalMode ?? this.progressIntervalMode,
      progressDistanceMeters:
          progressDistanceMeters ?? this.progressDistanceMeters,
      progressIntervalMinutes:
          progressIntervalMinutes ?? this.progressIntervalMinutes,
      feedbackMode: feedbackMode ?? this.feedbackMode,
    );
  }

  Map<String, dynamic> toJson() => {
    'offRouteEnabled': offRouteEnabled,
    'offRouteMeters': offRouteMeters,
    'offRoutePersistence': offRoutePersistence,
    'offRouteReminderSeconds': offRouteReminderSeconds,
    'junctionEnabled': junctionEnabled,
    'junctionMeters': junctionMeters,
    'progressEnabled': progressEnabled,
    'progressIntervalMode': progressIntervalMode.name,
    'progressDistanceMeters': progressDistanceMeters,
    'progressIntervalMinutes': progressIntervalMinutes,
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
      offRouteReminderSeconds:
          (json['offRouteReminderSeconds'] as num?)?.toInt() ??
          fallback.offRouteReminderSeconds,
      junctionEnabled:
          json['junctionEnabled'] as bool? ?? fallback.junctionEnabled,
      junctionMeters:
          (json['junctionMeters'] as num?)?.toDouble() ??
          fallback.junctionMeters,
      progressEnabled:
          json['progressEnabled'] as bool? ?? fallback.progressEnabled,
      progressIntervalMode: ProgressIntervalMode.values.firstWhere(
        (mode) => mode.name == json['progressIntervalMode'],
        orElse: () => fallback.progressIntervalMode,
      ),
      progressDistanceMeters:
          (json['progressDistanceMeters'] as num?)?.toDouble() ??
          fallback.progressDistanceMeters,
      progressIntervalMinutes:
          (json['progressIntervalMinutes'] as num?)?.toInt() ??
          fallback.progressIntervalMinutes,
      feedbackMode: NavFeedbackMode.values.firstWhere(
        (mode) => mode.name == json['feedbackMode'],
        orElse: () => fallback.feedbackMode,
      ),
    );
  }
}

/// How a live alert reaches a runner. Every mode retains haptic feedback.
enum NavFeedbackMode { toneAndVoice, tones, voice, hapticsOnly }

enum ProgressIntervalMode { distance, time }

extension NavFeedbackModeCapabilities on NavFeedbackMode {
  bool get usesTone =>
      this == NavFeedbackMode.toneAndVoice || this == NavFeedbackMode.tones;

  bool get usesVoice =>
      this == NavFeedbackMode.toneAndVoice || this == NavFeedbackMode.voice;
}

/// The alert produced on a single update, if any.
enum NavAlert { none, offRoute, offRouteReminder, junction, progress }

/// Which way the planned route turns at an upcoming junction.
enum TurnDirection { straight, left, right }

enum ManeuverPhase { advance, apex }

/// Runner-relative direction of the shortest path back to the route.
enum RouteRelativeDirection { ahead, left, right, behind }

/// Whether the latest off-route reminder shows recovery or deterioration.
enum OffRouteTrend { approaching, steady, movingAway }

/// The navigation state after processing a position update.
class NavStatus {
  const NavStatus({
    required this.offRoute,
    this.distanceToRouteMeters,
    this.nearestRoutePoint,
    this.bearingToRouteDegrees,
    this.routeRelativeDirection,
    this.offRouteTrend,
    this.forwardRecoveryPath = const [],
    this.forwardRecoveryDistanceMeters,
    this.forwardRecoveryBearingDegrees,
    this.forwardReconnectPoint,
    this.routeCompletedMeters,
    this.routeRemainingMeters,
    this.junctionAhead,
    this.junctionDistanceMeters,
    this.junctionTurn,
    this.junctionTurnDegrees,
    this.maneuverPhase,
    this.followingTurnDegrees,
    this.followingTurnDistanceMeters,
    this.triggered = NavAlert.none,
  });

  final bool offRoute;
  final double? distanceToRouteMeters;

  /// Closest point on the planned route and the direction needed to reach it.
  final LatLng? nearestRoutePoint;
  final double? bearingToRouteDegrees;
  final RouteRelativeDirection? routeRelativeDirection;
  final OffRouteTrend? offRouteTrend;

  /// Strict mapped-way recovery that reconnects ahead without backtracking.
  final List<LatLng> forwardRecoveryPath;
  final double? forwardRecoveryDistanceMeters;
  final double? forwardRecoveryBearingDegrees;
  final LatLng? forwardReconnectPoint;

  bool get hasForwardRecovery => forwardRecoveryPath.length >= 2;

  /// Monotonic progress along the planned route, not raw activity distance.
  final double? routeCompletedMeters;
  final double? routeRemainingMeters;

  /// Location of the next on-route junction within alert range, if any.
  final LatLng? junctionAhead;

  /// Distance to [junctionAhead] measured along the route, in meters.
  final double? junctionDistanceMeters;

  /// Which way the route turns at [junctionAhead].
  final TurnDirection? junctionTurn;

  /// Signed exact heading change: negative is left, positive is right.
  final double? junctionTurnDegrees;
  final ManeuverPhase? maneuverPhase;

  /// A second maneuver close enough to announce with the first.
  final double? followingTurnDegrees;
  final double? followingTurnDistanceMeters;

  final NavAlert triggered;

  static const idle = NavStatus(offRoute: false);

  NavStatus withForwardRecovery({
    required List<LatLng> path,
    required double distanceMeters,
    required double bearingDegrees,
    required LatLng reconnectPoint,
    NavAlert? triggered,
  }) => NavStatus(
    offRoute: offRoute,
    distanceToRouteMeters: distanceToRouteMeters,
    nearestRoutePoint: nearestRoutePoint,
    bearingToRouteDegrees: bearingToRouteDegrees,
    routeRelativeDirection: routeRelativeDirection,
    offRouteTrend: offRouteTrend,
    forwardRecoveryPath: path,
    forwardRecoveryDistanceMeters: distanceMeters,
    forwardRecoveryBearingDegrees: bearingDegrees,
    forwardReconnectPoint: reconnectPoint,
    routeCompletedMeters: routeCompletedMeters,
    routeRemainingMeters: routeRemainingMeters,
    junctionAhead: junctionAhead,
    junctionDistanceMeters: junctionDistanceMeters,
    junctionTurn: junctionTurn,
    junctionTurnDegrees: junctionTurnDegrees,
    maneuverPhase: maneuverPhase,
    followingTurnDegrees: followingTurnDegrees,
    followingTurnDistanceMeters: followingTurnDistanceMeters,
    triggered: triggered ?? this.triggered,
  );
}

/// Watches live position against a route and nearby junctions, emitting alert
/// transitions according to [config]. Pure and deterministic so the alert
/// timing can be unit-tested without a device.
class NavigationMonitor {
  NavigationMonitor({
    this.config = const NavAlertConfig(),
    this.distance = const GeoDistance(),
    this.maneuverPlanner = const RouteManeuverPlanner(),
  });

  NavAlertConfig config;
  final GeoDistance distance;
  final RouteManeuverPlanner maneuverPlanner;

  static const double _trendToleranceMeters = 5;
  static const double _maneuverApexToleranceMeters = 8;
  static const double _maneuverOvershootToleranceMeters = 25;
  static const double _combinedManeuverDistanceMeters = 45;

  int _offRouteStreak = 0;
  bool _offRouteActive = false;
  DateTime? _lastOffRouteCueAt;
  double? _distanceAtLastOffRouteCue;
  double _maxRouteProgressMeters = 0;
  double? _nextProgressMeters;
  Duration? _nextProgressElapsed;
  List<LatLng>? _maneuverRoute;
  List<LatLng>? _maneuverJunctions;
  List<RouteManeuver> _maneuvers = const [];
  int _maneuverIndex = 0;
  bool _advanceAnnounced = false;
  bool _apexAnnounced = false;

  void reset() {
    _offRouteStreak = 0;
    _offRouteActive = false;
    _lastOffRouteCueAt = null;
    _distanceAtLastOffRouteCue = null;
    _maxRouteProgressMeters = 0;
    _nextProgressMeters = null;
    _nextProgressElapsed = null;
    _maneuverRoute = null;
    _maneuverJunctions = null;
    _maneuvers = const [];
    _maneuverIndex = 0;
    _advanceAnnounced = false;
    _apexAnnounced = false;
  }

  NavStatus update(
    LatLng position, {
    List<LatLng> route = const [],
    List<LatLng> junctions = const [],
    double? headingDegrees,
    DateTime? timestamp,
    Duration elapsed = Duration.zero,
  }) {
    var triggered = NavAlert.none;
    var progressDue = false;
    OffRouteTrend? offRouteTrend;

    PolylineProjection? userProjection;
    double? distanceToRoute;
    double? userAlong;
    if (route.length >= 2) {
      userProjection = nearestOnPolyline(position, route);
      distanceToRoute = userProjection?.distanceMeters;
      if (userProjection != null) {
        userAlong = maneuverPlanner.alongRoute(route, userProjection);
      }
    }

    if (config.offRouteEnabled && distanceToRoute != null) {
      if (distanceToRoute > config.offRouteMeters) {
        _offRouteStreak++;
        if (!_offRouteActive && _offRouteStreak >= config.offRoutePersistence) {
          _offRouteActive = true;
          triggered = NavAlert.offRoute;
          _lastOffRouteCueAt = timestamp;
          _distanceAtLastOffRouteCue = distanceToRoute;
        } else if (_offRouteActive &&
            timestamp != null &&
            _lastOffRouteCueAt != null &&
            timestamp.difference(_lastOffRouteCueAt!).inSeconds >=
                config.offRouteReminderSeconds) {
          final previousDistance = _distanceAtLastOffRouteCue;
          final change = previousDistance == null
              ? 0
              : distanceToRoute - previousDistance;
          offRouteTrend = change <= -_trendToleranceMeters
              ? OffRouteTrend.approaching
              : change >= _trendToleranceMeters
              ? OffRouteTrend.movingAway
              : OffRouteTrend.steady;
          triggered = NavAlert.offRouteReminder;
          _lastOffRouteCueAt = timestamp;
          _distanceAtLastOffRouteCue = distanceToRoute;
        }
      } else {
        _offRouteStreak = 0;
        _offRouteActive = false;
        _lastOffRouteCueAt = null;
        _distanceAtLastOffRouteCue = null;
      }
    }

    double? routeCompleted;
    double? routeRemaining;
    if (route.length >= 2 && userProjection != null) {
      final projectedProgress = userAlong!;
      if (projectedProgress > _maxRouteProgressMeters) {
        _maxRouteProgressMeters = projectedProgress;
      }
      final routeLength = distance.pathLengthMeters(route);
      routeCompleted = _maxRouteProgressMeters.clamp(0, routeLength);
      routeRemaining = (routeLength - routeCompleted).clamp(0, routeLength);
      if (config.progressEnabled && !_offRouteActive) {
        if (config.progressIntervalMode == ProgressIntervalMode.distance) {
          final interval = config.progressDistanceMeters;
          _nextProgressMeters ??=
              ((routeCompleted / interval).floor() + 1) * interval;
          if (routeCompleted >= _nextProgressMeters!) {
            progressDue = true;
            while (_nextProgressMeters! <= routeCompleted) {
              _nextProgressMeters = _nextProgressMeters! + interval;
            }
          }
        } else {
          final interval = Duration(minutes: config.progressIntervalMinutes);
          _nextProgressElapsed ??= Duration(
            minutes:
                (elapsed.inMinutes ~/ config.progressIntervalMinutes + 1) *
                config.progressIntervalMinutes,
          );
          if (elapsed >= _nextProgressElapsed!) {
            progressDue = true;
            while (_nextProgressElapsed! <= elapsed) {
              _nextProgressElapsed = _nextProgressElapsed! + interval;
            }
          }
        }
      }
    }

    LatLng? junctionAhead;
    double? junctionDistance;
    TurnDirection? junctionTurn;
    double? junctionTurnDegrees;
    ManeuverPhase? maneuverPhase;
    double? followingTurnDegrees;
    double? followingTurnDistance;
    if (config.junctionEnabled &&
        route.length >= 2 &&
        userAlong != null &&
        !_offRouteActive) {
      _ensureManeuvers(route, junctions);
      _skipCompletedManeuvers(userAlong);
      if (_maneuverIndex < _maneuvers.length) {
        final maneuver = _maneuvers[_maneuverIndex];
        final ahead = maneuver.alongRouteMeters - userAlong;
        if (ahead <= config.junctionMeters &&
            ahead >= -_maneuverOvershootToleranceMeters) {
          junctionAhead = maneuver.point;
          junctionDistance = ahead.clamp(0, double.infinity);
          junctionTurnDegrees = maneuver.turnDegrees;
          junctionTurn = _turnDirection(maneuver.turnDegrees);
          maneuverPhase = ahead <= _maneuverApexToleranceMeters
              ? ManeuverPhase.apex
              : ManeuverPhase.advance;

          if (_maneuverIndex + 1 < _maneuvers.length) {
            final following = _maneuvers[_maneuverIndex + 1];
            final separation =
                following.alongRouteMeters - maneuver.alongRouteMeters;
            if (separation <= _combinedManeuverDistanceMeters) {
              followingTurnDegrees = following.turnDegrees;
              followingTurnDistance = separation;
            }
          }

          if (triggered == NavAlert.none) {
            if (!_apexAnnounced && ahead <= _maneuverApexToleranceMeters) {
              triggered = NavAlert.junction;
              maneuverPhase = ManeuverPhase.apex;
              _apexAnnounced = true;
            } else if (!_advanceAnnounced &&
                ahead > _maneuverApexToleranceMeters) {
              triggered = NavAlert.junction;
              maneuverPhase = ManeuverPhase.advance;
              _advanceAnnounced = true;
            }
          }
        }
      }
    }

    if (triggered == NavAlert.none && progressDue) {
      triggered = NavAlert.progress;
    }

    return NavStatus(
      offRoute: _offRouteActive,
      distanceToRouteMeters: distanceToRoute,
      nearestRoutePoint: userProjection?.point,
      bearingToRouteDegrees: userProjection == null
          ? null
          : distance.bearingDegrees(position, userProjection.point),
      routeRelativeDirection: userProjection == null || headingDegrees == null
          ? null
          : _relativeDirection(
              headingDegrees,
              distance.bearingDegrees(position, userProjection.point),
            ),
      offRouteTrend: offRouteTrend,
      routeCompletedMeters: routeCompleted,
      routeRemainingMeters: routeRemaining,
      junctionAhead: junctionAhead,
      junctionDistanceMeters: junctionDistance,
      junctionTurn: junctionTurn,
      junctionTurnDegrees: junctionTurnDegrees,
      maneuverPhase: maneuverPhase,
      followingTurnDegrees: followingTurnDegrees,
      followingTurnDistanceMeters: followingTurnDistance,
      triggered: triggered,
    );
  }

  RouteRelativeDirection _relativeDirection(
    double headingDegrees,
    double targetBearingDegrees,
  ) {
    var delta = targetBearingDegrees - headingDegrees;
    while (delta > 180) {
      delta -= 360;
    }
    while (delta < -180) {
      delta += 360;
    }
    if (delta.abs() <= 45) return RouteRelativeDirection.ahead;
    if (delta.abs() >= 135) return RouteRelativeDirection.behind;
    return delta > 0
        ? RouteRelativeDirection.right
        : RouteRelativeDirection.left;
  }

  void _ensureManeuvers(List<LatLng> route, List<LatLng> junctions) {
    if (identical(route, _maneuverRoute) &&
        identical(junctions, _maneuverJunctions)) {
      return;
    }
    _maneuverRoute = route;
    _maneuverJunctions = junctions;
    _maneuvers = maneuverPlanner.plan(route, junctions: junctions);
    _maneuverIndex = _maneuvers.indexWhere(
      (maneuver) =>
          maneuver.alongRouteMeters >=
          _maxRouteProgressMeters - _maneuverOvershootToleranceMeters,
    );
    if (_maneuverIndex < 0) _maneuverIndex = _maneuvers.length;
    _advanceAnnounced = false;
    _apexAnnounced = false;
  }

  void _skipCompletedManeuvers(double userAlong) {
    while (_maneuverIndex < _maneuvers.length) {
      final ahead = _maneuvers[_maneuverIndex].alongRouteMeters - userAlong;
      final completedAfterApex =
          _apexAnnounced && ahead < -_maneuverApexToleranceMeters;
      final skippedBeyondTolerance = ahead < -_maneuverOvershootToleranceMeters;
      if (!completedAfterApex && !skippedBeyondTolerance) return;
      _maneuverIndex++;
      _advanceAnnounced = false;
      _apexAnnounced = false;
    }
  }

  TurnDirection _turnDirection(double degrees) {
    if (degrees.abs() <= 15) return TurnDirection.straight;
    return degrees < 0 ? TurnDirection.left : TurnDirection.right;
  }
}
