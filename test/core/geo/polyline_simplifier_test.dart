import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trail_runner/core/geo/polyline_simplifier.dart';

void main() {
  test(
    'render simplification reduces dense points and preserves endpoints',
    () {
      final points = [
        for (var index = 0; index <= 100; index++) LatLng(0, index * 0.000001),
      ];

      final simplified = simplifyPolylineForRendering(
        points,
        toleranceMeters: 10,
      );

      expect(simplified.length, lessThan(points.length));
      expect(simplified.first, points.first);
      expect(simplified.last, points.last);
      expect(points, hasLength(101));
    },
  );

  test('render simplification leaves short lines unchanged', () {
    const points = [LatLng(0, 0), LatLng(0, 0.001)];

    expect(
      simplifyPolylineForRendering(points, toleranceMeters: 10),
      same(points),
    );
  });

  test('render tolerance grows as the map zooms out', () {
    expect(
      renderingToleranceMeters(32, 10),
      greaterThan(renderingToleranceMeters(32, 14)),
    );
  });
}
