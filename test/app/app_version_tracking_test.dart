import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:trail_runner/app/app_store.dart';
import 'package:trail_runner/data/app_database.dart';
import 'package:trail_runner/data/app_repository.dart';
import 'package:trail_runner/services/app_version_service.dart';
import 'package:trail_runner/services/map_provider.dart';
import 'package:trail_runner/services/tile_store.dart';

const _config = MapProviderConfig(
  id: 'test',
  urlTemplate: 'https://example.invalid/{z}/{x}/{y}.png',
  attribution: 'Test',
  offlineDownloadsAllowed: false,
  isDevelopmentOsmOverride: false,
);

const _firstVersion = AppVersionInfo(
  appName: 'RunTiyul',
  packageName: 'com.bernoulli.trailrunner.trail_runner',
  version: '1.2.1',
  buildNumber: '6',
);

const _updatedVersion = AppVersionInfo(
  appName: 'RunTiyul',
  packageName: 'com.bernoulli.trailrunner.trail_runner',
  version: '1.2.2',
  buildNumber: '7',
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
    tileDir = await Directory.systemTemp.createTemp('app_version_tracking');
    tileStore = await TileStore.at(tileDir);
  });

  tearDown(() async {
    await database.close();
    await tileDir.delete(recursive: true);
  });

  Future<AppStore> openStore(AppVersionInfo version) => AppStore.forTesting(
    repository: repository,
    tileStore: tileStore,
    mapProvider: _config,
    appVersion: version,
  );

  test(
    'first install stays quiet and a later version is acknowledged once',
    () async {
      final firstInstall = await openStore(_firstVersion);
      expect(firstInstall.hasPendingAppUpdate, isFalse);
      firstInstall.dispose();

      final updated = await openStore(_updatedVersion);
      expect(updated.hasPendingAppUpdate, isTrue);
      expect(updated.previousAppVersion, _firstVersion.identity);

      await updated.acknowledgeAppUpdate();
      expect(updated.hasPendingAppUpdate, isFalse);
      updated.dispose();

      final reopened = await openStore(_updatedVersion);
      expect(reopened.hasPendingAppUpdate, isFalse);
      reopened.dispose();
    },
  );
}
