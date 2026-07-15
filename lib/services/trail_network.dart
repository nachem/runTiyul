import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../core/geo/polyline_snap.dart';

/// A single trail line extracted from vector map data (an OpenMapTiles
/// `transportation` feature of class `path` or `track`).
class TrailPolyline {
  const TrailPolyline({required this.points, required this.kind, this.name});

  /// Ordered trail geometry in latitude/longitude.
  final List<LatLng> points;

  /// The OpenMapTiles `class` (for example `path` or `track`).
  final String kind;

  /// The trail name when present.
  final String? name;
}

/// A match of a query point onto a specific trail in a [TrailNetwork].
class TrailMatch {
  const TrailMatch({required this.trailIndex, required this.projection});

  final int trailIndex;
  final PolylineProjection projection;
}

/// A collection of trail lines with proximity and junction queries. Built from
/// downloaded vector tiles so the app can snap routes onto real trails and
/// detect junctions while fully offline.
class TrailNetwork {
  const TrailNetwork(this.trails);

  final List<TrailPolyline> trails;

  bool get isEmpty => trails.isEmpty;

  /// Returns the nearest trail point within [maxMeters], or null.
  TrailMatch? nearest(LatLng query, {double maxMeters = 30}) {
    TrailMatch? best;
    for (var i = 0; i < trails.length; i++) {
      final projection = nearestOnPolyline(query, trails[i].points);
      if (projection == null) continue;
      if (projection.distanceMeters <= maxMeters &&
          (best == null ||
              projection.distanceMeters < best.projection.distanceMeters)) {
        best = TrailMatch(trailIndex: i, projection: projection);
      }
    }
    return best;
  }

  /// Approximate trail junctions: grid nodes where three or more distinct
  /// trail directions meet. [gridMeters] quantizes coordinates so vertices that
  /// coincide at an OSM junction are treated as the same node.
  List<LatLng> junctions({double gridMeters = 8}) {
    if (trails.isEmpty) return const [];

    final referenceLat = trails.first.points.first.latitude;
    final dLat = gridMeters / 111320.0;
    final dLon =
        gridMeters /
        (111320.0 * math.max(0.01, math.cos(referenceLat * math.pi / 180.0)));

    (int, int) cell(LatLng p) =>
        ((p.latitude / dLat).round(), (p.longitude / dLon).round());

    final neighbors = <(int, int), Set<(int, int)>>{};
    void link((int, int) a, (int, int) b) {
      if (a == b) return;
      neighbors.putIfAbsent(a, () => {}).add(b);
      neighbors.putIfAbsent(b, () => {}).add(a);
    }

    for (final trail in trails) {
      final cells = trail.points.map(cell).toList(growable: false);
      neighbors.putIfAbsent(cells.first, () => {});
      for (var i = 1; i < cells.length; i++) {
        link(cells[i - 1], cells[i]);
      }
    }

    final result = <LatLng>[];
    neighbors.forEach((node, links) {
      if (links.length >= 3) {
        result.add(LatLng(node.$1 * dLat, node.$2 * dLon));
      }
    });
    return result;
  }
}
