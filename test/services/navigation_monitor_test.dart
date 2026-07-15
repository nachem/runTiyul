import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trail_runner/services/navigation_monitor.dart';

void main() {
  const route = [LatLng(0, 0), LatLng(0, 0.01)];

  test('off-route fires after the persistence window and clears on return', () {
    final monitor = NavigationMonitor(
      config: const NavAlertConfig(
        offRouteMeters: 30,
        offRoutePersistence: 3,
        junctionEnabled: false,
      ),
    );

    expect(
      monitor.update(const LatLng(0, 0.005), route: route).triggered,
      NavAlert.none,
    );

    const off = LatLng(0.001, 0.005); // ~111 m off route
    expect(monitor.update(off, route: route).triggered, NavAlert.none);
    expect(monitor.update(off, route: route).triggered, NavAlert.none);
    final third = monitor.update(off, route: route);
    expect(third.triggered, NavAlert.offRoute);
    expect(third.offRoute, isTrue);

    // Already off route: does not re-trigger.
    expect(monitor.update(off, route: route).triggered, NavAlert.none);

    // Back on route clears the state.
    expect(
      monitor.update(const LatLng(0, 0.005), route: route).offRoute,
      isFalse,
    );
  });

  test('off-route disabled never fires', () {
    final monitor = NavigationMonitor(
      config: const NavAlertConfig(
        offRouteEnabled: false,
        offRoutePersistence: 1,
        junctionEnabled: false,
      ),
    );
    for (var i = 0; i < 5; i++) {
      expect(
        monitor.update(const LatLng(0.01, 0.005), route: route).triggered,
        NavAlert.none,
      );
    }
  });

  test('junction fires once when approaching and re-arms after leaving', () {
    final monitor = NavigationMonitor(
      config: const NavAlertConfig(offRouteEnabled: false, junctionMeters: 25),
    );
    const line = [LatLng(0, 0), LatLng(0, 0.01)];
    const junction = LatLng(0, 0.005);
    const near = LatLng(0, 0.0048); // ~22 m before the junction, on route
    const past = LatLng(0, 0.0052); // just beyond the junction

    final first = monitor.update(
      near,
      route: line,
      junctions: const [junction],
    );
    expect(first.triggered, NavAlert.junction);
    expect(first.junctionAhead, isNotNull);

    expect(
      monitor
          .update(near, route: line, junctions: const [junction])
          .triggered,
      NavAlert.none,
    );
    expect(
      monitor
          .update(past, route: line, junctions: const [junction])
          .junctionAhead,
      isNull,
    );
    expect(
      monitor
          .update(near, route: line, junctions: const [junction])
          .triggered,
      NavAlert.junction,
    );
  });

  test('junction reports advance distance and a left turn', () {
    final monitor = NavigationMonitor(
      config: const NavAlertConfig(offRouteEnabled: false, junctionMeters: 300),
    );
    // East ~222 m, then north ~222 m; the junction sits at the corner.
    const lRoute = [LatLng(0, 0), LatLng(0, 0.002), LatLng(0.002, 0.002)];
    const corner = LatLng(0, 0.002);
    const user = LatLng(0, 0.0005); // ~167 m before the corner along the route

    final status = monitor.update(
      user,
      route: lRoute,
      junctions: const [corner],
    );
    expect(status.junctionAhead, isNotNull);
    expect(status.junctionDistanceMeters, closeTo(167, 12));
    expect(status.junctionTurn, TurnDirection.left);
  });

  test('junction reports a right turn on a right-bending route', () {
    final monitor = NavigationMonitor(
      config: const NavAlertConfig(offRouteEnabled: false, junctionMeters: 300),
    );
    // East then south is a right turn at the corner.
    const rRoute = [LatLng(0, 0), LatLng(0, 0.002), LatLng(-0.002, 0.002)];
    const corner = LatLng(0, 0.002);

    final status = monitor.update(
      const LatLng(0, 0.0005),
      route: rRoute,
      junctions: const [corner],
    );
    expect(status.junctionTurn, TurnDirection.right);
  });

  test('junction reports continue straight when the route does not turn', () {
    final monitor = NavigationMonitor(
      config: const NavAlertConfig(offRouteEnabled: false, junctionMeters: 300),
    );
    const straight = [LatLng(0, 0), LatLng(0, 0.004)];
    final status = monitor.update(
      const LatLng(0, 0.0005),
      route: straight,
      junctions: const [LatLng(0, 0.002)],
    );
    expect(status.junctionAhead, isNotNull);
    expect(status.junctionTurn, TurnDirection.straight);
  });

  test('a junction already passed is not reported', () {
    final monitor = NavigationMonitor(
      config: const NavAlertConfig(offRouteEnabled: false, junctionMeters: 300),
    );
    const straight = [LatLng(0, 0), LatLng(0, 0.004)];
    final status = monitor.update(
      const LatLng(0, 0.003), // past the junction at 0.002
      route: straight,
      junctions: const [LatLng(0, 0.002)],
    );
    expect(status.junctionAhead, isNull);
    expect(status.triggered, NavAlert.none);
  });

  test('junction disabled never fires', () {
    final monitor = NavigationMonitor(
      config: const NavAlertConfig(
        junctionEnabled: false,
        offRouteEnabled: false,
      ),
    );
    expect(
      monitor
          .update(
            const LatLng(0, 0.005),
            route: const [LatLng(0, 0), LatLng(0, 0.01)],
            junctions: const [LatLng(0, 0.005)],
          )
          .triggered,
      NavAlert.none,
    );
  });
}
