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

  factory RouteEditorDraft.fromCheckpointPlan(
    List<LatLng> checkpoints,
    TrailRoutePlan plan,
  ) {
    final indices = <int>[];
    final inputs = <LatLng>[];
    for (var index = 0; index < plan.waypointIndices.length; index++) {
      final handle = plan.waypointIndices[index];
      if (indices.isNotEmpty && indices.last == handle) continue;
      indices.add(handle);
      inputs.add(checkpoints[index]);
    }
    return RouteEditorDraft._(
      List.unmodifiable(plan.points),
      List.unmodifiable(indices),
      List.unmodifiable(plan.directSegments),
      List.unmodifiable(inputs),
    );
  }

  const RouteEditorDraft._(
    this.points,
    this.controlIndices, [
    this.directSegments = const [],
    this.checkpointInputs,
  ]);

  final List<LatLng> points;
  final List<int> controlIndices;
  final List<int> directSegments;
  final List<LatLng>? checkpointInputs;
  static const _distance = GeoDistance();

  List<LatLng> get controls => [
    for (final index in controlIndices) points[index],
  ];

  RouteEditorDraft? append(
    LatLng point, {
    TrailRouter? router,
    bool followTrails = false,
    bool allowDirectConnections = false,
  }) {
    final goals = [if (points.isNotEmpty) points.last, point];
    final replacement = _connect(
      goals,
      router,
      followTrails,
      allowDirectConnections: allowDirectConnections,
      movableGoal: goals.length - 1,
    );
    if (replacement == null) return null;
    if (points.isEmpty) {
      return RouteEditorDraft._(List.unmodifiable(replacement.points), const [
        0,
      ]);
    }
    if (replacement.points.length == 1 &&
        _distance.metersBetween(points.last, replacement.points.single) <=
            0.01) {
      return this;
    }
    final joined = [...points, ...replacement.points.skip(1)];
    return RouteEditorDraft._(
      List.unmodifiable(joined),
      List.unmodifiable([...controlIndices, joined.length - 1]),
      List.unmodifiable([
        ...directSegments,
        for (final segment in replacement.directSegments)
          points.length - 1 + segment,
      ]),
    );
  }

  RouteEditorDraft? moveControl(
    int control,
    LatLng point, {
    TrailRouter? router,
    bool followTrails = false,
    bool allowDirectConnections = false,
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
      allowDirectConnections: allowDirectConnections,
      movableGoal: control - first,
    );
    return replacement == null ? null : _replace(first, last, replacement);
  }

  RouteEditorDraft? removeControl(
    int control, {
    TrailRouter? router,
    bool followTrails = false,
    bool allowDirectConnections = false,
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
        List.unmodifiable([
          for (final segment in directSegments)
            if (segment >= offset) segment - offset,
        ]),
      );
    }
    if (control == controlIndices.length - 1) {
      return RouteEditorDraft._(
        List.unmodifiable(points.take(controlIndices[control - 1] + 1)),
        List.unmodifiable(controlIndices.take(control)),
        List.unmodifiable(
          directSegments.where(
            (segment) => segment < controlIndices[control - 1],
          ),
        ),
      );
    }
    final replacement = _connect(
      [
        points[controlIndices[control - 1]],
        points[controlIndices[control + 1]],
      ],
      router,
      followTrails,
      allowDirectConnections: allowDirectConnections,
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
    final originalInputs = checkpointInputs == null
        ? null
        : {
            for (var control = 0; control < handles.length; control++)
              handles[control]: checkpointInputs![control],
          };
    if (!handles.contains(index)) handles.add(index);
    handles.sort();
    return (
      draft: RouteEditorDraft._(
        List.unmodifiable(updated),
        List.unmodifiable(handles),
        List.unmodifiable([
          for (final segment in directSegments) ...[
            inserted && segment >= index ? segment + 1 : segment,
            if (inserted && segment == index - 1) segment + 1,
          ],
        ]),
        checkpointInputs == null
            ? null
            : List.unmodifiable([
                for (final handle in handles)
                  originalInputs![handle] ?? updated[handle],
              ]),
      ),
      control: handles.indexOf(index),
    );
  }

  RouteEditorDraft _replace(
    int firstControl,
    int lastControl,
    ({List<LatLng> points, List<int> controls, List<int> directSegments})
    replacement,
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
      List.unmodifiable([
        for (final segment in directSegments)
          if (segment < start) segment,
        for (final segment in replacement.directSegments) start + segment,
        for (final segment in directSegments)
          if (segment >= end) segment + delta,
      ]),
    );
  }

  ({List<LatLng> points, List<int> controls, List<int> directSegments})?
  _connect(
    List<LatLng> goals,
    TrailRouter? router,
    bool followTrails, {
    int? movableGoal,
    bool allowDirectConnections = false,
  }) {
    if (!followTrails) {
      return (
        points: goals,
        controls: List.generate(goals.length, (index) => index),
        directSegments: const [],
      );
    }
    if (router == null) {
      return allowDirectConnections
          ? (
              points: goals,
              controls: List.generate(goals.length, (index) => index),
              directSegments: List.generate(
                math.max(0, goals.length - 1),
                (index) => index,
              ),
            )
          : null;
    }
    final plan = router.planWaypoints(
      goals,
      snapLimits: [
        for (var index = 0; index < goals.length; index++)
          index == movableGoal ? 40 : 2,
      ],
      allowDirectConnections: allowDirectConnections,
    );
    return plan == null
        ? null
        : (
            points: plan.points,
            controls: plan.waypointIndices,
            directSegments: plan.directSegments,
          );
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
