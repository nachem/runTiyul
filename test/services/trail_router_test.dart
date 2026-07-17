import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trail_runner/core/geo/distance.dart';
import 'package:trail_runner/services/trail_extractor.dart';
import 'package:trail_runner/services/trail_network.dart';
import 'package:trail_runner/services/trail_router.dart';

class _CountingDistance extends GeoDistance {
  var calls = 0;

  @override
  double metersBetween(LatLng a, LatLng b) {
    calls++;
    return super.metersBetween(a, b);
  }
}

void main() {
  test('defers graph construction until graph routing is needed', () {
    final distance = _CountingDistance();
    final router = TrailRouter(
      TrailNetwork(const [
        TrailPolyline(points: [LatLng(0, 0), LatLng(0, 0.002)], kind: 'path'),
      ]),
      distance: distance,
    );

    expect(distance.calls, 0);
    expect(router.nodeCount, 2);
    expect(distance.calls, 1);
  });

  test(
    'snaps onto the trail line between sparse vertices, not to a vertex',
    () {
      // A single ~445 m segment with vertices only at its ends.
      final router = TrailRouter(
        TrailNetwork(const [
          TrailPolyline(points: [LatLng(0, 0), LatLng(0, 0.004)], kind: 'path'),
        ]),
      );

      // Tap ~22 m off the MIDDLE of the segment: ~223 m from either vertex but
      // right next to the trail line.
      final anchor = router.snap(const LatLng(0.0002, 0.002), maxMeters: 40);

      expect(anchor, isNotNull);
      expect(anchor!.segmentIndex, 0);
      // Projected onto the line (latitude ~0) at the tapped longitude.
      expect(anchor.point.latitude, closeTo(0, 1e-5));
      expect(anchor.point.longitude, closeTo(0.002, 1e-4));
      expect(anchor.distanceMeters, lessThan(40));
    },
  );

  test('returns null when the query is not near any trail', () {
    final router = TrailRouter(
      TrailNetwork(const [
        TrailPolyline(points: [LatLng(0, 0), LatLng(0, 0.004)], kind: 'path'),
      ]),
    );

    expect(router.snap(const LatLng(0.01, 0.01), maxMeters: 40), isNull);
  });

  test('prefers the previous waypoint category when a tap is near both', () {
    // A trail (at the equator) and a road ~33 m north of it run parallel.
    final router = TrailRouter(
      TrailNetwork(const [
        TrailPolyline(points: [LatLng(0, 0), LatLng(0, 0.004)], kind: 'path'),
        TrailPolyline(
          points: [LatLng(0.0003, 0), LatLng(0.0003, 0.004)],
          kind: 'primary',
        ),
      ]),
    );

    // ~11 m from the road, ~22 m from the trail: both within snap distance.
    const tap = LatLng(0.0002, 0.002);

    // With no preference the nearest way (the road) wins.
    expect(router.snap(tap)!.category, WayCategory.road);

    // Preferring the previous waypoint's category keeps the anchor on that kind
    // of way even when the other kind is closer.
    expect(
      router.snap(tap, preferCategory: WayCategory.trail)!.category,
      WayCategory.trail,
    );
    expect(
      router.snap(tap, preferCategory: WayCategory.road)!.category,
      WayCategory.road,
    );
  });

  test('bridges straight instead of an unreasonable cross-trail detour', () {
    // Two parallel trails ~111 m apart, joined only by a long connector at the
    // far (east) end, so the only network path between their near ends loops
    // ~2 km around.
    final router = TrailRouter(
      TrailNetwork(const [
        TrailPolyline(points: [LatLng(0, 0), LatLng(0, 0.01)], kind: 'path'),
        TrailPolyline(
          points: [LatLng(0.001, 0), LatLng(0.001, 0.01)],
          kind: 'primary',
        ),
        TrailPolyline(
          points: [LatLng(0, 0.01), LatLng(0.001, 0.01)],
          kind: 'path',
        ),
      ]),
    );

    final a = router.snap(const LatLng(0, 0.001))!; // near end of trail 0
    final b = router.snap(const LatLng(0.001, 0.001))!; // near end of trail 1
    final route = router.buildRoute([a, b]);

    // The ~2 km loop is rejected as an unreasonable detour: the leg bridges the
    // ~111 m gap with a straight segment instead.
    expect(route, [a.point, b.point]);
    expect(router.buildConnectedRoute([a, b]), isNull);
  });

  test('strict route rejects anchors on disconnected trail networks', () {
    final router = TrailRouter(
      TrailNetwork(const [
        TrailPolyline(points: [LatLng(0, 0), LatLng(0, 0.002)], kind: 'path'),
        TrailPolyline(
          points: [LatLng(0.02, 0), LatLng(0.02, 0.002)],
          kind: 'path',
        ),
      ]),
    );

    final first = router.snap(const LatLng(0, 0.001))!;
    final far = router.snap(const LatLng(0.02, 0.001))!;

    expect(router.buildConnectedRoute([first, far]), isNull);
    expect(router.buildConnectedLeg(first, far), isNull);
    expect(router.buildRoute([first, far]), [first.point, far.point]);
  });

  test('route between two anchors on the same trail follows the trail', () {
    // L-shaped trail: east along the equator, then north at lon 0.002.
    final router = TrailRouter(
      TrailNetwork(const [
        TrailPolyline(
          points: [LatLng(0, 0), LatLng(0, 0.002), LatLng(0.002, 0.002)],
          kind: 'path',
        ),
      ]),
    );

    final a = router.snap(const LatLng(0.0001, 0.0005))!; // east leg
    final b = router.snap(const LatLng(0.0015, 0.0021))!; // north leg
    final route = router.buildRoute([a, b]);

    // It bends around the corner instead of cutting straight across.
    expect(route.length, 3);
    expect(route.first.longitude, closeTo(0.0005, 1e-4));
    expect(route[1].latitude, closeTo(0, 1e-6));
    expect(route[1].longitude, closeTo(0.002, 1e-6));
    expect(route.last.latitude, closeTo(0.0015, 1e-4));
  });

  test('route between anchors on connected trails passes the junction', () {
    // A "T": a horizontal trail with a mid-vertex, and a vertical trail that
    // shares that vertex as a junction.
    final router = TrailRouter(
      TrailNetwork(const [
        TrailPolyline(
          points: [LatLng(0, 0), LatLng(0, 0.002), LatLng(0, 0.004)],
          kind: 'path',
        ),
        TrailPolyline(
          points: [LatLng(0, 0.002), LatLng(0.002, 0.002)],
          kind: 'path',
        ),
      ]),
    );

    final a = router.snap(const LatLng(0.0001, 0.0005))!; // horizontal trail
    final b = router.snap(const LatLng(0.0015, 0.002))!; // vertical trail
    expect(a.trailIndex, isNot(b.trailIndex));

    final route = router.buildRoute([a, b]);
    final strictRoute = router.buildConnectedRoute([a, b]);

    final passesJunction = route.any(
      (p) => (p.latitude).abs() < 1e-6 && (p.longitude - 0.002).abs() < 1e-6,
    );
    expect(passesJunction, isTrue);
    expect(route.last.latitude, closeTo(0.0015, 1e-4));
    expect(strictRoute, route);
    expect(router.buildConnectedLeg(a, b), route);
  });
}
