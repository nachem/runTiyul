import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../core/geo/distance.dart';
import '../core/geo/polyline_snap.dart';
import 'trail_network.dart';

/// A point snapped onto a trail's *line* (not just its vertices): it lies on the
/// segment `[segmentIndex, segmentIndex + 1]` of trail [trailIndex].
class TrailAnchor {
  const TrailAnchor({
    required this.trailIndex,
    required this.segmentIndex,
    required this.point,
    this.distanceMeters = 0,
  });

  final int trailIndex;
  final int segmentIndex;
  final LatLng point;

  /// How far the original query was from the trail line.
  final double distanceMeters;
}

class _Edge {
  const _Edge(this.to, this.weight);

  final int to;
  final double weight;
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
  }) {
    _build();
  }

  final TrailNetwork _network;

  /// Vertices closer than this are treated as the same graph node, merging the
  /// shared endpoints of trails that meet at a junction.
  final double nodeGridMeters;

  final GeoDistance distance;

  final List<LatLng> _nodePoints = [];
  final Map<(int, int), int> _cellToNode = {};
  final List<List<_Edge>> _adjacency = [];

  double _dLat = 1;
  double _dLon = 1;

  bool get isEmpty => _network.isEmpty;

  /// The number of graph nodes (exposed for diagnostics/tests).
  int get nodeCount => _nodePoints.length;

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
  TrailAnchor? snap(LatLng query, {double maxMeters = 40}) {
    TrailAnchor? best;
    var bestMeters = maxMeters;
    for (var i = 0; i < _network.trails.length; i++) {
      final projection = nearestOnPolyline(
        query,
        _network.trails[i].points,
        distance: distance,
      );
      if (projection == null) continue;
      if (projection.distanceMeters <= bestMeters) {
        bestMeters = projection.distanceMeters;
        best = TrailAnchor(
          trailIndex: i,
          segmentIndex: projection.segmentIndex,
          point: projection.point,
          distanceMeters: projection.distanceMeters,
        );
      }
    }
    return best;
  }

  /// Stitches [anchors] into a route that follows the trail network between
  /// consecutive anchors. A leg that cannot be connected falls back to a
  /// straight segment so the route stays continuous.
  List<LatLng> buildRoute(List<TrailAnchor> anchors) {
    if (anchors.length < 2) return [for (final a in anchors) a.point];
    final route = <LatLng>[];
    for (var i = 0; i + 1 < anchors.length; i++) {
      final leg = _leg(anchors[i], anchors[i + 1]);
      if (route.isEmpty) {
        route.addAll(leg);
      } else {
        route.addAll(leg.skip(1));
      }
    }
    return route;
  }

  List<LatLng> _leg(TrailAnchor a, TrailAnchor b) {
    if (a.trailIndex == b.trailIndex) {
      return _alongTrail(a.trailIndex, a, b);
    }
    return _graphPath(a, b) ?? [a.point, b.point];
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
    final visited = List<bool>.filled(total, false);
    dist[startId] = 0;

    for (var iteration = 0; iteration < total; iteration++) {
      var u = -1;
      var best = double.infinity;
      for (var i = 0; i < total; i++) {
        if (!visited[i] && dist[i] < best) {
          best = dist[i];
          u = i;
        }
      }
      if (u == -1) break;
      if (u == goalId) break;
      visited[u] = true;
      for (final edge in edgesOf(u)) {
        final candidate = dist[u] + edge.weight;
        if (candidate < dist[edge.to]) {
          dist[edge.to] = candidate;
          prev[edge.to] = u;
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
