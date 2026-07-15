import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trail_runner/core/geo/polyline_snap.dart';

void main() {
  test('projects a query onto the middle of a segment', () {
    final projection = nearestOnPolyline(const LatLng(0.0001, 0.0005), const [
      LatLng(0, 0),
      LatLng(0, 0.001),
    ])!;

    expect(projection.segmentIndex, 0);
    expect(projection.t, closeTo(0.5, 0.05));
    expect(projection.distanceMeters, closeTo(11.13, 1.0));
    expect(projection.point.latitude, closeTo(0, 1e-5));
    expect(projection.point.longitude, closeTo(0.0005, 1e-5));
  });

  test('clamps to the endpoint when the query is beyond the segment', () {
    final projection = nearestOnPolyline(const LatLng(0, 0.002), const [
      LatLng(0, 0),
      LatLng(0, 0.001),
    ])!;

    expect(projection.t, closeTo(1.0, 0.01));
    expect(projection.point.longitude, closeTo(0.001, 1e-5));
  });

  test('returns null for a degenerate polyline', () {
    expect(nearestOnPolyline(const LatLng(0, 0), const [LatLng(0, 0)]), isNull);
  });
}
