import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trail_runner/services/route_snapper.dart';
import 'package:trail_runner/services/trail_network.dart';

void main() {
  final network = TrailNetwork(const [
    TrailPolyline(points: [LatLng(0, 0), LatLng(0, 0.002)], kind: 'path'),
  ]);

  test('snaps a route that runs close to a trail onto it', () {
    // Route ~11 m north of the trail (0.0001 deg latitude).
    final route = const [LatLng(0.0001, 0), LatLng(0.0001, 0.002)];

    final snapped = const RouteSnapper().snap(route, network);

    expect(snapped.length, greaterThan(route.length)); // densified
    for (final point in snapped) {
      final match = network.nearest(point, maxMeters: 30);
      expect(match, isNotNull);
      expect(match!.projection.distanceMeters, lessThan(2));
    }
  });

  test('leaves a route far from any trail unchanged', () {
    // Route ~111 m north of the trail, beyond the snap threshold.
    final route = const [LatLng(0.001, 0), LatLng(0.001, 0.002)];

    final snapped = const RouteSnapper().snap(route, network);

    for (final point in snapped) {
      expect(point.latitude, closeTo(0.001, 1e-4));
    }
  });

  test('stays on a trail it is already following until clearly off it', () {
    final trail = TrailNetwork(const [
      TrailPolyline(points: [LatLng(0, 0), LatLng(0, 0.004)], kind: 'path'),
    ]);
    // Joins the trail near its start (~5 m) then drifts to ~33 m north: beyond
    // the 25 m join distance but within the 50 m leave distance.
    const route = [LatLng(0.00005, 0), LatLng(0.0003, 0.002)];

    final snapped = const RouteSnapper().snap(route, trail);

    // A fresh join at the drifting tail would fail (it is ~33 m away)...
    expect(trail.nearest(route.last, maxMeters: 25), isNull);
    // ...but because the route was already on the trail, the tail is kept on
    // it (pulled back to latitude ~0) instead of flicking off.
    expect(snapped.last.latitude, lessThan(0.0001));
  });

  test('does not join a trail it only ever runs ~33 m from', () {
    final trail = TrailNetwork(const [
      TrailPolyline(points: [LatLng(0, 0), LatLng(0, 0.004)], kind: 'path'),
    ]);
    // Never comes within the 25 m join distance, so it stays unchanged.
    const route = [LatLng(0.0003, 0), LatLng(0.0003, 0.002)];

    final snapped = const RouteSnapper().snap(route, trail);

    for (final point in snapped) {
      expect(point.latitude, closeTo(0.0003, 1e-4));
    }
  });
}
