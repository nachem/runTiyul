import 'package:flutter_test/flutter_test.dart';
import 'package:trail_runner/core/geo/location_sample_filter.dart';

void main() {
  const filter = LocationSampleFilter();

  test('ACT-004 accepts a plausible step after a delayed GPS fix', () {
    expect(
      filter.acceptedDistance(
        distanceMeters: 300,
        elapsed: const Duration(minutes: 2),
      ),
      300,
    );
  });

  test('ACT-004 rejects the same jump over a short interval', () {
    expect(
      filter.acceptedDistance(
        distanceMeters: 300,
        elapsed: const Duration(seconds: 2),
      ),
      isNull,
    );
  });

  test('ACT-004 resumes after a long outage without adding the gap', () {
    expect(
      filter.acceptedDistance(
        distanceMeters: 2500,
        elapsed: const Duration(minutes: 10),
      ),
      0,
    );
  });

  test('ACT-004 rejects invalid accuracy and non-forward timestamps', () {
    expect(filter.hasUsableAccuracy(double.nan), isFalse);
    expect(filter.hasUsableAccuracy(61), isFalse);
    expect(filter.hasUsableAccuracy(5), isTrue);
    expect(
      filter.acceptedDistance(distanceMeters: 5, elapsed: Duration.zero),
      isNull,
    );
  });
}
