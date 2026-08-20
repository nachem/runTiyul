import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trail_runner/services/route_maneuver_planner.dart';

void main() {
  const planner = RouteManeuverPlanner();

  test('classifies an exact 45 degree bend as bear right', () {
    const route = [LatLng(-0.001, 0), LatLng(0, 0), LatLng(0.001, 0.001)];

    final maneuver = planner.plan(route).single;
    expect(maneuver.turnDegrees, closeTo(45, 1));
    expect(maneuver.kind, ManeuverKind.bearRight);
  });

  test('preserves and classifies an intentional U-turn', () {
    const route = [LatLng(0, 0), LatLng(0, 0.0003), LatLng(0, 0)];

    final maneuver = planner.plan(route).single;
    expect(maneuver.turnDegrees.abs(), closeTo(180, 1));
    expect(maneuver.kind, ManeuverKind.uTurn);
  });

  test('retains a straight junction for consecutive instructions', () {
    const route = [LatLng(0, 0), LatLng(0, 0.002)];
    const junction = LatLng(0, 0.001);

    final maneuver = planner.plan(route, junctions: const [junction]).single;
    expect(maneuver.kind, ManeuverKind.straight);
    expect(maneuver.isJunction, isTrue);
  });
}
