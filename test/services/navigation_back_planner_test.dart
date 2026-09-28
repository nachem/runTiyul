import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trail_runner/core/geo/distance.dart';
import 'package:trail_runner/services/navigation_back_planner.dart';

void main() {
  const planner = NavigationBackPlanner();
  const distance = GeoDistance();
  const outAndBack = [LatLng(0, 0), LatLng(0, 0.004), LatLng(0, 0)];

  test('NAV-011 outbound abort reverses the same route to home', () {
    final plan = planner.planHome(
      plannedRoute: outAndBack,
      breadcrumbs: const [],
      completedRouteMeters: 222,
      currentPosition: const LatLng(0, 0.002),
      headingDegrees: 90,
    )!;

    expect(plan.path.first.longitude, closeTo(0.002, 1e-8));
    expect(plan.path.last, outAndBack.first);
    expect(distance.pathLengthMeters(plan.path), closeTo(222, 5));
  });

  test('NAV-011 planned return leg continues forward to coincident home', () {
    final plan = planner.planHome(
      plannedRoute: outAndBack,
      breadcrumbs: const [],
      completedRouteMeters: 556,
      currentPosition: const LatLng(0, 0.003),
      headingDegrees: 270,
    )!;

    expect(plan.path.first.longitude, closeTo(0.003, 1e-8));
    expect(plan.path.last, outAndBack.last);
    expect(distance.pathLengthMeters(plan.path), closeTo(334, 5));
  });

  test('NAV-011 selected route point uses the shortest same-route segment', () {
    final plan = planner.planToRoutePoint(
      plannedRoute: outAndBack,
      target: const LatLng(0, 0.001),
      completedRouteMeters: 334,
      currentPosition: const LatLng(0, 0.003),
      headingDegrees: 90,
    )!;

    expect(plan.path.first.longitude, closeTo(0.003, 1e-8));
    expect(plan.path.last.longitude, closeTo(0.001, 1e-8));
    expect(distance.pathLengthMeters(plan.path), closeTo(222, 5));
  });

  test('NAV-011 free run retraces accepted breadcrumbs', () {
    const breadcrumbs = [
      LatLng(0, 0),
      LatLng(0.001, 0.001),
      LatLng(0.002, 0.001),
    ];
    final plan = planner.planHome(
      plannedRoute: const [],
      breadcrumbs: breadcrumbs,
      completedRouteMeters: 0,
      currentPosition: breadcrumbs.last,
    )!;

    expect(plan.path, breadcrumbs.reversed);
    expect(plan.destination, breadcrumbs.first);
  });
}
