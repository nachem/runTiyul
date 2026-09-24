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
  const _Edge(this.to, this.weight, {this.direct = false});

  final int to;
  final double weight;
  final bool direct;
}

class TrailRoutePlan {
  const TrailRoutePlan({
    required this.points,
    required this.waypointIndices,
    required this.directSegments,
    required this.snappedWaypoints,
    this.unroutedLegs = 0,
  });

  final List<LatLng> points;
  final List<int> waypointIndices;
  final List<int> directSegments;
  final int snappedWaypoints;
  final int unroutedLegs;
}

class _WaypointState {
  const _WaypointState({
    required this.point,
    required this.anchor,
    required this.cost,
    this.directLegs = 0,
    this.previous,
    this.leg = const [],
    this.directSegments = const [],
    this.unmappedMeters = 0,
    this.missedExactSnaps = 0,
  });

  final LatLng point;
  final TrailAnchor? anchor;
  final double cost;
  final int directLegs;
  final _WaypointState? previous;
  final List<LatLng> leg;
  final List<int> directSegments;
  final double unmappedMeters;
  final int missedExactSnaps;

  bool betterThan(_WaypointState other) {
    if (directLegs != other.directLegs) return directLegs < other.directLegs;
    if ((unmappedMeters == 0) != (other.unmappedMeters == 0)) {
      return unmappedMeters == 0;
    }
    if (missedExactSnaps != other.missedExactSnaps) {
      return missedExactSnaps < other.missedExactSnaps;
    }
    return cost < other.cost;
  }
}

typedef _GraphLeg = ({List<LatLng> points, List<int> directSegments});

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
  final Map<int, List<_Edge>> _planningAdjacency = {};
  final Map<(int, int), List<int>> _planningSegmentNodes = {};
  bool _planningConnectionsBuilt = false;
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

  List<int> _nodesAroundAnchor(TrailAnchor anchor, {bool planning = false}) {
    final nodes =
        (planning
            ? _planningSegmentNodes[(anchor.trailIndex, anchor.segmentIndex)]
            : null) ??
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

  void _ensurePlanningConnections() {
    _ensureGraphBuilt();
    if (_planningConnectionsBuilt) return;
    _planningConnectionsBuilt = true;
    final buckets = <(int, int, String), Set<(int, int)>>{};
    final cellLatitude = _dLat * 50 / nodeGridMeters;
    final cellLongitude = _dLon * 50 / nodeGridMeters;
    for (
      var trailIndex = 0;
      trailIndex < _network.trails.length;
      trailIndex++
    ) {
      final trail = _network.trails[trailIndex];
      if (!trail.routable) continue;
      for (var segment = 0; segment + 1 < trail.points.length; segment++) {
        final from = trail.points[segment];
        final to = trail.points[segment + 1];
        final steps = math.max(
          1,
          (2 *
                  math.max(
                    (to.latitude - from.latitude).abs() / cellLatitude,
                    (to.longitude - from.longitude).abs() / cellLongitude,
                  ))
              .ceil(),
        );
        for (var step = 0; step <= steps; step++) {
          final fraction = step / steps;
          final latitude =
              from.latitude + (to.latitude - from.latitude) * fraction;
          final longitude =
              from.longitude + (to.longitude - from.longitude) * fraction;
          buckets
              .putIfAbsent((
                (latitude / cellLatitude).floor(),
                (longitude / cellLongitude).floor(),
                trail.routingLevel,
              ), () => {})
              .add((trailIndex, segment));
        }
      }
    }
    List<TrailAnchor> nearbySegments(LatLng point, String level) {
      final latitude = (point.latitude / cellLatitude).floor();
      final longitude = (point.longitude / cellLongitude).floor();
      final segments = <(int, int)>{};
      for (var latitudeOffset = -1; latitudeOffset <= 1; latitudeOffset++) {
        for (
          var longitudeOffset = -1;
          longitudeOffset <= 1;
          longitudeOffset++
        ) {
          segments.addAll(
            buckets[(
                  latitude + latitudeOffset,
                  longitude + longitudeOffset,
                  level,
                )] ??
                const {},
          );
        }
      }
      final candidates = <TrailAnchor>[];
      for (final segment in segments) {
        final trail = _network.trails[segment.$1];
        final projection = nearestOnPolyline(point, [
          trail.points[segment.$2],
          trail.points[segment.$2 + 1],
        ])!;
        if (projection.distanceMeters > 12) continue;
        candidates.add(
          TrailAnchor(
            trailIndex: segment.$1,
            segmentIndex: segment.$2,
            point: projection.point,
            distanceMeters: projection.distanceMeters,
            category: TrailExtractor.categoryOf(trail.kind),
          ),
        );
      }
      candidates.sort(
        (left, right) => left.distanceMeters.compareTo(right.distanceMeters),
      );
      return candidates.take(16).toList(growable: false);
    }

    final components = List<int>.filled(_nodePoints.length, -1);
    for (var node = 0; node < components.length; node++) {
      if (components[node] >= 0) continue;
      final pending = <int>[node];
      components[node] = node;
      while (pending.isNotEmpty) {
        final current = pending.removeLast();
        for (final edge in _adjacency[current]) {
          if (components[edge.to] >= 0) continue;
          components[edge.to] = node;
          pending.add(edge.to);
        }
      }
    }
    final connectedPairs = <(int, int)>{};
    for (
      var trailIndex = 0;
      trailIndex < _network.trails.length;
      trailIndex++
    ) {
      final trail = _network.trails[trailIndex];
      if (!trail.routable || trail.points.length < 2) continue;
      for (final endpoint in [trail.points.first, trail.points.last]) {
        final node = _nodeFor(endpoint, trail.routingLevel);
        final neighbors = _adjacency[node].map((edge) => edge.to).toSet();
        if (neighbors.length != 1) continue;
        final incoming = distance.bearingDegrees(
          _nodePoints[neighbors.single],
          endpoint,
        );
        for (final candidate in nearbySegments(endpoint, trail.routingLevel)) {
          final target = _network.trails[candidate.trailIndex];
          if (candidate.trailIndex == trailIndex ||
              target.routingLevel != trail.routingLevel ||
              candidate.distanceMeters <= nodeGridMeters) {
            continue;
          }
          final originalNodes = _nodesAroundAnchor(candidate);
          if (originalNodes.isEmpty ||
              components[originalNodes.first] == components[node]) {
            continue;
          }
          final outgoing = distance.bearingDegrees(endpoint, candidate.point);
          if (((outgoing - incoming + 540) % 360 - 180).abs() > 60) continue;
          final targetNode = _nodeFor(candidate.point, target.routingLevel);
          final targetNeighbors = _adjacency[targetNode]
              .map((edge) => edge.to)
              .toSet();
          if (targetNeighbors.length == 1) {
            final targetIncoming = distance.bearingDegrees(
              _nodePoints[targetNeighbors.single],
              candidate.point,
            );
            final targetOutgoing = distance.bearingDegrees(
              candidate.point,
              endpoint,
            );
            if (((targetOutgoing - targetIncoming + 540) % 360 - 180).abs() >
                60) {
              continue;
            }
          }
          final pair = (math.min(node, targetNode), math.max(node, targetNode));
          if (!connectedPairs.add(pair)) continue;
          final segment = (candidate.trailIndex, candidate.segmentIndex);
          final nodes = _planningSegmentNodes.putIfAbsent(
            segment,
            () => [..._segmentNodes[segment]!],
          );
          if (!nodes.contains(targetNode)) {
            nodes.add(targetNode);
            final origin = target.points[candidate.segmentIndex];
            nodes.sort(
              (left, right) => distance
                  .metersBetween(origin, _nodePoints[left])
                  .compareTo(
                    distance.metersBetween(origin, _nodePoints[right]),
                  ),
            );
          }
          _planningAdjacency
              .putIfAbsent(node, () => [])
              .add(_Edge(targetNode, candidate.distanceMeters, direct: true));
          _planningAdjacency
              .putIfAbsent(targetNode, () => [])
              .add(_Edge(node, candidate.distanceMeters, direct: true));
        }
      }
    }
    for (final nodes in _planningSegmentNodes.values) {
      for (var index = 1; index < nodes.length; index++) {
        final from = nodes[index - 1];
        final to = nodes[index];
        final length = distance.metersBetween(
          _nodePoints[from],
          _nodePoints[to],
        );
        _planningAdjacency.putIfAbsent(from, () => []).add(_Edge(to, length));
        _planningAdjacency.putIfAbsent(to, () => []).add(_Edge(from, length));
      }
    }
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
      final projections = [
        for (var segment = 0; segment + 1 < trail.points.length; segment++)
          nearestOnPolyline(query, [
            trail.points[segment],
            trail.points[segment + 1],
          ], distance: distance)!,
      ];
      TrailAnchor? previous;
      for (var segment = 0; segment < projections.length; segment++) {
        final projection = projections[segment];
        if (projection.distanceMeters > maxMeters ||
            (segment > 0 &&
                projections[segment - 1].distanceMeters <
                    projection.distanceMeters) ||
            (segment + 1 < projections.length &&
                projections[segment + 1].distanceMeters <
                    projection.distanceMeters)) {
          continue;
        }
        if (previous != null &&
            previous.segmentIndex + 1 == segment &&
            distance.metersBetween(previous.point, projection.point) <=
                nodeGridMeters) {
          continue;
        }
        final anchor = TrailAnchor(
          trailIndex: i,
          segmentIndex: segment,
          point: projection.point,
          category: TrailExtractor.categoryOf(trail.kind),
          distanceMeters: projection.distanceMeters,
        );
        candidates.add(anchor);
        previous = anchor;
      }
    }
    candidates.sort(
      (left, right) => left.distanceMeters.compareTo(right.distanceMeters),
    );
    return candidates.take(limit).toList(growable: false);
  }

  TrailRoutePlan? planWaypoints(
    List<LatLng> waypoints, {
    bool allowDirectConnections = false,
    bool checkpointRouting = false,
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
        maxMeters: snapLimits?[index] ?? (checkpointRouting ? 150 : 40),
        limit: checkpointRouting ? 16 : 6,
      );
      return [
        ...nearby,
        if (allowDirectConnections && (nearby.isEmpty || checkpointRouting))
          null,
      ];
    }

    int missedExactSnap(TrailAnchor? anchor, List<TrailAnchor?> nearby) {
      if (nearby.isEmpty ||
          (nearby.first?.distanceMeters ?? double.infinity) > 2) {
        return 0;
      }
      return (anchor?.distanceMeters ?? double.infinity) > 2 ? 1 : 0;
    }

    final firstCandidates = candidates(0);
    var states = [
      for (final anchor in firstCandidates)
        _WaypointState(
          point: checkpointRouting && (anchor?.distanceMeters ?? 0) > 40
              ? waypoints.first
              : anchor?.point ?? waypoints.first,
          anchor: anchor,
          cost: (anchor?.distanceMeters ?? 0) * 4,
          missedExactSnaps: missedExactSnap(anchor, firstCandidates),
        ),
    ];
    for (var index = 1; index < waypoints.length; index++) {
      final next = <_WaypointState>[];
      final original =
          originalLegs?[index - 1] ?? [waypoints[index - 1], waypoints[index]];
      final originalLength = distance.pathLengthMeters(original);
      final nextCandidates = candidates(index);
      final targets = nextCandidates.whereType<TrailAnchor>().toList(
        growable: false,
      );
      final maximumDistance = math
          .max(10000, originalLength * 8)
          .clamp(10000, 100000)
          .toDouble();
      final checkpointPaths = <_WaypointState, Map<int, _GraphLeg>>{};
      if (checkpointRouting) {
        for (final previous in states) {
          if (previous.anchor == null) continue;
          final paths = _pathsToTargets(
            previous.anchor!,
            targets,
            maximumDistanceMeters: maximumDistance,
            firstOnly: false,
          );
          if (allowDirectConnections && paths.length < targets.length) {
            final gaps = _pathsToTargets(
              previous.anchor!,
              targets,
              maximumDistanceMeters: maximumDistance,
              firstOnly: false,
              planning: true,
            );
            for (final entry in gaps.entries) {
              paths.putIfAbsent(entry.key, () => entry.value);
            }
          }
          checkpointPaths[previous] = paths;
        }
      }
      for (
        var candidateIndex = 0;
        candidateIndex < nextCandidates.length;
        candidateIndex++
      ) {
        final anchor = nextCandidates[candidateIndex];
        final point = checkpointRouting && (anchor?.distanceMeters ?? 0) > 40
            ? waypoints[index]
            : anchor?.point ?? waypoints[index];
        _WaypointState? best;
        for (final previous in states) {
          if (checkpointRouting &&
              originalLength > 5 &&
              distance.metersBetween(previous.point, point) <
                  math.min(10, originalLength / 2)) {
            continue;
          }
          final checkpointLeg = checkpointPaths[previous]?[candidateIndex];
          var leg = previous.anchor == null || anchor == null
              ? null
              : checkpointRouting
              ? checkpointLeg?.points
              : buildConnectedLeg(previous.anchor!, anchor);
          if (leg != null && !(acceptMappedLeg?.call(leg, index - 1) ?? true)) {
            leg = null;
          }
          final direct = leg == null;
          if (direct && !allowDirectConnections) continue;
          var directSegments = checkpointLeg?.directSegments ?? const <int>[];
          leg ??= [
            previous.point,
            ...original.skip(1).take(original.length - 2),
            point,
          ];
          if (direct) {
            directSegments = List.generate(
              leg.length - 1,
              (segment) => segment,
            );
          } else if (checkpointRouting) {
            final approach =
                distance.metersBetween(previous.point, leg.first) > 0.01;
            final departure = distance.metersBetween(leg.last, point) > 0.01;
            if ((approach || departure) && !allowDirectConnections) continue;
            directSegments = [
              if (approach) 0,
              for (final segment in directSegments)
                segment + (approach ? 1 : 0),
              if (departure) leg.length - 1 + (approach ? 1 : 0),
            ];
            leg = [if (approach) previous.point, ...leg, if (departure) point];
          }
          final unmapped = directSegments.fold<double>(
            0,
            (sum, segment) =>
                sum + distance.metersBetween(leg![segment], leg[segment + 1]),
          );
          final state = _WaypointState(
            point: point,
            anchor: anchor,
            cost:
                previous.cost +
                (anchor?.distanceMeters ?? 0) * 4 +
                (checkpointRouting ? unmapped * 25 : 0) +
                (checkpointRouting
                    ? distance.pathLengthMeters(leg)
                    : (distance.pathLengthMeters(leg) - originalLength).abs()),
            directLegs: previous.directLegs + (direct ? 1 : 0),
            unmappedMeters:
                previous.unmappedMeters + (checkpointRouting ? unmapped : 0),
            missedExactSnaps:
                previous.missedExactSnaps +
                missedExactSnap(anchor, nextCandidates),
            previous: previous,
            leg: leg,
            directSegments: directSegments,
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
      for (var segment = 0; segment + 1 < state.leg.length; segment++) {
        final point = state.leg[segment + 1];
        if (distance.metersBetween(points.last, point) <= 0.01) continue;
        if (state.directSegments.contains(segment)) {
          directSegments.add(points.length - 1);
        }
        points.add(point);
      }
      handles.add(points.length - 1);
    }
    return TrailRoutePlan(
      points: List.unmodifiable(points),
      waypointIndices: List.unmodifiable(handles),
      directSegments: List.unmodifiable(directSegments),
      snappedWaypoints: ordered.where((state) => state.anchor != null).length,
      unroutedLegs: best.directLegs,
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
    final paths = _pathsToTargets(
      from,
      targets,
      headingDegrees: headingDegrees,
      maximumInitialTurnDegrees: maximumInitialTurnDegrees,
      maximumDistanceMeters: maximumDistanceMeters,
    );
    if (paths.isEmpty) return null;
    final first = paths.entries.first;
    return (path: first.value.points, targetIndex: first.key);
  }

  Map<int, _GraphLeg> _pathsToTargets(
    TrailAnchor from,
    List<TrailAnchor> targets, {
    double? headingDegrees,
    double maximumInitialTurnDegrees = 75,
    double maximumDistanceMeters = double.infinity,
    bool firstOnly = true,
    bool planning = false,
  }) {
    _ensureGraphBuilt();
    if (planning) _ensurePlanningConnections();
    final nodeCount = _nodePoints.length;
    if (nodeCount == 0 || targets.isEmpty) return {};
    final startId = nodeCount;
    final total = nodeCount + 1 + targets.length;
    final startNodes = _nodesAroundAnchor(from, planning: planning);
    if (startNodes.isEmpty) return {};
    final targetEdges = <int, List<_Edge>>{};
    final directTargets = <_Edge>[];
    for (var index = 0; index < targets.length; index++) {
      final target = targets[index];
      final goalId = startId + 1 + index;
      for (final node in _nodesAroundAnchor(target, planning: planning)) {
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
        if (planning) ...?_planningAdjacency[node],
        ...?targetEdges[node],
      ];
    }

    final distances = List<double>.filled(total, double.infinity);
    final pathLengths = List<double>.filled(total, double.infinity);
    final previous = List<int>.filled(total, -1);
    final previousDirect = List<bool>.filled(total, false);
    distances[startId] = 0;
    pathLengths[startId] = 0;
    final paths = <int, _GraphLeg>{};
    final queue = _MinQueue()..add(_QueueEntry(startId, 0));
    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      final node = current.node;
      if (current.distance != distances[node]) continue;
      if (node > startId) {
        final ids = <int>[];
        for (var step = node; step != -1; step = previous[step]) {
          ids.add(step);
        }
        final ordered = ids.reversed.toList(growable: false);
        paths[node - startId - 1] = (
          points: [for (final id in ordered) pointOf(id)],
          directSegments: [
            for (var index = 1; index < ordered.length; index++)
              if (previousDirect[ordered[index]]) index - 1,
          ],
        );
        if (firstOnly || paths.length == targets.length) break;
        continue;
      }
      for (final edge in edgesOf(node)) {
        if (headingDegrees != null &&
            current.distance < 3 &&
            distance.metersBetween(from.point, pointOf(edge.to)) >= 3) {
          final bearing = distance.bearingDegrees(from.point, pointOf(edge.to));
          final turn = ((bearing - headingDegrees + 540) % 360 - 180).abs();
          if (turn > maximumInitialTurnDegrees) continue;
        }
        final length = pathLengths[node] + edge.weight;
        final candidate =
            current.distance + edge.weight * (edge.direct ? 25 : 1);
        if (length <= maximumDistanceMeters && candidate < distances[edge.to]) {
          distances[edge.to] = candidate;
          pathLengths[edge.to] = length;
          previous[edge.to] = node;
          previousDirect[edge.to] = edge.direct;
          queue.add(_QueueEntry(edge.to, candidate));
        }
      }
    }
    return paths;
  }
}
