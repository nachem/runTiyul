import 'package:latlong2/latlong.dart';

enum ActivityStatus { recording, paused, completed }

class ActivitySample {
  const ActivitySample({
    required this.latitude,
    required this.longitude,
    required this.recordedAt,
    required this.accuracy,
    this.altitude,
    this.speed,
    this.heading,
  });

  final double latitude;
  final double longitude;
  final DateTime recordedAt;
  final double accuracy;
  final double? altitude;
  final double? speed;
  final double? heading;

  LatLng get latLng => LatLng(latitude, longitude);
}

class RunActivity {
  const RunActivity({
    required this.id,
    required this.status,
    required this.startedAt,
    required this.elapsed,
    required this.distanceMeters,
    required this.elevationGainMeters,
    required this.samples,
    this.routeId,
    this.endedAt,
  });

  final String id;
  final String? routeId;
  final ActivityStatus status;
  final DateTime startedAt;
  final DateTime? endedAt;
  final Duration elapsed;
  final double distanceMeters;
  final double elevationGainMeters;
  final List<ActivitySample> samples;

  RunActivity copyWith({
    ActivityStatus? status,
    DateTime? endedAt,
    Duration? elapsed,
    double? distanceMeters,
    double? elevationGainMeters,
    List<ActivitySample>? samples,
  }) {
    return RunActivity(
      id: id,
      routeId: routeId,
      status: status ?? this.status,
      startedAt: startedAt,
      endedAt: endedAt ?? this.endedAt,
      elapsed: elapsed ?? this.elapsed,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      elevationGainMeters: elevationGainMeters ?? this.elevationGainMeters,
      samples: samples ?? this.samples,
    );
  }
}
