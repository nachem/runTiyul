import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../../core/geo/distance.dart';
import '../../core/geo/polyline_snap.dart';
import '../../services/trail_router.dart';

/// RTE-003/RTE-009: sparse handles are separate from lossless route geometry.
class RouteEditorDraft {
  factory RouteEditorDraft(List<LatLng> points) => RouteEditorDraft._(
    List.unmodifiable(points),
    routeControlIndices(points),
  );

  const RouteEditorDraft._(this.points, this.controlIndices);

  final List<LatLng> points;
  final List<int> controlIndices;
  static const _distance = GeoDistance();

  List<LatLng> get controls => [
    for (final index in controlIndices) points[index],
  ];

  RouteEditorDraft? append(
    LatLng point, {
    TrailRouter? router,
    bool followTrails = false,
  }) {
    final goals = [if (points.isNotEmpty) points.last, point];
    final replacement = _connect(
      goals,
      router,
      followTrails,
      movableGoal: goals.length - 1,
    );
    if (replacement == null) return null;
    if (points.isEmpty) {
      return RouteEditorDraft._(List.unmodifiable(replacement.points), const [
        0,
      ]);
    }
    final joined = [...points, ...replacement.points.skip(1)];
    return RouteEditorDraft._(
      List.unmodifiable(joined),
      List.unmodifiable([...controlIndices, joined.length - 1]),
    );
  }

  RouteEditorDraft? moveControl(
    int control,
    LatLng point, {
    TrailRouter? router,
    bool followTrails = false,
  }) {
    if (control < 0 || control >= controlIndices.length) return null;
    final first = math.max(0, control - 1);
    final last = math.min(controlIndices.length - 1, control + 1);
    final goals = [
      for (var index = first; index <= last; index++)
        index == control ? point : points[controlIndices[index]],
    ];
    final replacement = _connect(
      goals,
      router,
      followTrails,
      movableGoal: control - first,
    );
    return replacement == null ? null : _replace(first, last, replacement);
  }

  RouteEditorDraft? removeControl(
    int control, {
    TrailRouter? router,
    bool followTrails = false,
  }) {
    if (control < 0 || control >= controlIndices.length) return null;
    if (controlIndices.length == 1) return RouteEditorDraft(const []);
    if (control == 0) {
      final offset = controlIndices[1];
      return RouteEditorDraft._(
        List.unmodifiable(points.skip(offset)),
        List.unmodifiable(
          controlIndices.skip(1).map((index) => index - offset),
        ),
      );
    }
    if (control == controlIndices.length - 1) {
      return RouteEditorDraft._(
        List.unmodifiable(points.take(controlIndices[control - 1] + 1)),
        List.unmodifiable(controlIndices.take(control)),
      );
    }
    final replacement = _connect(
      [
        points[controlIndices[control - 1]],
        points[controlIndices[control + 1]],
      ],
      router,
      followTrails,
    );
    return replacement == null
        ? null
        : _replace(control - 1, control + 1, replacement);
  }

  ({RouteEditorDraft draft, int control})? insertControl(
    LatLng point, {
    double maxMeters = 30,
  }) {
    final projection = nearestOnPolyline(point, points);
    if (projection == null || projection.distanceMeters > maxMeters) {
      return null;
    }
    final updated = [...points];
    var index = projection.segmentIndex;
    var inserted = false;
    if (_distance.metersBetween(points[index], projection.point) > 0.5) {
      index++;
      if (_distance.metersBetween(points[index], projection.point) > 0.5) {
        updated.insert(index, projection.point);
        inserted = true;
      }
    }
    final handles = [
      for (final handle in controlIndices)
        inserted && handle >= index ? handle + 1 : handle,
    ];
    if (!handles.contains(index)) handles.add(index);
    handles.sort();
    return (
      draft: RouteEditorDraft._(
        List.unmodifiable(updated),
        List.unmodifiable(handles),
      ),
      control: handles.indexOf(index),
    );
  }

  RouteEditorDraft _replace(
    int firstControl,
    int lastControl,
    ({List<LatLng> points, List<int> controls}) replacement,
  ) {
    final start = controlIndices[firstControl];
    final end = controlIndices[lastControl];
    final delta = replacement.points.length - (end - start + 1);
    return RouteEditorDraft._(
      List.unmodifiable([
        ...points.take(start),
        ...replacement.points,
        ...points.skip(end + 1),
      ]),
      List.unmodifiable([
        ...controlIndices.take(firstControl),
        for (final index in replacement.controls) start + index,
        for (final index in controlIndices.skip(lastControl + 1)) index + delta,
      ]),
    );
  }

  ({List<LatLng> points, List<int> controls})? _connect(
    List<LatLng> goals,
    TrailRouter? router,
    bool followTrails, {
    int? movableGoal,
  }) {
    if (!followTrails) {
      return (
        points: goals,
        controls: List.generate(goals.length, (index) => index),
      );
    }
    if (router == null) return null;
    final anchors = <TrailAnchor>[];
    for (var index = 0; index < goals.length; index++) {
      final anchor = router.snap(
        goals[index],
        maxMeters: index == movableGoal ? 40 : 2,
      );
      if (anchor == null) return null;
      anchors.add(anchor);
    }
    final geometry = <LatLng>[anchors.first.point];
    final handles = <int>[0];
    for (var index = 1; index < anchors.length; index++) {
      final leg = router.buildConnectedLeg(anchors[index - 1], anchors[index]);
      if (leg == null) return null;
      geometry.addAll(leg.skip(1));
      handles.add(geometry.length - 1);
    }
    return (points: geometry, controls: handles);
  }
}

List<int> routeControlIndices(
  List<LatLng> points, {
  int maxControls = 32,
  double toleranceMeters = 12,
}) {
  if (points.length <= 2) return List.generate(points.length, (index) => index);
  final kept = <int>[0, points.length - 1];
  while (kept.length < maxControls) {
    var greatestDeviation = toleranceMeters;
    int? selected;
    for (var segment = 1; segment < kept.length; segment++) {
      final first = kept[segment - 1];
      final last = kept[segment];
      for (var index = first + 1; index < last; index++) {
        final deviation = nearestOnPolyline(points[index], [
          points[first],
          points[last],
        ])!.distanceMeters;
        if (deviation > greatestDeviation) {
          greatestDeviation = deviation;
          selected = index;
        }
      }
    }
    if (selected == null) break;
    kept.add(selected);
    kept.sort();
  }
  return List.unmodifiable(kept);
}
