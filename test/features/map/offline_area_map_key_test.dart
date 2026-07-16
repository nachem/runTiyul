import 'package:flutter_test/flutter_test.dart';
import 'package:trail_runner/core/geo/geo_bounds.dart';
import 'package:trail_runner/features/map/map_screen.dart';
import 'package:trail_runner/models/offline_area.dart';

OfflineArea _area({
  String id = 'a',
  GeoBounds bounds = const GeoBounds(north: 1, south: 0, east: 1, west: 0),
  int minZoom = 12,
  int maxZoom = 16,
  OfflineAreaStatus status = OfflineAreaStatus.downloading,
  int completedTiles = 0,
  int actualBytes = 0,
  DateTime? updatedAt,
}) => OfflineArea(
  id: id,
  name: id,
  bounds: bounds,
  minZoom: minZoom,
  maxZoom: maxZoom,
  providerId: 'test',
  status: status,
  totalTiles: 100,
  completedTiles: completedTiles,
  actualBytes: actualBytes,
  createdAt: DateTime.utc(2026, 7, 16),
  updatedAt: updatedAt ?? DateTime.utc(2026, 7, 16),
);

void main() {
  group('offlineAreaMapKey', () {
    test('is stable across download progress on the same area', () {
      // A download bumps completedTiles, actualBytes, status, and updatedAt on
      // every tile. The map key must not change, or the whole map (and its
      // controls) is torn down per tile, leaving a gray screen.
      final start = _area(
        status: OfflineAreaStatus.downloading,
        completedTiles: 0,
        actualBytes: 0,
        updatedAt: DateTime.utc(2026, 7, 16, 10),
      );
      final midDownload = _area(
        status: OfflineAreaStatus.downloading,
        completedTiles: 57,
        actualBytes: 1024 * 900,
        updatedAt: DateTime.utc(2026, 7, 16, 10, 0, 5),
      );
      final done = _area(
        status: OfflineAreaStatus.complete,
        completedTiles: 100,
        actualBytes: 1024 * 1600,
        updatedAt: DateTime.utc(2026, 7, 16, 10, 1),
      );

      expect(offlineAreaMapKey(midDownload), offlineAreaMapKey(start));
      expect(offlineAreaMapKey(done), offlineAreaMapKey(start));
    });

    test('changes when the area geometry is edited', () {
      final base = _area();
      expect(
        offlineAreaMapKey(_area(minZoom: 14)),
        isNot(offlineAreaMapKey(base)),
      );
      expect(
        offlineAreaMapKey(_area(maxZoom: 17)),
        isNot(offlineAreaMapKey(base)),
      );
      expect(
        offlineAreaMapKey(
          _area(bounds: const GeoBounds(north: 2, south: 0, east: 1, west: 0)),
        ),
        isNot(offlineAreaMapKey(base)),
      );
    });

    test('changes when a different area is shown, and none has a fixed key', () {
      expect(offlineAreaMapKey(_area(id: 'a')), isNot(offlineAreaMapKey(_area(id: 'b'))));
      expect(offlineAreaMapKey(null), 'main-map-none');
    });
  });
}
