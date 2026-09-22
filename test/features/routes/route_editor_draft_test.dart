import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trail_runner/features/routes/route_editor_draft.dart';
import 'package:trail_runner/services/trail_network.dart';
import 'package:trail_runner/services/trail_router.dart';

void main() {
  test('RTE-009 dense geometry remains lossless behind sparse controls', () {
    final points = [
      for (var index = 0; index < 1000; index++) LatLng(0, index * 0.00001),
    ];
    final draft = RouteEditorDraft(points);
    expect(draft.points, points);
    expect(draft.controls, [points.first, points.last]);
  });

  test('major bends get controls without exceeding the control budget', () {
    final points = [
      for (var index = 0; index < 200; index++)
        LatLng(index.isEven ? 0 : 0.001, index * 0.0001),
    ];
    final draft = RouteEditorDraft(points);
    expect(draft.controls.length, lessThanOrEqualTo(32));
    expect(draft.controlIndices.first, 0);
    expect(draft.controlIndices.last, 199);
    expect(draft.points, points);
  });

  test('a control can be inserted on a hidden part without changing shape', () {
    final points = [
      for (var index = 0; index < 100; index++) LatLng(0, index * 0.00001),
    ];
    final draft = RouteEditorDraft(points);
    final inserted = draft.insertControl(points[50])!;
    expect(inserted.draft.points, points);
    expect(inserted.draft.controls, [points.first, points[50], points.last]);
    expect(inserted.control, 1);
  });

  test(
    'moving a control keeps untouched geometry before and after its neighbors',
    () {
      final points = [
        for (var index = 0; index <= 100; index++) LatLng(0, index * 0.00001),
      ];
      var draft = RouteEditorDraft(points);
      for (final index in [20, 40, 60, 80]) {
        draft = draft.insertControl(points[index])!.draft;
      }
      final moved = draft.moveControl(2, const LatLng(0.0001, 0.0004))!;
      expect(moved.points.take(21), points.take(21));
      expect(moved.points.reversed.take(41), points.reversed.take(41));
      expect(moved.controls[2], const LatLng(0.0001, 0.0004));
      expect(draft.points, points);
    },
  );

  test(
    'connected editing rejects an unreal replacement and preserves the draft',
    () {
      const points = [LatLng(0, 0), LatLng(0, 0.001), LatLng(0, 0.002)];
      final draft = RouteEditorDraft(points).insertControl(points[1])!.draft;
      final router = TrailRouter(
        const TrailNetwork([
          TrailPolyline(points: [LatLng(0, 0), LatLng(0, 0.002)], kind: 'path'),
          TrailPolyline(
            points: [LatLng(0.001, 0), LatLng(0.001, 0.002)],
            kind: 'path',
          ),
        ]),
      );
      expect(
        draft.moveControl(
          1,
          const LatLng(0.001, 0.001),
          router: router,
          followTrails: true,
        ),
        isNull,
      );
      expect(draft.points, points);
    },
  );

  test('connected edit follows mapped bends around the moved control', () {
    const points = [LatLng(0, 0), LatLng(0, 0.001), LatLng(0, 0.002)];
    final draft = RouteEditorDraft(points).insertControl(points[1])!.draft;
    final router = TrailRouter(
      const TrailNetwork([
        TrailPolyline(points: [LatLng(0, 0), LatLng(0, 0.002)], kind: 'path'),
        TrailPolyline(
          points: [
            LatLng(0, 0),
            LatLng(0.001, 0),
            LatLng(0.001, 0.002),
            LatLng(0, 0.002),
          ],
          kind: 'path',
        ),
      ]),
    );
    final edited = draft.moveControl(
      1,
      const LatLng(0.001, 0.001),
      router: router,
      followTrails: true,
    )!;
    expect(edited.points, contains(const LatLng(0.001, 0)));
    expect(edited.points, contains(const LatLng(0.001, 0.002)));
    expect(edited.controls[1], const LatLng(0.001, 0.001));
  });
}
