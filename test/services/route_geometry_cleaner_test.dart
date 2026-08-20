import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trail_runner/services/route_geometry_cleaner.dart';

void main() {
  const cleaner = RouteGeometryCleaner();

  test('removes a short return-to-junction spike', () {
    const start = LatLng(0, 0);
    const route = [
      start,
      LatLng(0, 0.0001),
      LatLng(0.000005, 0),
      LatLng(0, 0.001),
    ];

    expect(cleaner.clean(route), [start, route.last]);
  });

  test('preserves a deliberate longer out-and-back', () {
    const route = [
      LatLng(0, 0),
      LatLng(0, 0.0003),
      LatLng(0.000005, 0),
      LatLng(0, -0.001),
    ];

    expect(cleaner.clean(route), route);
  });
}
