import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../core/geo/distance.dart';
import '../core/geo/polyline_snap.dart';
import 'trail_extractor.dart';
import 'trail_network.dart';

/// A point snapped onto a trail's *line* (not just its vertices): it lies on the
/// segment `[segmentIndex, segmentIndex + 1]` of trail [trailIndex].
class TrailAnchor {
  const TrailAnchor({
    required this.trailIndex,
    required this.segmentIndex,
    required this.point,
    required this.category,
    this.distanceMeters = 0,
  });

  final int trailIndex;
  final int segmentIndex;
  final LatLng point;

  /// Whether the snapped way is a trail or a road.
  final WayCategory category;

  /// How far the original query was from the trail line.
  final double distanceMeters;
}

class _Edge {
  const _Edge(this.to, this.weight);

  final int to;
  final double weight;
}

class TrailRoutePlan {
  const TrailRoutePlan({
    required this.points,
    required this.waypointIndices,
    required this.directSegments,
    required this.snappedWaypoints,
  });

  final List<LatLng> points;
  final List<int> waypointIndices;
  final List<int> directSegments;
  final int snappedWaypoints;
}

class _WaypointState {
  const _WaypointState({
    required this.point,
    required this.anchor,
    required this.cost,
    this.directLegs = 0,
    this.previous,
    this.leg = const [],
    this.direct = false,
  });

  final LatLng point;
  final TrailAnchor? anchor;
  final double cost;
  final int directLegs;
  final _WaypointState? previous;
  final List<LatLng> leg;
  final bool direct;

  bool betterThan(_WaypointState other) =>
      directLegs < other.directLegs ||
      (directLegs == other.directLegs && cost < other.cost);
}

class _QueueEntry {
  const _QueueEntry(this.node, this.distance);

  final int node;
  final double distance;
}

class _MinQueue {
  final List<_QueueEntry> _entries = [];

  bool get isNotEmpty => _entries.isNotEmpty;

  void add(_QueueEntry entry) {
    _entries.add(entry);
    var index = _entries.length - 1;
    while (index > 0) {
      final parent = (index - 1) ~/ 2;
      if (_entries[parent].distance <= entry.distance) break;
      _entries[index] = _entries[parent];
      index = parent;
    }
    _entries[index] = entry;
  }

  _QueueEntry removeFirst() {
    final first = _entries.first;
    final last = _entries.removeLast();
    if (_entries.isEmpty) return first;
    var index = 0;
    while (true) {
      final left = index * 2 + 1;
      if (left >= _entries.length) break;
      final right = left + 1;
      final child =
          right < _entries.length &&
              _entries[right].distance < _entries[left].distance
          ? right
          : left;
      if (_entries[child].distance >= last.distance) break;
      _entries[index] = _entries[child];
      index = child;
    }
    _entries[index] = last;
    return first;
  }
}

/// Builds a routable graph from a [TrailNetwork] so a route can *follow* real
/// trails between tapped anchor points instead of cutting straight lines.
///
/// Only coincident vertices (within coordinate-rounding precision) share a
/// node. Nearby ways must not become connected merely because they occupy the
/// same few metres on the map.
class TrailRouter {
  TrailRouter(
    this._network, {
    this.nodeGridMeters = 0.01,
    this.distance = const GeoDistance(),
  });

  final TrailNetwork _network;

  /// Coordinate-rounding grid for shared vertices, not a proximity-based
  /// junction radius. RTE-011 requires separate mapped ways to stay separate.
  final double nodeGridMeters;

  final GeoDistance distance;

  final List<LatLng> _nodePoints = [];
  final Map<(int, int, String), int> _cellToNode = {};
  final List<List<_Edge>> _adjacency = [];
  final Map<(int, int), List<int>> _segmentNodes = {};
  var _graphBuilt = false;

  double _dLat = 1;
  double _dLon = 1;

  bool get isEmpty => _network.isEmpty;

  /// The number of graph nodes (exposed for diagnostics/tests).
  int get nodeCount {
    _ensureGraphBuilt();
    return _nodePoints.length;
  }

  void _ensureGraphBuilt() {
    if (_graphBuilt) return;
    _graphBuilt = true;
    _build();
  }

  void _build() {
    if (_network.isEmpty) return;
    final referenceLat = _network.trails.first.points.first.latitude;
    _dLat = nodeGridMeters / 111320.0;
    _dLon =
        nodeGridMeters /
        (111320.0 * math.max(0.01, math.cos(referenceLat * math.pi / 180.0)));

    final endpoints = <(int, int), Set<int>>{};
    final endpointsByLevel = <String, Set<int>>{};
    for (final trail in _network.trails) {
      if (!trail.routable || trail.points.length < 2) continue;
      for (final point in [trail.points.first, trail.points.last]) {
        final node = _nodeFor(point, trail.routingLevel);
        endpoints.putIfAbsent(_cell(point), () => {}).add(node);
        endpointsByLevel.putIfAbsent(trail.routingLevel, () => {}).add(node);
      }
    }
    final sortedEndpoints = endpointsByLevel.map(
      (level, nodes) => MapEntry(
        level,
        nodes.toList()..sort(
          (left, right) =>
              _nodePoints[left].latitude.compareTo(_nodePoints[right].latitude),
        ),
      ),
    );
    for (
      var trailIndex = 0;
      trailIndex < _network.trails.length;
      trailIndex++
    ) {
      final trail = _network.trails[trailIndex];
      if (!trail.routable || trail.points.length < 2) continue;
      for (var segment = 0; segment + 1 < trail.points.length; segment++) {
        final nodes = _splitSegment(
          trail.points[segment],
          trail.points[segment + 1],
          trail.routingLevel,
          sortedEndpoints[trail.routingLevel]!,
        );
        _segmentNodes[(trailIndex, segment)] = nodes;
        for (var index = 1; index < nodes.length; index++) {
          final from = nodes[index - 1];
          final to = nodes[index];
          final weight = distance.metersBetween(
            _nodePoints[from],
            _nodePoints[to],
          );
          _adjacency[from].add(_Edge(to, weight));
          _adjacency[to].add(_Edge(from, weight));
        }
      }
    }
    for (final nodes in endpoints.values) {
      for (final from in nodes) {
        for (final to in nodes) {
          if (from != to) _adjacency[from].add(_Edge(to, 0));
        }
      }
    }
  }

  List<int> _splitSegment(
    LatLng from,
    LatLng to,
    String level,
    List<int> endpoints,
  ) {
    final positions = <int, double>{
      _nodeFor(from, level): 0,
      _nodeFor(to, level): 1,
    };
    final south = math.min(from.latitude, to.latitude) - _dLat;
    final north = math.max(from.latitude, to.latitude) + _dLat;
    final west = math.min(from.longitude, to.longitude) - _dLon;
    final east = math.max(from.longitude, to.longitude) + _dLon;
    var lower = 0;
    var upper = endpoints.length;
    while (lower < upper) {
      final middle = (lower + upper) ~/ 2;
      if (_nodePoints[endpoints[middle]].latitude < south) {
        lower = middle + 1;
      } else {
        upper = middle;
      }
    }
    for (var index = lower; index < endpoints.length; index++) {
      final node = endpoints[index];
      final point = _nodePoints[node];
      if (point.latitude > north) break;
      if (point.longitude < west ||
          point.longitude > east ||
          positions.containsKey(node)) {
        continue;
      }
      final projection = nearestOnPolyline(point, [
        from,
        to,
      ], distance: distance)!;
      if (projection.distanceMeters <= nodeGridMeters &&
          projection.t > 0 &&
          projection.t < 1) {
        positions[node] = projection.t;
      }
    }
    return positions.keys.toList()
      ..sort((left, right) => positions[left]!.compareTo(positions[right]!));
  }

  (int, int) _cell(LatLng point) =>
      ((point.latitude / _dLat).round(), (point.longitude / _dLon).round());

  int _nodeFor(LatLng point, String level) {
    final position = _cell(point);
    final cell = (position.$1, position.$2, level);
    final existing = _cellToNode[cell];
    if (existing != null) return existing;
    final id = _nodePoints.length;
    _cellToNode[cell] = id;
    _nodePoints.add(point);
    _adjacency.add(<_Edge>[]);
    return id;
  }

  List<int> _nodesAroundAnchor(TrailAnchor anchor) {
    final nodes =
        _segmentNodes[(anchor.trailIndex, anchor.segmentIndex)] ??
        const <int>[];
    if (nodes.length <= 2) return nodes;
    final origin =
        _network.trails[anchor.trailIndex].points[anchor.segmentIndex];
    final along = distance.metersBetween(origin, anchor.point);
    for (var index = 1; index < nodes.length; index++) {
      if (distance.metersBetween(origin, _nodePoints[nodes[index]]) >= along) {
        return [nodes[index - 1], nodes[index]];
      }
    }
    return nodes.sublist(nodes.length - 2);
  }

  /// The nearest point on any trail *line* within [maxMeters], or null. Uses
  /// segment projection so a query on a trail between vertices still snaps.
  ///
  /// Category is only a near-tie breaker; an exact road tap must not jump to a
  /// distant parallel path just because the preceding point was on a path.
  TrailAnchor? snap(
    LatLng query, {
    double maxMeters = 40,
    WayCategory? preferCategory,
  }) {
    final candidates = snapCandidates(query, maxMeters: maxMeters);
    if (candidates.isEmpty) return null;
    final best = candidates.first;
    final preferred = candidates
        .where((anchor) => anchor.category == preferCategory)
        .firstOrNull;
    return preferred != null &&
            preferred.distanceMeters <= best.distanceMeters + 6
        ? preferred
        : best;
  }

  List<TrailAnchor> snapCandidates(
    LatLng query, {
    double maxMeters = 40,
    int limit = 6,
  }) {
    final candidates = <TrailAnchor>[];
    for (var i = 0; i < _network.trails.length; i++) {
      final trail = _network.trails[i];
      if (!trail.routable) continue;
      final projection = nearestOnPolyline(
        query,
        trail.points,
        distance: distance,
      );
      if (projection == null || projection.distanceMeters > maxMeters) continue;
      final anchor = TrailAnchor(
        trailIndex: i,
        segmentIndex: projection.segmentIndex,
        point: projection.point,
        category: TrailExtractor.categoryOf(trail.kind),
        distanceMeters: projection.distanceMeters,
      );
      candidates.add(anchor);
    }
    candidates.sort(
      (left, right) => left.distanceMeters.compareTo(right.distanceMeters),
    );
    return candidates.take(limit).toList(growable: false);
  }

  TrailRoutePlan? planWaypoints(
    List<LatLng> waypoints, {
    bool allowDirectConnections = false,
    List<double>? snapLimits,
    List<List<LatLng>>? originalLegs,
    bool Function(List<LatLng> leg, int legIndex)? acceptMappedLeg,
  }) {
    if (waypoints.isEmpty) {
      return const TrailRoutePlan(
        points: [],
        waypointIndices: [],
        directSegments: [],
        snappedWaypoints: 0,
      );
    }
    List<TrailAnchor?> candidates(int index) {
      final nearby = snapCandidates(
        waypoints[index],
        maxMeters: snapLimits?[index] ?? 40,
      );
      return nearby.isEmpty && allowDirectConnections ? [null] : nearby;
    }

    var states = [
      for (final anchor in candidates(0))
        _WaypointState(
          point: anchor?.point ?? waypoints.first,
          anchor: anchor,
          cost: (anchor?.distanceMeters ?? 0) * 4,
        ),
    ];
    for (var index = 1; index < waypoints.length; index++) {
      final next = <_WaypointState>[];
      final original =
          originalLegs?[index - 1] ?? [waypoints[index - 1], waypoints[index]];
      final originalLength = distance.pathLengthMeters(original);
      for (final anchor in candidates(index)) {
        final point = anchor?.point ?? waypoints[index];
        _WaypointState? best;
        for (final previous in states) {
          var leg = previous.anchor == null || anchor == null
              ? null
              : buildConnectedLeg(previous.anchor!, anchor);
          if (leg != null && !(acceptMappedLeg?.call(leg, index - 1) ?? true)) {
            leg = null;
          }
          final direct = leg == null;
          if (direct && !allowDirectConnections) continue;
          leg ??= [
            previous.point,
            ...original.skip(1).take(original.length - 2),
            point,
          ];
          final state = _WaypointState(
            point: point,
            anchor: anchor,
            cost:
                previous.cost +
                (anchor?.distanceMeters ?? 0) * 4 +
                (distance.pathLengthMeters(leg) - originalLength).abs(),
            directLegs: previous.directLegs + (direct ? 1 : 0),
            previous: previous,
            leg: leg,
            direct: direct,
          );
          if (best == null || state.betterThan(best)) best = state;
        }
        if (best != null) next.add(best);
      }
      states = next;
      if (states.isEmpty) return null;
    }
    if (states.isEmpty) return null;
    var best = states.first;
    for (final state in states.skip(1)) {
      if (state.betterThan(best)) best = state;
    }
    final chain = <_WaypointState>[];
    for (_WaypointState? state = best; state != null; state = state.previous) {
      chain.add(state);
    }
    final ordered = chain.reversed.toList(growable: false);
    final points = <LatLng>[ordered.first.point];
    final handles = <int>[0];
    final directSegments = <int>[];
    for (final state in ordered.skip(1)) {
      for (final point in state.leg.skip(1)) {
        if (distance.metersBetween(points.last, point) <= 0.01) continue;
        if (state.direct) directSegments.add(points.length - 1);
        points.add(point);
      }
      handles.add(points.length - 1);
    }
    return TrailRoutePlan(
      points: List.unmodifiable(points),
      waypointIndices: List.unmodifiable(handles),
      directSegments: List.unmodifiable(directSegments),
      snappedWaypoints: ordered.where((state) => state.anchor != null).length,
    );
  }

  /// Stitches [anchors] into a route that follows the trail network between
  /// consecutive anchors. A leg that cannot be connected falls back to a
  /// straight segment so the route stays continuous.
  List<LatLng> buildRoute(List<TrailAnchor> anchors) {
    if (anchors.length < 2) return [for (final a in anchors) a.point];
    final route = <LatLng>[];
    for (var i = 0; i + 1 < anchors.length; i++) {
      final leg =
          _connectedLeg(anchors[i], anchors[i + 1]) ??
          [anchors[i].point, anchors[i + 1].point];
      if (route.isEmpty) {
        route.addAll(leg);
      } else {
        route.addAll(leg.skip(1));
      }
    }
    return route;
  }

  /// Builds a route only when every anchor pair is connected through a
  /// reasonable trail-network path. Follow-trails editing uses this strict
  /// variant so the mode never silently inserts a straight waypoint leg.
  List<LatLng>? buildConnectedRoute(List<TrailAnchor> anchors) {
    if (anchors.length < 2) return [for (final anchor in anchors) anchor.point];
    final route = <LatLng>[];
    for (var index = 0; index + 1 < anchors.length; index++) {
      final leg = _connectedLeg(anchors[index], anchors[index + 1]);
      if (leg == null) return null;
      if (route.isEmpty) {
        route.addAll(leg);
      } else {
        route.addAll(leg.skip(1));
      }
    }
    return route;
  }

  /// Returns the trail-network path for one anchor pair, or null when the pair
  /// is disconnected or would require an unreasonable detour.
  List<LatLng>? buildConnectedLeg(TrailAnchor from, TrailAnchor to) =>
      _connectedLeg(from, to);

  /// A cross-trail bridge longer than this multiple of the direct hop (plus a
  /// small slack) is treated as an unreasonable detour and replaced by a
  /// straight segment, so a short real-world crossing is never swapped for a
  /// long loop through the network. Same-trail legs are never capped, so real
  /// switchbacks along one trail are preserved.
  static const double _maxBridgeDetourFactor = 6;
  static const double _maxBridgeDetourSlackMeters = 40;

  List<LatLng>? _connectedLeg(TrailAnchor a, TrailAnchor b) {
    if (a.trailIndex == b.trailIndex && a.segmentIndex == b.segmentIndex) {
      return [a.point, b.point];
    }
    final path = _graphPath(a, b);
    if (path == null) return null;
    final direct = distance.metersBetween(a.point, b.point);
    if (a.trailIndex != b.trailIndex &&
        _pathLength(path) >
            direct * _maxBridgeDetourFactor + _maxBridgeDetourSlackMeters) {
      return null;
    }
    return path;
  }

  double _pathLength(List<LatLng> points) {
    var total = 0.0;
    for (var i = 1; i < points.length; i++) {
      total += distance.metersBetween(points[i - 1], points[i]);
    }
    return total;
  }

  List<LatLng>? _graphPath(TrailAnchor from, TrailAnchor to) =>
      buildConnectedLegToAny(from, [to])?.path;

  /// NAV-007: a single Dijkstra search chooses the shortest mapped connection.
  /// The initial heading constraint is part of search, not a post-hoc rejection
  /// that could miss a longer but valid forward alternative.
  ({List<LatLng> path, int targetIndex})? buildConnectedLegToAny(
    TrailAnchor from,
    List<TrailAnchor> targets, {
    double? headingDegrees,
    double maximumInitialTurnDegrees = 75,
    double maximumDistanceMeters = double.infinity,
  }) {
    _ensureGraphBuilt();
    final nodeCount = _nodePoints.length;
    if (nodeCount == 0 || targets.isEmpty) return null;
    final startId = nodeCount;
    final total = nodeCount + 1 + targets.length;
    final startNodes = _nodesAroundAnchor(from);
    if (startNodes.isEmpty) return null;
    final targetEdges = <int, List<_Edge>>{};
    final directTargets = <_Edge>[];
    for (var index = 0; index < targets.length; index++) {
      final target = targets[index];
      final goalId = startId + 1 + index;
      for (final node in _nodesAroundAnchor(target)) {
        targetEdges
            .putIfAbsent(node, () => [])
            .add(
              _Edge(
                goalId,
                distance.metersBetween(_nodePoints[node], target.point),
              ),
            );
      }
      if (target.trailIndex == from.trailIndex &&
          target.segmentIndex == from.segmentIndex) {
        directTargets.add(
          _Edge(goalId, distance.metersBetween(from.point, target.point)),
        );
      }
    }

    LatLng pointOf(int id) => id == startId
        ? from.point
        : id > startId
        ? targets[id - startId - 1].point
        : _nodePoints[id];

    List<_Edge> edgesOf(int node) {
      if (node == startId) {
        return [
          for (final start in startNodes)
            _Edge(
              start,
              distance.metersBetween(from.point, _nodePoints[start]),
            ),
          ...directTargets,
        ];
      }
      return [
        for (final edge in _adjacency[node])
          if (!(startNodes.contains(node) && startNodes.contains(edge.to)))
            edge,
        ...?targetEdges[node],
      ];
    }

    final distances = List<double>.filled(total, double.infinity);
    final previous = List<int>.filled(total, -1);
    distances[startId] = 0;
    int? reachedGoal;
    final queue = _MinQueue()..add(_QueueEntry(startId, 0));
    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      final node = current.node;
      if (current.distance != distances[node]) continue;
      if (node > startId) {
        reachedGoal = node;
        break;
      }
      for (final edge in edgesOf(node)) {
        if (headingDegrees != null &&
            current.distance < 3 &&
            distance.metersBetween(from.point, pointOf(edge.to)) >= 3) {
          final bearing = distance.bearingDegrees(from.point, pointOf(edge.to));
          final turn = ((bearing - headingDegrees + 540) % 360 - 180).abs();
          if (turn > maximumInitialTurnDegrees) continue;
        }
        final candidate = current.distance + edge.weight;
        if (candidate <= maximumDistanceMeters &&
            candidate < distances[edge.to]) {
          distances[edge.to] = candidate;
          previous[edge.to] = node;
          queue.add(_QueueEntry(edge.to, candidate));
        }
      }
    }
    if (reachedGoal == null) return null;
    final ids = <int>[];
    var current = reachedGoal;
    while (current != -1) {
      ids.add(current);
      if (current == startId) break;
      current = previous[current];
    }
    if (ids.isEmpty || ids.last != startId) return null;
    return (
      path: [for (final id in ids.reversed) pointOf(id)],
      targetIndex: reachedGoal - startId - 1,
    );
  }
}
