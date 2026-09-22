import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trail_runner/services/trail_network.dart';

TrailPolyline _path(List<LatLng> points) =>
    TrailPolyline(points: points, kind: 'path');

void main() {
  final horizontal = _path(const [
    LatLng(0, -0.001),
    LatLng(0, 0),
    LatLng(0, 0.001),
  ]);
  final vertical = _path(const [
    LatLng(-0.001, 0),
    LatLng(0, 0),
    LatLng(0.001, 0),
  ]);

  test('detects a crossing as a single junction', () {
    final network = TrailNetwork([horizontal, vertical]);
    final junctions = network.junctions();

    expect(junctions, hasLength(1));
    expect(junctions.first.latitude, closeTo(0, 1e-3));
    expect(junctions.first.longitude, closeTo(0, 1e-3));
  });

  test('nearest returns the closest trail within range', () {
    final network = TrailNetwork([horizontal, vertical]);
    final match = network.nearest(const LatLng(0.00005, 0.0005));

    expect(match, isNotNull);
    expect(match!.trailIndex, 0);
    expect(match.projection.distanceMeters, lessThan(10));
  });

  test('nearest returns null when nothing is within range', () {
    final network = TrailNetwork([horizontal, vertical]);
    expect(network.nearest(const LatLng(0.01, 0.01)), isNull);
  });

  test('junction cues do not treat a bridge crossing as an intersection', () {
    final network = TrailNetwork([
      horizontal,
      TrailPolyline(
        points: vertical.points,
        kind: 'path',
        structure: 'bridge',
        level: 1,
      ),
    ]);
    expect(network.junctions(), isEmpty);
  });

  test('restricted ways cannot create junction cues or snap targets', () {
    final network = TrailNetwork([
      horizontal,
      TrailPolyline(points: vertical.points, kind: 'path', routable: false),
    ]);
    expect(network.junctions(), isEmpty);
    expect(network.nearest(const LatLng(0.0008, 0)), isNull);
  });
}
