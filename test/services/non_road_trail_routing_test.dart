import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trail_runner/features/routes/route_editor_draft.dart';
import 'package:trail_runner/services/route_maneuver_planner.dart';
import 'package:trail_runner/services/trail_extractor.dart';
import 'package:trail_runner/services/trail_network.dart';
import 'package:trail_runner/services/trail_router.dart';
import 'package:vector_tile/vector_tile.dart';

VectorTile _bendingTrailTile(
  String kind,
  String subclass, {
  bool multipart = false,
  bool restricted = false,
}) {
  final keys = ['class', 'subclass', 'name', if (restricted) 'foot'];
  final values = [
    VectorTileValue(stringValue: kind),
    VectorTileValue(stringValue: subclass),
    VectorTileValue(stringValue: 'Synthetic hill trail'),
    if (restricted) VectorTileValue(stringValue: 'no'),
  ];
  const first = [9, 2048, 6144, 18, 0, 2047, 2048, 0];
  const second = [9, 4096, 4096, 18, 2048, 0, 0, 2047];
  final geometries = multipart
      ? [
          <int>[...first, 9, 0, 0, 18, 2048, 0, 0, 2047],
        ]
      : [first, second];
  return VectorTile(
    layers: [
      VectorTileLayer(
        name: 'transportation',
        version: 2,
        extent: 4096,
        keys: keys,
        values: values,
        features: [
          for (var index = 0; index < geometries.length; index++)
            VectorTileFeature(
              id: Int64(index + 1),
              type: VectorTileGeomType.LINESTRING,
              tags: [
                for (var property = 0; property < keys.length; property++) ...[
                  property,
                  property,
                ],
              ],
              geometryList: geometries[index],
              extent: 4096,
              keys: keys,
              values: values,
            ),
        ],
      ),
    ],
  );
}

void main() {
  for (final kind in ['path', 'track']) {
    test(
      'RTE-003: Follow trails retains exact endpoints on opposite $kind hairpin arms',
      () {
        const start = LatLng(31.8, 35.2);
        const corner = LatLng(31.802, 35.2);
        const finish = LatLng(31.8, 35.2002);
        final router = TrailRouter(
          TrailNetwork([
            TrailPolyline(
              points: const [start, corner, LatLng(31.802, 35.2002), finish],
              kind: kind,
            ),
          ]),
        );
        for (final endpoints in const [
          [start, finish],
          [finish, start],
        ]) {
          final draft = RouteEditorDraft(
            const [],
          ).append(endpoints.first, router: router, followTrails: true)!;
          final extended = draft.append(
            endpoints.last,
            router: router,
            followTrails: true,
          )!;
          expect(extended.controls, endpoints);
          expect(extended.points, contains(corner));
          expect(extended.directSegments, isEmpty);
        }
      },
    );
  }

  for (final scenario in [
    ('path', 'footway'),
    ('path', 'steps'),
    ('track', 'track'),
  ]) {
    for (final multipart in [false, true]) {
      test(
        'RTE-003/NAV-008: ${scenario.$2} ${multipart ? 'multipart' : 'split'} tile geometry retains connections and turns',
        () {
          final trails = const TrailExtractor().extractFromTile(
            _bendingTrailTile(scenario.$1, scenario.$2, multipart: multipart),
            14,
            9794,
            6660,
          );
          expect(trails, hasLength(2));
          expect(
            trails.every(
              (trail) => trail.routable && trail.kind == scenario.$1,
            ),
            isTrue,
          );
          final router = TrailRouter(TrailNetwork(trails));
          final plan = router.planWaypoints(
            [trails.first.points.first, trails.last.points.last],
            checkpointRouting: true,
            allowDirectConnections: true,
          )!;

          expect(plan.directSegments, isEmpty);
          expect(plan.unroutedLegs, 0);
          expect(
            plan.points,
            containsAll({...trails.first.points, ...trails.last.points}),
          );
          final turns = const RouteManeuverPlanner().plan(plan.points);
          expect(turns, hasLength(2));
          expect(
            turns.every((turn) => (turn.turnDegrees.abs() - 90).abs() < 1),
            isTrue,
          );
        },
      );
    }
  }

  test('RTE-011: extracting a restricted footpath never makes it routable', () {
    final trails = const TrailExtractor().extractFromTile(
      _bendingTrailTile('path', 'footway', restricted: true),
      14,
      9794,
      6660,
    );
    expect(trails, hasLength(2));
    expect(trails.every((trail) => !trail.routable), isTrue);
    final router = TrailRouter(TrailNetwork(trails));
    expect(router.snap(trails.first.points.first), isNull);
    final plan = router.planWaypoints(
      [trails.first.points.first, trails.last.points.last],
      checkpointRouting: true,
      allowDirectConnections: true,
    )!;
    expect(plan.directSegments, isNotEmpty);
    expect(plan.snappedWaypoints, 0);
  });

  test(
    'RTE-003: adjacent checkpoints resolve a noisy tap between hairpin arms',
    () {
      final router = TrailRouter(
        const TrailNetwork([
          TrailPolyline(
            points: [
              LatLng(31.8, 35.2),
              LatLng(31.802, 35.2),
              LatLng(31.802, 35.2002),
              LatLng(31.8, 35.2002),
            ],
            kind: 'path',
          ),
        ]),
      );
      final plan = router.planWaypoints(
        const [
          LatLng(31.8002, 35.2),
          LatLng(31.8005, 35.20011),
          LatLng(31.801, 35.2),
        ],
        checkpointRouting: true,
        allowDirectConnections: true,
      )!;
      expect(plan.directSegments, isEmpty);
      expect(plan.waypointIndices, hasLength(3));
      expect(
        plan.points[plan.waypointIndices[1]].longitude,
        closeTo(35.2, 1e-9),
      );
      expect(plan.points.every((point) => point.latitude < 31.802), isTrue);
    },
  );

  test(
    'RTE-011: dense straight trail vertices do not crowd out snap alternatives',
    () {
      final router = TrailRouter(
        TrailNetwork([
          TrailPolyline(
            points: [
              for (var index = 0; index <= 500; index++)
                LatLng(0, index * 0.00001),
            ],
            kind: 'path',
          ),
          const TrailPolyline(
            points: [LatLng(0.0001, 0), LatLng(0.0001, 0.005)],
            kind: 'track',
          ),
        ]),
      );
      final candidates = router.snapCandidates(const LatLng(0.00002, 0.0025));
      expect(
        candidates.map((candidate) => candidate.trailIndex),
        containsAll([0, 1]),
      );
      expect(candidates.length, lessThanOrEqualTo(3));
    },
  );

  for (final kind in ['path', 'track', 'minor']) {
    test(
      'RTE-003: exact $kind taps keep a connected hairpin beside a shorter parallel way',
      () {
        const start = LatLng(31.8, 35.2);
        const corner = LatLng(31.802, 35.2);
        const finish = LatLng(31.8, 35.2002);
        final router = TrailRouter(
          TrailNetwork([
            TrailPolyline(
              points: const [start, corner, LatLng(31.802, 35.2002), finish],
              kind: kind,
            ),
            TrailPolyline(
              points: const [LatLng(31.79991, 35.2), LatLng(31.79991, 35.2002)],
              kind: kind == 'minor' ? 'path' : 'minor',
            ),
          ]),
        );

        final plan = router.planWaypoints(
          const [start, finish],
          checkpointRouting: true,
          allowDirectConnections: true,
        )!;

        expect(plan.points.first.latitude, closeTo(start.latitude, 1e-9));
        expect(plan.points.first.longitude, closeTo(start.longitude, 1e-9));
        expect(plan.points.last.latitude, closeTo(finish.latitude, 1e-9));
        expect(plan.points.last.longitude, closeTo(finish.longitude, 1e-9));
        expect(plan.points, contains(corner));
        expect(plan.directSegments, isEmpty);
      },
    );
  }

  for (final kind in ['path', 'track']) {
    test('RTE-011: $kind hairpin offers both nearby arms for snapping', () {
      final router = TrailRouter(
        TrailNetwork([
          TrailPolyline(
            points: const [
              LatLng(31.8, 35.2),
              LatLng(31.802, 35.2),
              LatLng(31.802, 35.2002),
              LatLng(31.8, 35.2002),
            ],
            kind: kind,
          ),
        ]),
      );

      final candidates = router.snapCandidates(
        const LatLng(31.8005, 35.20011),
        maxMeters: 30,
      );

      expect(
        candidates.map((anchor) => anchor.segmentIndex),
        containsAll([0, 2]),
      );
      expect(candidates.every((anchor) => anchor.distanceMeters <= 30), isTrue);
    });
  }
}
