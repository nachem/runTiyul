import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:trail_runner/app/app_store.dart';
import 'package:trail_runner/core/geo/geo_bounds.dart';
import 'package:trail_runner/data/app_database.dart';
import 'package:trail_runner/data/app_repository.dart';
import 'package:trail_runner/models/offline_area.dart';
import 'package:trail_runner/services/map_provider.dart';
import 'package:trail_runner/services/tile_store.dart';

const _config = MapProviderConfig(
  id: 'test-map',
  urlTemplate: 'https://example.invalid/{z}/{x}/{y}.png',
  attribution: 'Test',
  offlineDownloadsAllowed: false,
  isDevelopmentOsmOverride: false,
  vectorSourceUrl: 'https://example.invalid/vector/{z}/{x}/{y}.pbf',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late AppRepository repository;
  late Directory tileDir;
  late TileStore tileStore;

  setUp(() async {
    sqfliteFfiInit();
    database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    repository = AppRepository(database);
    tileDir = await Directory.systemTemp.createTemp('legacy_terrain');
    tileStore = await TileStore.at(tileDir);
  });

  tearDown(() async {
    await database.close();
    if (await tileDir.exists()) await tileDir.delete(recursive: true);
  });

  test(
    'reload removes legacy raw terrain but keeps the offline area',
    () async {
      final area = OfflineArea(
        id: 'area',
        name: 'Area',
        bounds: const GeoBounds(north: 1, south: 0, east: 1, west: 0),
        minZoom: 12,
        maxZoom: 12,
        providerId: _config.id,
        status: OfflineAreaStatus.complete,
        totalTiles: 1,
        completedTiles: 1,
        actualBytes: 8,
        createdAt: DateTime.utc(2026, 7, 16),
        updatedAt: DateTime.utc(2026, 7, 16),
        sourceFormat: OfflineSourceFormat.convertedVector,
      );
      await repository.saveOfflineArea(area);

      final raw = tileStore.fileFor('aws-terrarium', 12, 1, 2);
      await raw.parent.create(recursive: true);
      await raw.writeAsBytes([1, 2, 3, 4]);
      await repository.attachTile(
        areaId: area.id,
        tileKey: 'aws-terrarium/12/1/2',
        providerId: 'aws-terrarium',
        zoom: 12,
        x: 1,
        y: 2,
        relativePath: tileStore.relativePath(raw),
        byteCount: 4,
      );
      final cached = tileStore.fileFor('aws-terrarium-cache', 12, 3, 4);
      await cached.parent.create(recursive: true);
      await cached.writeAsBytes([5, 6, 7, 8]);
      await repository.saveSetting('show_contours', 'true');
      await repository.saveSetting('terrain_cache_limit_bytes', '1234');

      final store = await AppStore.forTesting(
        repository: repository,
        tileStore: tileStore,
        mapProvider: _config,
      );
      addTearDown(store.dispose);

      expect(store.offlineAreas.single.id, area.id);
      expect(await raw.exists(), isFalse);
      expect(await cached.exists(), isFalse);
      expect(await repository.unsharedTiles(area.id), isEmpty);
      expect(await repository.loadSetting('show_contours'), isNull);
      expect(await repository.loadSetting('terrain_cache_limit_bytes'), isNull);
      expect(await repository.loadSetting('legacy_terrain_cleanup_v1'), 'true');
    },
  );
}
