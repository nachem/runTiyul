import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trail_runner/features/routes/route_editor_draft.dart';
import 'package:trail_runner/services/route_trail_builder.dart';
import 'package:trail_runner/services/trail_network.dart';
import 'package:trail_runner/services/trail_router.dart';

void main() {
  test(
    'RTE-003: repeated taps snapping to the same point do not duplicate controls',
    () {
      final router = TrailRouter(
        const TrailNetwork([
          TrailPolyline(points: [LatLng(0, 0), LatLng(0, 0.004)], kind: 'path'),
        ]),
      );
      final draft = RouteEditorDraft(const [LatLng(0, 0.002)]);
      expect(
        draft.append(
          const LatLng(0.0001, 0.002),
          router: router,
          followTrails: true,
          allowDirectConnections: true,
        ),
        same(draft),
      );
    },
  );

  final bends = <String, List<LatLng>>{
    'park path with an S-bend': const [
      LatLng(31.8, 35.2),
      LatLng(31.801, 35.2),
      LatLng(31.801, 35.201),
      LatLng(31.802, 35.201),
      LatLng(31.802, 35.202),
    ],
    'intentional narrow hairpin': const [
      LatLng(31.8, 35.2),
      LatLng(31.802, 35.2),
      LatLng(31.802, 35.2002),
      LatLng(31.8, 35.2002),
    ],
  };
  for (final scenario in bends.entries) {
    test('RTE-011: ${scenario.key} retains all intended turns', () {
      final network = TrailNetwork([
        TrailPolyline(points: scenario.value, kind: 'path'),
      ]);
      final plan = RouteTrailBuilder().planOnNetwork(scenario.value, network)!;
      expect(plan.directSegments, isEmpty);
      for (final point in scenario.value) {
        expect(
          plan.points.any(
            (candidate) =>
                (candidate.latitude - point.latitude).abs() < 1e-9 &&
                (candidate.longitude - point.longitude).abs() < 1e-9,
          ),
          isTrue,
        );
      }
    });
  }

  test('RTE-003: route entering a T-junction works from either direction', () {
    final router = TrailRouter(
      const TrailNetwork([
        TrailPolyline(points: [LatLng(0, 0), LatLng(0, 0.004)], kind: 'path'),
        TrailPolyline(
          points: [LatLng(0, 0.002), LatLng(0.002, 0.002)],
          kind: 'path',
        ),
      ]),
    );
    for (final longitude in [0.0005, 0.0035]) {
      final road = router.snap(LatLng(0, longitude))!;
      final branch = router.snap(const LatLng(0.0015, 0.002))!;
      for (final anchors in [
        [road, branch],
        [branch, road],
      ]) {
        final path = router.buildConnectedLeg(anchors.first, anchors.last);
        expect(path, isNotNull);
        expect(path, contains(const LatLng(0, 0.002)));
      }
    }
  });

  test(
    'RTE-003: a bridge endpoint over a ground segment is not a junction',
    () {
      final router = TrailRouter(
        const TrailNetwork([
          TrailPolyline(
            points: [LatLng(-0.002, 0), LatLng(0.002, 0)],
            kind: 'path',
          ),
          TrailPolyline(
            points: [LatLng(0, 0), LatLng(0, 0.002)],
            kind: 'path',
            level: 1,
            structure: 'bridge',
          ),
        ]),
      );
      final ground = router.snap(const LatLng(-0.0015, 0))!;
      final bridge = router.snap(const LatLng(0, 0.0015))!;
      expect(router.buildConnectedLeg(ground, bridge), isNull);
      final plan = router.planWaypoints([
        ground.point,
        bridge.point,
      ], allowDirectConnections: true)!;
      expect(plan.directSegments, [0]);
    },
  );

  test('RTE-003: a private connector does not become a mapped path', () {
    final router = TrailRouter(
      const TrailNetwork([
        TrailPolyline(points: [LatLng(0, 0), LatLng(0, 0.002)], kind: 'path'),
        TrailPolyline(
          points: [LatLng(0, 0.002), LatLng(0.001, 0.002)],
          kind: 'path',
          routable: false,
        ),
        TrailPolyline(
          points: [LatLng(0.001, 0.002), LatLng(0.001, 0.004)],
          kind: 'path',
        ),
      ]),
    );
    const waypoints = [LatLng(0, 0.0005), LatLng(0.001, 0.0035)];
    expect(router.planWaypoints(waypoints), isNull);
    expect(
      router
          .planWaypoints(waypoints, allowDirectConnections: true)!
          .directSegments,
      [0],
    );
  });

  test('RTE-003: near parallel path endpoints remain separate', () {
    final router = TrailRouter(
      const TrailNetwork([
        TrailPolyline(points: [LatLng(0, 0), LatLng(0, 0.004)], kind: 'path'),
        TrailPolyline(
          points: [LatLng(0.00002, 0.001), LatLng(0.00002, 0.003)],
          kind: 'path',
        ),
      ]),
    );
    expect(
      router.buildConnectedLeg(
        router.snap(const LatLng(0, 0.001))!,
        router.snap(const LatLng(0.00002, 0.003))!,
      ),
      isNull,
    );
  });

  test('RTE-011: dense off-map detail is retained during partial snapping', () {
    const network = TrailNetwork([
      TrailPolyline(points: [LatLng(0, 0), LatLng(0, 0.004)], kind: 'path'),
    ]);
    final original = [
      const LatLng(0.0001, 0),
      for (var index = 0; index < 12; index++)
        LatLng(0.001 + index * 0.00001, 0.002),
      const LatLng(0.0001, 0.004),
    ];
    final plan = RouteTrailBuilder().planOnNetwork(original, network)!;
    for (final point in original.skip(1).take(12)) {
      expect(plan.points, contains(point));
    }
    expect(plan.directSegments, isNotEmpty);
  });

  test('RTE-012: removing an off-map stop clears only its direct segments', () {
    final router = TrailRouter(
      const TrailNetwork([
        TrailPolyline(points: [LatLng(0, 0), LatLng(0, 0.004)], kind: 'path'),
      ]),
    );
    var draft = RouteEditorDraft(const []);
    for (final point in const [
      LatLng(0, 0),
      LatLng(0.001, 0.002),
      LatLng(0, 0.003),
      LatLng(0, 0.004),
    ]) {
      draft = draft.append(
        point,
        router: router,
        followTrails: true,
        allowDirectConnections: true,
      )!;
    }
    expect(draft.directSegments, [0, 1]);
    final removed = draft.removeControl(
      1,
      router: router,
      followTrails: true,
      allowDirectConnections: true,
    )!;
    expect(removed.directSegments, isEmpty);
    expect(removed.controls, const [
      LatLng(0, 0),
      LatLng(0, 0.003),
      LatLng(0, 0.004),
    ]);
    expect(draft.directSegments, [0, 1]);
    final inserted = draft.insertControl(const LatLng(0.0005, 0.001))!;
    expect(inserted.draft.directSegments, [0, 1, 2]);
  });

  test(
    'RTE-011: whole-route planning snaps nearby points without dropping an off-map stop',
    () {
      const network = TrailNetwork([
        TrailPolyline(points: [LatLng(0, 0), LatLng(0, 0.004)], kind: 'path'),
      ]);
      const far = LatLng(0.001, 0.002);
      const original = [LatLng(0.0001, 0), far, LatLng(0.0001, 0.004)];
      final builder = RouteTrailBuilder();
      final plan = builder.planOnNetwork(original, network)!;
      expect(plan.points.first.latitude, closeTo(0, 1e-10));
      expect(plan.points, contains(far));
      expect(plan.points.last.latitude, closeTo(0, 1e-10));
      expect(plan.directSegments, hasLength(2));
      expect(builder.matchOnNetwork(original, network), isNull);
    },
  );

  test(
    'RTE-003: nearby taps snap and distant taps retain direct connections',
    () {
      final router = TrailRouter(
        const TrailNetwork([
          TrailPolyline(points: [LatLng(0, 0), LatLng(0, 0.004)], kind: 'path'),
        ]),
      );
      var draft = RouteEditorDraft(const []).append(
        const LatLng(0.0001, 0.001),
        router: router,
        followTrails: true,
        allowDirectConnections: true,
      )!;
      expect(draft.points.single.latitude, closeTo(0, 1e-10));
      draft = draft.append(
        const LatLng(0.0001, 0.002),
        router: router,
        followTrails: true,
        allowDirectConnections: true,
      )!;
      expect(draft.controls.last.latitude, closeTo(0, 1e-10));
      expect(draft.directSegments, isEmpty);
      const far = LatLng(0.003, 0.004);
      final extended = draft.append(
        far,
        router: router,
        followTrails: true,
        allowDirectConnections: true,
      )!;
      expect(extended.points.last, far);
      expect(extended.points.take(draft.points.length), draft.points);
      expect(extended.directSegments, [extended.points.length - 2]);
      expect(extended.removeControl(2)!.directSegments, isEmpty);
    },
  );

  test(
    'RTE-003: planning selects a connected candidate beside an isolated fragment',
    () {
      final router = TrailRouter(
        const TrailNetwork([
          TrailPolyline(points: [LatLng(0, 0), LatLng(0, 0.004)], kind: 'path'),
          TrailPolyline(
            points: [LatLng(0.00002, 0.0015), LatLng(0.00002, 0.0025)],
            kind: 'path',
          ),
        ]),
      );
      final result = router.planWaypoints(const [
        LatLng(0, 0),
        LatLng(0.00002, 0.002),
      ], allowDirectConnections: true)!;
      expect(result.directSegments, isEmpty);
      expect(result.points.last.latitude, closeTo(0, 1e-10));
    },
  );

  test(
    'RTE-003: missing map coverage produces explicit direct planning only',
    () {
      final router = TrailRouter(const TrailNetwork([]));
      const waypoints = [LatLng(0, 0), LatLng(0.001, 0.002), LatLng(0, 0.003)];
      expect(router.planWaypoints(waypoints), isNull);
      final plan = router.planWaypoints(
        waypoints,
        allowDirectConnections: true,
      )!;
      expect(plan.points, waypoints);
      expect(plan.directSegments, [0, 1]);
      expect(plan.snappedWaypoints, 0);
    },
  );

  test('RTE-011: sparse waypoints follow a mapped right-angle bend', () {
    const start = LatLng(0, 0);
    const corner = LatLng(0.002, 0);
    const finish = LatLng(0.002, 0.002);
    const network = TrailNetwork([
      TrailPolyline(points: [start, corner, finish], kind: 'path'),
    ]);

    final result = RouteTrailBuilder().matchOnNetwork([start, finish], network);

    expect(result, isNotNull);
    expect(result!.first, start);
    expect(result, contains(corner));
    expect(result.last, finish);
  });

  test('RTE-003: a same-level T-junction connects at a segment interior', () {
    const network = TrailNetwork([
      TrailPolyline(points: [LatLng(0, 0), LatLng(0, 0.003)], kind: 'path'),
      TrailPolyline(
        points: [LatLng(0, 0.0015), LatLng(0.002, 0.0015)],
        kind: 'path',
      ),
    ]);
    final router = TrailRouter(network);
    final start = router.snap(const LatLng(0, 0.0005))!;
    final finish = router.snap(const LatLng(0.0015, 0.0015))!;

    final result = router.buildConnectedLeg(start, finish);

    expect(result, isNotNull);
    expect(result, contains(const LatLng(0, 0.0015)));
    expect(result!.first, start.point);
    expect(result.last, finish.point);
  });
}
