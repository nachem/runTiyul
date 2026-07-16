import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:trail_runner/app/app_store.dart';
import 'package:trail_runner/data/app_database.dart';
import 'package:trail_runner/data/app_repository.dart';
import 'package:trail_runner/services/map_provider.dart';
import 'package:trail_runner/services/tile_store.dart';

const _lockedOsm = MapProviderConfig(
  id: 'openstreetmap-standard',
  label: 'Streets',
  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  attribution: 'OpenStreetMap contributors',
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
    tileDir = await Directory.systemTemp.createTemp('raster_dev_unlock');
    tileStore = await TileStore.at(tileDir);
  });

  tearDown(() async {
    await database.close();
    if (await tileDir.exists()) await tileDir.delete(recursive: true);
  });

  test(
    'developer raster unlock persists and promotes only public dev layers',
    () async {
      final store = await AppStore.forTesting(
        repository: repository,
        tileStore: tileStore,
        mapProvider: _lockedOsm,
        publicRasterDevUnlockCompiled: true,
      );
      addTearDown(store.dispose);

      expect(store.publicRasterDevUnlockAvailable, isTrue);
      expect(store.publicRasterDevDownloadsUnlocked, isFalse);
      expect(
        store.rasterDownloadProviders.map((provider) => provider.id),
        isNot(contains(_lockedOsm.id)),
      );

      expect(await store.enablePublicRasterDevDownloads(), isTrue);
      expect(store.publicRasterDevDownloadsUnlocked, isTrue);
      expect(store.publicRasterDevUnlockAvailable, isFalse);
      expect(
        store.rasterDownloadProviders.map((provider) => provider.id),
        contains(_lockedOsm.id),
      );
      expect(
        store.rasterDownloadProviders.map((provider) => provider.id),
        isNot(contains(MapProviderConfig.esriWorldImagery.id)),
      );

      final reloaded = await AppStore.forTesting(
        repository: repository,
        tileStore: tileStore,
        mapProvider: _lockedOsm,
        publicRasterDevUnlockCompiled: true,
      );
      addTearDown(reloaded.dispose);
      expect(reloaded.publicRasterDevDownloadsUnlocked, isTrue);
      expect(
        reloaded.rasterDownloadProviders.map((provider) => provider.id),
        contains(_lockedOsm.id),
      );
    },
  );

  test('unlock is impossible when the capability is compiled out', () async {
    final store = await AppStore.forTesting(
      repository: repository,
      tileStore: tileStore,
      mapProvider: _lockedOsm,
      publicRasterDevUnlockCompiled: false,
    );
    addTearDown(store.dispose);

    expect(store.publicRasterDevUnlockAvailable, isFalse);
    expect(await store.enablePublicRasterDevDownloads(), isFalse);
    expect(store.publicRasterDevDownloadsUnlocked, isFalse);
  });
}
