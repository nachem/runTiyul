import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:trail_runner/app/app_store.dart';
import 'package:trail_runner/data/app_database.dart';
import 'package:trail_runner/data/app_repository.dart';
import 'package:trail_runner/services/map_provider.dart';
import 'package:trail_runner/services/tile_store.dart';

const _config = MapProviderConfig(
  id: 'test',
  urlTemplate: 'https://example.invalid/{z}/{x}/{y}.png',
  attribution: 'Test',
  offlineDownloadsAllowed: false,
  isDevelopmentOsmOverride: false,
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
    tileDir = await Directory.systemTemp.createTemp('vector_setting');
    tileStore = await TileStore.at(tileDir);
  });

  tearDown(() async {
    await database.close();
    await tileDir.delete(recursive: true);
  });

  test(
    'setting an in-app vector source enables downloads and persists',
    () async {
      final store = await AppStore.forTesting(
        repository: repository,
        tileStore: tileStore,
        mapProvider: _config,
      );

      // No vector source yet. Debug builds still expose the small,
      // development-only CyclOSM raster path by default.
      expect(store.usesVectorSource, isFalse);
      expect(store.offlineDownloadsAllowed, isTrue);
      expect(
        store.rasterDownloadProviders.map((provider) => provider.id),
        contains('cyclosm'),
      );

      await store.setVectorSourceUrl('https://example.invalid/region.mbtiles');

      // Configuring a source enables the on-device conversion download path.
      expect(store.usesVectorSource, isTrue);
      expect(store.offlineDownloadsAllowed, isTrue);
      expect(store.vectorSourceUrl, 'https://example.invalid/region.mbtiles');

      // The setting persists across a reload from the same database.
      final reloaded = await AppStore.forTesting(
        repository: repository,
        tileStore: tileStore,
        mapProvider: _config,
      );
      expect(
        reloaded.vectorSourceUrl,
        'https://example.invalid/region.mbtiles',
      );
      expect(reloaded.usesVectorSource, isTrue);
      expect(reloaded.offlineDownloadsAllowed, isTrue);
    },
  );
}
