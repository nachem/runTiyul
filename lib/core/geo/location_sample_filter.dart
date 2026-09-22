import 'dart:math' as math;

class LocationSampleFilter {
  const LocationSampleFilter({
    this.maximumAccuracyMeters = 60,
    this.minimumJumpAllowanceMeters = 200,
    this.maximumPlausibleSpeedMetersPerSecond = 12,
    this.maximumContinuousGap = const Duration(minutes: 5),
  });

  final double maximumAccuracyMeters;
  final double minimumJumpAllowanceMeters;
  final double maximumPlausibleSpeedMetersPerSecond;
  final Duration maximumContinuousGap;

  bool hasUsableAccuracy(double accuracyMeters) =>
      accuracyMeters.isFinite &&
      accuracyMeters >= 0 &&
      accuracyMeters <= maximumAccuracyMeters;

  /// Returns the distance to add, zero when a long outage starts a new
  /// segment, or null when the step is invalid or physically implausible.
  double? acceptedDistance({
    required double distanceMeters,
    required Duration elapsed,
  }) {
    if (!distanceMeters.isFinite ||
        distanceMeters < 0 ||
        elapsed <= Duration.zero) {
      return null;
    }
    if (elapsed >= maximumContinuousGap) return 0;

    final elapsedSeconds =
        elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    final allowedDistance = math.max(
      minimumJumpAllowanceMeters,
      maximumPlausibleSpeedMetersPerSecond * elapsedSeconds,
    );
    return distanceMeters <= allowedDistance ? distanceMeters : null;
  }
}
