import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trail_runner/services/trail_network.dart';
import 'package:trail_runner/services/trail_router.dart';

void main() {
  test('snaps onto the trail line between sparse vertices, not to a vertex', () {
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
  });

  test('returns null when the query is not near any trail', () {
    final router = TrailRouter(
      TrailNetwork(const [
        TrailPolyline(points: [LatLng(0, 0), LatLng(0, 0.004)], kind: 'path'),
      ]),
    );

    expect(router.snap(const LatLng(0.01, 0.01), maxMeters: 40), isNull);
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

    final passesJunction = route.any(
      (p) => (p.latitude).abs() < 1e-6 && (p.longitude - 0.002).abs() < 1e-6,
    );
    expect(passesJunction, isTrue);
    expect(route.last.latitude, closeTo(0.0015, 1e-4));
  });
}
