import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trail_runner/services/forward_route_recovery.dart';
import 'package:trail_runner/services/trail_network.dart';

void main() {
  const recovery = ForwardRouteRecovery();
  const plannedRoute = [LatLng(0, 0), LatLng(0, 0.004)];

  test(
    'recovery path advances with the runner and rejects stale direction',
    () {
      const previous = ForwardRouteRecoveryResult(
        path: [LatLng(0.001, 0.001), LatLng(0.001, 0.003), LatLng(0, 0.003)],
        reconnectPoint: LatLng(0, 0.003),
        reconnectAlongRouteMeters: 330,
        pathDistanceMeters: 333,
        initialBearingDegrees: 90,
      );
      final advanced = recovery.advance(
        previous,
        position: const LatLng(0.001, 0.002),
        headingDegrees: 90,
      )!;
      expect(advanced.path.first.longitude, closeTo(0.002, 0.000001));
      expect(
        advanced.pathDistanceMeters,
        lessThan(previous.pathDistanceMeters),
      );
      expect(
        recovery.advance(
          previous,
          position: const LatLng(0.001, 0.002),
          headingDegrees: 270,
        ),
        isNull,
      );
    },
  );

  test(
    'NAV-007 chooses the shortest forward connection, not the earliest rejoin',
    () {
      const route = [LatLng(0, 0), LatLng(0, 0.01)];
      const network = TrailNetwork([
        TrailPolyline(
          points: [
            LatLng(0, 0),
            LatLng(0, 0.0022),
            LatLng(0, 0.005),
            LatLng(0, 0.01),
          ],
          kind: 'path',
        ),
        TrailPolyline(
          points: [
            LatLng(0.001, 0.001),
            LatLng(0.001, 0.002),
            LatLng(0.001, 0.005),
          ],
          kind: 'path',
        ),
        TrailPolyline(
          points: [
            LatLng(0.001, 0.002),
            LatLng(0.003, 0.002),
            LatLng(0.003, 0.0022),
            LatLng(0, 0.0022),
          ],
          kind: 'path',
        ),
        TrailPolyline(
          points: [LatLng(0.001, 0.005), LatLng(0, 0.005)],
          kind: 'path',
        ),
      ]);
      final result = recovery.recover(
        position: const LatLng(0.001, 0.0012),
        headingDegrees: 90,
        plannedRoute: route,
        completedRouteMeters: 100,
        network: network,
      );
      expect(result, isNotNull);
      expect(result!.reconnectPoint.longitude, closeTo(0.005, 0.00001));
      expect(result.pathDistanceMeters, lessThan(560));
    },
  );

  test('forward search can ignore a shorter backward start', () {
    const network = TrailNetwork([
      TrailPolyline(points: [LatLng(0, 0), LatLng(0, 0.004)], kind: 'path'),
      TrailPolyline(
        points: [
          LatLng(0, 0),
          LatLng(0.001, 0),
          LatLng(0.001, 0.004),
          LatLng(0, 0.004),
        ],
        kind: 'path',
      ),
    ]);
    final result = recovery.recover(
      position: const LatLng(0.001, 0.001),
      headingDegrees: 90,
      plannedRoute: plannedRoute,
      completedRouteMeters: 0,
      network: network,
    );
    expect(result, isNotNull);
    expect(result!.initialBearingDegrees, closeTo(90, 1));
    expect(result.reconnectPoint.longitude, closeTo(0.004, 0.00001));
  });

  test('routes forward on mapped ways to reconnect ahead', () {
    const network = TrailNetwork([
      TrailPolyline(
        points: [LatLng(0, 0), LatLng(0, 0.003), LatLng(0, 0.004)],
        kind: 'path',
      ),
      TrailPolyline(
        points: [LatLng(0.001, 0.001), LatLng(0.001, 0.003)],
        kind: 'path',
      ),
      TrailPolyline(
        points: [LatLng(0.001, 0.003), LatLng(0, 0.003)],
        kind: 'path',
      ),
    ]);

    final result = recovery.recover(
      position: const LatLng(0.001, 0.0012),
      headingDegrees: 90,
      plannedRoute: plannedRoute,
      completedRouteMeters: 100,
      network: network,
    );

    expect(result, isNotNull);
    expect(result!.reconnectAlongRouteMeters, greaterThan(130));
    expect(result.initialBearingDegrees, closeTo(90, 2));
    expect(result.path.first.latitude, closeTo(0.001, 1e-6));
    expect(result.path.last.latitude, closeTo(0, 1e-6));
    expect(result.path.last.longitude, closeTo(0.003, 1e-4));
  });

  test('rejects a mapped connection that starts by backtracking', () {
    const network = TrailNetwork([
      TrailPolyline(
        points: [LatLng(0, 0), LatLng(0, 0.0005), LatLng(0, 0.004)],
        kind: 'path',
      ),
      TrailPolyline(
        points: [LatLng(0.001, 0.0005), LatLng(0.001, 0.002)],
        kind: 'path',
      ),
      TrailPolyline(
        points: [LatLng(0.001, 0.0005), LatLng(0, 0.0005)],
        kind: 'path',
      ),
    ]);

    final result = recovery.recover(
      position: const LatLng(0.001, 0.0018),
      headingDegrees: 90,
      plannedRoute: plannedRoute,
      completedRouteMeters: 40,
      network: network,
    );

    expect(result, isNull);
  });

  test('rejects a mapped connection outside the forward cone', () {
    const network = TrailNetwork([
      TrailPolyline(
        points: [LatLng(0, 0), LatLng(0, 0.002), LatLng(0, 0.004)],
        kind: 'path',
      ),
      TrailPolyline(
        points: [LatLng(0.001, 0.002), LatLng(0, 0.002)],
        kind: 'path',
      ),
    ]);

    expect(
      recovery.recover(
        position: const LatLng(0.0008, 0.002),
        headingDegrees: 90,
        plannedRoute: plannedRoute,
        completedRouteMeters: 100,
        network: network,
      ),
      isNull,
    );
  });

  test('never bridges disconnected ways through open terrain', () {
    const network = TrailNetwork([
      TrailPolyline(points: [LatLng(0, 0), LatLng(0, 0.004)], kind: 'path'),
      TrailPolyline(
        points: [LatLng(0.001, 0.001), LatLng(0.001, 0.003)],
        kind: 'path',
      ),
    ]);

    expect(
      recovery.recover(
        position: const LatLng(0.001, 0.0012),
        headingDegrees: 90,
        plannedRoute: plannedRoute,
        completedRouteMeters: 100,
        network: network,
      ),
      isNull,
    );
  });
}
