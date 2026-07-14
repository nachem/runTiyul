import 'package:flutter_test/flutter_test.dart';
import 'package:trail_runner/core/geo/geo_bounds.dart';
import 'package:trail_runner/core/geo/tile_math.dart';
import 'package:trail_runner/core/units/formatters.dart';
import 'package:trail_runner/models/run_activity.dart';
import 'package:trail_runner/services/gpx_service.dart';

void main() {
  group('TilePlanner', () {
    test('enumerates a small selection deterministically', () {
      const bounds = GeoBounds(
        north: 31.79,
        south: 31.77,
        east: 35.23,
        west: 35.21,
      );

      final plan = const TilePlanner(maxTiles: 100).plan(bounds, 12, 13);

      expect(plan.tileCount, greaterThan(0));
      expect(plan.coordinates.toSet(), hasLength(plan.tileCount));
      expect(plan.estimateBytes(), plan.tileCount * 32 * 1024);
    });

    test('enforces the tile safety limit', () {
      const bounds = GeoBounds(north: 60, south: -60, east: 120, west: -120);

      expect(
        () => const TilePlanner(maxTiles: 10).plan(bounds, 5, 8),
        throwsStateError,
      );
    });
  });

  test('formats running metrics', () {
    expect(formatDistance(1500), '1.50 km');
    expect(
      formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
      '01:02:03',
    );
    expect(formatPace(1000, const Duration(minutes: 5)), '5:00 /km');
    expect(formatBytes(1024 * 1024), '1.0 MB');
  });

  group('GpxService', () {
    test('parses a track and preserves elevation', () {
      const xml = '''
        <gpx version="1.1" creator="test">
          <trk><name>Forest Loop</name><trkseg>
            <trkpt lat="31.7" lon="35.2"><ele>100</ele></trkpt>
            <trkpt lat="31.71" lon="35.21"><ele>110</ele></trkpt>
          </trkseg></trk>
        </gpx>
      ''';

      final route = const GpxService().parse(xml, 'fallback.gpx');

      expect(route.name, 'Forest Loop');
      expect(route.points, hasLength(2));
      expect(route.points.last.elevation, 110);
      expect(route.distanceMeters, greaterThan(0));
    });

    test('rejects an empty GPX file', () {
      const xml = '<gpx version="1.1" creator="test"></gpx>';
      expect(
        () => const GpxService().parse(xml, 'empty.gpx'),
        throwsFormatException,
      );
    });

    test('exports activity samples as a GPX track', () {
      final startedAt = DateTime.utc(2026, 7, 14, 8);
      final activity = RunActivity(
        id: 'activity-1',
        status: ActivityStatus.completed,
        startedAt: startedAt,
        endedAt: startedAt.add(const Duration(minutes: 5)),
        elapsed: const Duration(minutes: 5),
        distanceMeters: 1000,
        elevationGainMeters: 12,
        samples: [
          ActivitySample(
            latitude: 31.7,
            longitude: 35.2,
            altitude: 100,
            accuracy: 5,
            recordedAt: startedAt,
          ),
          ActivitySample(
            latitude: 31.71,
            longitude: 35.21,
            altitude: 110,
            accuracy: 5,
            recordedAt: startedAt.add(const Duration(minutes: 5)),
          ),
        ],
      );

      final xml = const GpxService().activityAsXml(activity);
      final parsed = const GpxService().parse(xml, 'export.gpx');

      expect(parsed.points, hasLength(2));
      expect(parsed.points.first.elevation, 100);
      expect(parsed.points.last.elevation, 110);
    });
  });
}
