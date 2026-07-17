import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'distance.dart';

/// Reduces points used to draw a polyline while preserving the original list
/// for persistence, navigation, and export.
List<LatLng> simplifyPolylineForRendering(
  List<LatLng> points, {
  required double toleranceMeters,
  GeoDistance distance = const GeoDistance(),
}) {
  if (points.length < 3 || toleranceMeters <= 0) return points;

  final simplified = <LatLng>[points.first];
  var lastKept = points.first;
  for (var index = 1; index < points.length - 1; index++) {
    final point = points[index];
    if (distance.metersBetween(lastKept, point) >= toleranceMeters) {
      simplified.add(point);
      lastKept = point;
    }
  }
  simplified.add(points.last);
  return simplified;
}

/// Approximate ground distance represented by one screen pixel at [zoom].
double renderingToleranceMeters(double latitude, double zoom) {
  const equatorMetersPerPixel = 156543.03392;
  final latitudeScale = math.cos(
    latitude.clamp(-85.0, 85.0) * 0.017453292519943295,
  );
  return equatorMetersPerPixel * latitudeScale / (1 << zoom.round());
}
