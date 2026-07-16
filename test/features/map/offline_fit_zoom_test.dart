import 'package:flutter_test/flutter_test.dart';
import 'package:trail_runner/features/map/trail_map.dart';

void main() {
  group('offlineAwareFitZoom', () {
    test('online/auto fitting is not floored by the offline minimum', () {
      final fit = offlineAwareFitZoom(
        offlineMode: false,
        offlineRange: (14, 16),
      );
      expect(fit.min, isNull);
      expect(fit.max, 16);
    });

    test('offline fitting is floored at the downloaded minimum', () {
      // A large area fit to its bounds would otherwise drop below z14 and show
      // a blank (gray) map, so the fit must not go below the downloaded floor.
      final fit = offlineAwareFitZoom(
        offlineMode: true,
        offlineRange: (14, 16),
      );
      expect(fit.min, 14);
      expect(fit.max, 16);
    });

    test('offline fitting raises the cap when the download starts above it', () {
      // Raising the minimum download zoom to 17 (the reported scenario): both
      // the floor and cap become 17 so "Show on map" lands on real tiles
      // instead of gray.
      final fit = offlineAwareFitZoom(
        offlineMode: true,
        offlineRange: (17, 17),
      );
      expect(fit.min, 17);
      expect(fit.max, 17);
    });

    test('offline with no saved coverage keeps the default cap', () {
      final fit = offlineAwareFitZoom(offlineMode: true, offlineRange: null);
      expect(fit.min, isNull);
      expect(fit.max, 16);
    });
  });
}
