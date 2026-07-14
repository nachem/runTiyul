import 'package:latlong2/latlong.dart';

import '../core/geo/distance.dart';

enum RouteSource { manual, gpx }

class RoutePoint {
  const RoutePoint({
    required this.latitude,
    required this.longitude,
    this.elevation,
    this.recordedAt,
  });

  final double latitude;
  final double longitude;
  final double? elevation;
  final DateTime? recordedAt;

  LatLng get latLng => LatLng(latitude, longitude);
}

class TrailRoute {
  TrailRoute({
    required this.id,
    required this.name,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
    required this.points,
    double? distanceMeters,
  }) : distanceMeters =
           distanceMeters ??
           const GeoDistance().pathLengthMeters(
             points.map((point) => point.latLng).toList(),
           );

  final String id;
  final String name;
  final RouteSource source;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<RoutePoint> points;
  final double distanceMeters;
}
