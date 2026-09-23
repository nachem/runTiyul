import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trail_runner/features/routes/route_editor_draft.dart';
import 'package:trail_runner/services/route_trail_builder.dart';
import 'package:trail_runner/services/trail_network.dart';
import 'package:trail_runner/services/trail_router.dart';
import 'package:trail_runner/services/vector_tile_source.dart';

class _MissingMapSource implements VectorTileSource {
  final requested = <String>{};
  int closes = 0;

  @override
  int get minZoom => 0;
  @override
  int get maxZoom => 14;

  @override
  Future<List<int>?> readTile(int zoom, int column, int row) async {
    requested.add('$zoom/$column/$row');
    return null;
  }

  @override
  Future<void> close() async {
    closes++;
  }
}

void main() {
  test(
    'RTE-003: two short gaps use the middle of a road without an end detour',
    () {
      final router = TrailRouter(
        const TrailNetwork([
          TrailPolyline(points: [LatLng(0, 0), LatLng(0, 0.004)], kind: 'path'),
          TrailPolyline(
            points: [LatLng(0.002, 0.001), LatLng(0.00004, 0.001)],
            kind: 'path',
          ),
          TrailPolyline(
            points: [LatLng(0.00004, 0.003), LatLng(0.002, 0.003)],
            kind: 'path',
          ),
        ]),
      );
      final plan = router.planWaypoints(
        const [LatLng(0.0019, 0.001), LatLng(0.0019, 0.003)],
        checkpointRouting: true,
        allowDirectConnections: true,
      )!;
      expect(plan.directSegments, hasLength(2));
      expect(plan.points, contains(const LatLng(0, 0.001)));
      expect(plan.points, contains(const LatLng(0, 0.003)));
      expect(plan.points, isNot(contains(const LatLng(0, 0))));
      expect(plan.points, isNot(contains(const LatLng(0, 0.004))));
    },
  );

  test('RTE-012: inserting a checkpoint control retains previous raw taps', () {
    const taps = [LatLng(0.0001, 0), LatLng(0.0001, 0.004)];
    final router = TrailRouter(
      const TrailNetwork([
        TrailPolyline(points: [LatLng(0, 0), LatLng(0, 0.004)], kind: 'path'),
      ]),
    );
    final plan = router.planWaypoints(
      taps,
      checkpointRouting: true,
      allowDirectConnections: true,
    )!;
    final draft = RouteEditorDraft.fromCheckpointPlan(taps, plan);
    final inserted = draft.insertControl(const LatLng(0, 0.002))!;
    expect(inserted.draft.checkpointInputs!.first, taps.first);
    expect(inserted.draft.checkpointInputs!.last, taps.last);
    expect(inserted.draft.checkpointInputs, hasLength(3));
    expect(draft.checkpointInputs, taps);
  });

  test(
    'RTE-003: missing connections expand the route corridor once within its tile budget',
    () async {
      final source = _MissingMapSource();
      var opens = 0;
      final builder = RouteTrailBuilder(
        openSource: (_) async {
          opens++;
          return source;
        },
      );
      const checkpoints = [LatLng(0, 0), LatLng(0, 0.001)];
      final network = await builder.networkForCheckpoints(
        checkpoints,
        'https://example.invalid/planet',
      );
      expect(network.isEmpty, isTrue);
      expect(source.requested, hasLength(25));
      expect(opens, 2);
      expect(source.closes, 2);
      await builder.networkForCheckpoints(
        checkpoints,
        'https://example.invalid/planet',
        allowNetwork: false,
      );
      expect(opens, 2);
      final uncached = RouteTrailBuilder(
        openSource: (_) async {
          fail('Offline checkpoint planning must not open an HTTP source.');
        },
      );
      final offline = await uncached.networkForCheckpoints(
        checkpoints,
        'https://example.invalid/planet',
        allowNetwork: false,
      );
      expect(offline.isEmpty, isTrue);
    },
  );

  test(
    'RTE-003: close switchback checkpoints stay distinct and follow the mapped bend',
    () {
      const start = LatLng(0, 0);
      const finish = LatLng(0, 0.0002);
      const network = TrailNetwork([
        TrailPolyline(points: [start, LatLng(0.002, 0)], kind: 'path'),
        TrailPolyline(
          points: [LatLng(0.002, 0), LatLng(0.002, 0.0002), finish],
          kind: 'path',
        ),
      ]);
      final plan = RouteTrailBuilder().planOnNetwork(
        [start, finish],
        network,
        checkpointRouting: true,
      )!;
      expect(plan.directSegments, isEmpty);
      expect(plan.points.first, start);
      expect(plan.points.last, finish);
      expect(plan.waypointIndices.first, isNot(plan.waypointIndices.last));
      expect(plan.points, contains(const LatLng(0.002, 0.0002)));
    },
  );

  test('RTE-003: nearby checkpoint stops under 20 meters are all retained', () {
    const stops = [LatLng(0, 0), LatLng(0, 0.00005), LatLng(0, 0.0001)];
    const network = TrailNetwork([
      TrailPolyline(points: [LatLng(0, 0), LatLng(0, 0.001)], kind: 'path'),
    ]);
    final plan = RouteTrailBuilder().planOnNetwork(
      stops,
      network,
      checkpointRouting: true,
    )!;
    expect(plan.waypointIndices, hasLength(stops.length));
    for (var index = 0; index < stops.length; index++) {
      final point = plan.points[plan.waypointIndices[index]];
      expect(point.latitude, closeTo(stops[index].latitude, 1e-10));
      expect(point.longitude, closeTo(stops[index].longitude, 1e-10));
    }
  });

  test(
    'RTE-003: planning picks the shorter complete route through all checkpoints',
    () {
      const network = TrailNetwork([
        TrailPolyline(
          points: [
            LatLng(0, 0),
            LatLng(0.003, 0),
            LatLng(0.003, 0.004),
            LatLng(0, 0.004),
          ],
          kind: 'path',
        ),
        TrailPolyline(
          points: [LatLng(0.0001, 0), LatLng(0.0001, 0.004)],
          kind: 'path',
        ),
      ]);
      final plan = RouteTrailBuilder().planOnNetwork(
        const [LatLng(0, 0), LatLng(0, 0.002), LatLng(0, 0.004)],
        network,
        checkpointRouting: true,
      )!;
      expect(plan.directSegments, isEmpty);
      expect(plan.waypointIndices, hasLength(3));
      expect(plan.points, contains(const LatLng(0.0001, 0.002)));
      expect(
        plan.points.every((point) => point.latitude <= 0.0001 + 1e-9),
        isTrue,
      );
    },
  );

  for (final level in [0, 1]) {
    test(
      'RTE-003: ${level == 0 ? 'parallel dangling ways' : 'bridge and ground'} are not joined as a short gap',
      () {
        final router = TrailRouter(
          TrailNetwork([
            const TrailPolyline(
              points: [LatLng(0, 0), LatLng(0, 0.004)],
              kind: 'path',
            ),
            TrailPolyline(
              points: const [LatLng(0.00004, 0.002), LatLng(0.00004, 0.004)],
              kind: 'path',
              level: level,
            ),
          ]),
        );
        const checkpoints = [LatLng(0, 0.001), LatLng(0.00004, 0.003)];
        final plan = router.planWaypoints(
          checkpoints,
          checkpointRouting: true,
          allowDirectConnections: true,
          snapLimits: const [1, 1],
        )!;
        expect(plan.points, checkpoints);
        expect(plan.directSegments, [0]);
      },
    );
  }

  test('RTE-003: a fully mapped alternative wins over a gap shortcut', () {
    final router = TrailRouter(
      const TrailNetwork([
        TrailPolyline(points: [LatLng(0, 0), LatLng(0, 0.001)], kind: 'path'),
        TrailPolyline(
          points: [LatLng(0, 0.00104), LatLng(0, 0.002)],
          kind: 'path',
        ),
        TrailPolyline(
          points: [
            LatLng(0.0001, 0),
            LatLng(0.002, 0),
            LatLng(0.002, 0.002),
            LatLng(0.0001, 0.002),
          ],
          kind: 'path',
        ),
      ]),
    );
    final plan = router.planWaypoints(
      const [LatLng(0, 0), LatLng(0, 0.002)],
      checkpointRouting: true,
      allowDirectConnections: true,
    )!;
    expect(plan.directSegments, isEmpty);
    expect(plan.points, contains(const LatLng(0.002, 0.002)));
  });

  test(
    'RTE-003: checkpoint routing stays local among many unrelated fragments',
    () {
      final network = TrailNetwork([
        for (var index = 0; index < 1500; index++)
          TrailPolyline(
            points: [
              LatLng(1 + index * 0.001, 1),
              LatLng(1 + index * 0.001, 1.001),
            ],
            kind: 'path',
          ),
        const TrailPolyline(
          points: [LatLng(0, 0), LatLng(0, 0.001)],
          kind: 'path',
        ),
        const TrailPolyline(
          points: [LatLng(0, 0.00104), LatLng(0, 0.002)],
          kind: 'path',
        ),
      ]);
      final plan = RouteTrailBuilder().planOnNetwork(
        const [LatLng(0, 0), LatLng(0, 0.002)],
        network,
        checkpointRouting: true,
      )!;
      expect(plan.directSegments, hasLength(1));
      expect(plan.points, contains(const LatLng(0, 0.00104)));
    },
  );

  test(
    'RTE-003: off-trail checkpoints retain their locations and follow the nearest trail',
    () {
      const start = LatLng(-0.0006, 0);
      const finish = LatLng(0.002, 0.0026);
      const corner = LatLng(0.002, 0);
      const network = TrailNetwork([
        TrailPolyline(
          points: [LatLng(0, 0), corner, LatLng(0.002, 0.002)],
          kind: 'path',
        ),
      ]);
      final plan = RouteTrailBuilder().planOnNetwork(
        [start, finish],
        network,
        checkpointRouting: true,
      )!;
      expect(plan.points.first, start);
      expect(plan.points.last, finish);
      expect(plan.points, contains(corner));
      expect(plan.directSegments, hasLength(2));
      expect(plan.points.length, greaterThan(4));
    },
  );

  test(
    'RTE-003: tiny fragment gap retains both trails with only the gap unmapped',
    () {
      const gapStart = LatLng(0, 0.002);
      const gapEnd = LatLng(0, 0.00204);
      final router = TrailRouter(
        const TrailNetwork([
          TrailPolyline(points: [LatLng(0, 0), gapStart], kind: 'path'),
          TrailPolyline(points: [gapEnd, LatLng(0, 0.004)], kind: 'path'),
        ]),
      );
      const checkpoints = [LatLng(0, 0.0001), LatLng(0, 0.0039)];
      final plan = router.planWaypoints(
        checkpoints,
        checkpointRouting: true,
        allowDirectConnections: true,
      )!;
      expect(plan.points, contains(gapStart));
      expect(plan.points, contains(gapEnd));
      expect(plan.directSegments, hasLength(1));
      final gap = plan.directSegments.single;
      expect(plan.points[gap], gapStart);
      expect(plan.points[gap + 1], gapEnd);
      expect(
        router.buildConnectedLeg(
          router.snap(checkpoints.first)!,
          router.snap(checkpoints.last)!,
        ),
        isNull,
      );
    },
  );

  test(
    'RTE-003: near T-junction gap connects to the interior of the closest way',
    () {
      final router = TrailRouter(
        const TrailNetwork([
          TrailPolyline(points: [LatLng(0, 0), LatLng(0, 0.004)], kind: 'path'),
          TrailPolyline(
            points: [LatLng(0.00004, 0.002), LatLng(0.002, 0.002)],
            kind: 'path',
          ),
        ]),
      );
      final plan = router.planWaypoints(
        const [LatLng(0, 0.0002), LatLng(0.0018, 0.002)],
        checkpointRouting: true,
        allowDirectConnections: true,
      )!;
      expect(plan.points, contains(const LatLng(0, 0.002)));
      expect(plan.points, contains(const LatLng(0.00004, 0.002)));
      expect(plan.directSegments, hasLength(1));
    },
  );

  test(
    'RTE-003: checkpoints prefer a mapped hairpin over a direct shortcut',
    () {
      const start = LatLng(0, 0);
      const finish = LatLng(0, 0.001);
      const network = TrailNetwork([
        TrailPolyline(points: [start, LatLng(0.004, 0)], kind: 'path'),
        TrailPolyline(
          points: [LatLng(0.004, 0), LatLng(0.004, 0.001), finish],
          kind: 'path',
        ),
      ]);

      final plan = RouteTrailBuilder().planOnNetwork(
        [start, finish],
        network,
        checkpointRouting: true,
      )!;

      expect(plan.directSegments, isEmpty);
      expect(plan.points, contains(const LatLng(0.004, 0)));
      expect(plan.points, contains(const LatLng(0.004, 0.001)));
    },
  );

  test(
    'RTE-003: nearby fragments do not hide the connected checkpoint route',
    () {
      final network = TrailNetwork([
        for (var index = 0; index < 7; index++)
          TrailPolyline(
            points: [
              LatLng(index * 0.00002, 0),
              LatLng(index * 0.00002, 0.001),
            ],
            kind: 'path',
          ),
        const TrailPolyline(
          points: [LatLng(0.00016, 0), LatLng(0.00016, 0.003)],
          kind: 'path',
        ),
      ]);

      final plan = RouteTrailBuilder().planOnNetwork(
        const [LatLng(0, 0), LatLng(0.00016, 0.003)],
        network,
        checkpointRouting: true,
      )!;

      expect(plan.directSegments, isEmpty);
      expect(plan.points.first.latitude, closeTo(0.00016, 1e-9));
    },
  );
}
