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
/// Vertices are merged onto a small grid so trails that meet at a junction
/// share a node, which lets a shortest-path search walk from one trail onto a
/// connected one through the junction. This is what powers "tap a trail and the
/// route follows it to the next junction (and beyond)".
class TrailRouter {
  TrailRouter(
    this._network, {
    this.nodeGridMeters = 6,
    this.distance = const GeoDistance(),
  });

  final TrailNetwork _network;

  /// Vertices closer than this are treated as the same graph node, merging the
  /// shared endpoints of trails that meet at a junction.
  final double nodeGridMeters;

  final GeoDistance distance;

  final List<LatLng> _nodePoints = [];
  final Map<(int, int), int> _cellToNode = {};
  final List<List<_Edge>> _adjacency = [];
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

    for (final trail in _network.trails) {
      final points = trail.points;
      for (var i = 0; i + 1 < points.length; i++) {
        final a = _nodeFor(points[i]);
        final b = _nodeFor(points[i + 1]);
        if (a == b) continue;
        final weight = distance.metersBetween(points[i], points[i + 1]);
        _adjacency[a].add(_Edge(b, weight));
        _adjacency[b].add(_Edge(a, weight));
      }
    }
  }

  (int, int) _cell(LatLng point) =>
      ((point.latitude / _dLat).round(), (point.longitude / _dLon).round());

  int _nodeFor(LatLng point) {
    final cell = _cell(point);
    final existing = _cellToNode[cell];
    if (existing != null) return existing;
    final id = _nodePoints.length;
    _cellToNode[cell] = id;
    _nodePoints.add(point);
    _adjacency.add(<_Edge>[]);
    return id;
  }

  int? _nodeIndexOf(LatLng vertex) => _cellToNode[_cell(vertex)];

  /// The nearest point on any trail *line* within [maxMeters], or null. Uses
  /// segment projection so a query on a trail between vertices still snaps.
  ///
  /// When [preferCategory] is set and the query is within [maxMeters] of a way
  /// in that category, that way wins even if a way of another category is
  /// closer. This keeps a built route on the same kind of way (a trail versus a
  /// road) as its previous waypoint when a tap sits near both.
  TrailAnchor? snap(
    LatLng query, {
    double maxMeters = 40,
    WayCategory? preferCategory,
  }) {
    TrailAnchor? best;
    TrailAnchor? preferred;
    for (var i = 0; i < _network.trails.length; i++) {
      final trail = _network.trails[i];
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
      if (best == null || anchor.distanceMeters < best.distanceMeters) {
        best = anchor;
      }
      if (preferCategory != null &&
          anchor.category == preferCategory &&
          (preferred == null ||
              anchor.distanceMeters < preferred.distanceMeters)) {
        preferred = anchor;
      }
    }
    return preferred ?? best;
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
    if (a.trailIndex == b.trailIndex) {
      return _alongTrail(a.trailIndex, a, b);
    }
    final path = _graphPath(a, b);
    if (path == null) return null;
    final direct = distance.metersBetween(a.point, b.point);
    if (_pathLength(path) >
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

  /// The portion of a single trail between two anchors, following the trail's
  /// own vertices so the whole leg stays exactly on the trail.
  List<LatLng> _alongTrail(int trailIndex, TrailAnchor a, TrailAnchor b) {
    final points = _network.trails[trailIndex].points;
    if (a.segmentIndex == b.segmentIndex) return [a.point, b.point];
    final leg = <LatLng>[a.point];
    if (a.segmentIndex < b.segmentIndex) {
      for (var k = a.segmentIndex + 1; k <= b.segmentIndex; k++) {
        leg.add(points[k]);
      }
    } else {
      for (var k = a.segmentIndex; k >= b.segmentIndex + 1; k--) {
        leg.add(points[k]);
      }
    }
    leg.add(b.point);
    return leg;
  }

  /// Shortest path across the trail graph between anchors on different trails,
  /// entering/leaving via the endpoints of each anchor's segment.
  List<LatLng>? _graphPath(TrailAnchor a, TrailAnchor b) {
    _ensureGraphBuilt();
    final n = _nodePoints.length;
    if (n == 0) return null;
    final startId = n;
    final goalId = n + 1;
    final total = n + 2;

    final aPoints = _network.trails[a.trailIndex].points;
    final bPoints = _network.trails[b.trailIndex].points;
    final a0 = _nodeIndexOf(aPoints[a.segmentIndex]);
    final a1 = _nodeIndexOf(aPoints[a.segmentIndex + 1]);
    final b0 = _nodeIndexOf(bPoints[b.segmentIndex]);
    final b1 = _nodeIndexOf(bPoints[b.segmentIndex + 1]);
    if (a0 == null || a1 == null || b0 == null || b1 == null) return null;

    LatLng pointOf(int id) => id == startId
        ? a.point
        : id == goalId
        ? b.point
        : _nodePoints[id];

    List<_Edge> edgesOf(int u) {
      if (u == startId) {
        return [
          _Edge(a0, distance.metersBetween(a.point, _nodePoints[a0])),
          _Edge(a1, distance.metersBetween(a.point, _nodePoints[a1])),
        ];
      }
      final base = u < n ? _adjacency[u] : const <_Edge>[];
      if (u == b0 || u == b1) {
        return [
          ...base,
          _Edge(goalId, distance.metersBetween(_nodePoints[u], b.point)),
        ];
      }
      return base;
    }

    final dist = List<double>.filled(total, double.infinity);
    final prev = List<int>.filled(total, -1);
    dist[startId] = 0;

    final queue = _MinQueue()..add(_QueueEntry(startId, 0));
    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      final u = current.node;
      if (current.distance != dist[u]) continue;
      if (u == goalId) break;
      for (final edge in edgesOf(u)) {
        final candidate = current.distance + edge.weight;
        if (candidate < dist[edge.to]) {
          dist[edge.to] = candidate;
          prev[edge.to] = u;
          queue.add(_QueueEntry(edge.to, candidate));
        }
      }
    }

    if (dist[goalId].isInfinite) return null;
    final ids = <int>[];
    var current = goalId;
    while (current != -1) {
      ids.add(current);
      if (current == startId) break;
      current = prev[current];
    }
    if (ids.isEmpty || ids.last != startId) return null;
    return [for (final id in ids.reversed) pointOf(id)];
  }
}
