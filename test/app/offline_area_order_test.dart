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
  id: 'test',
  urlTemplate: 'https://example.invalid/{z}/{x}/{y}.png',
  attribution: 'Test',
  offlineDownloadsAllowed: false,
  isDevelopmentOsmOverride: false,
);

OfflineArea _area(String id) => OfflineArea(
  id: id,
  name: id,
  bounds: const GeoBounds(north: 1, south: 0, east: 1, west: 0),
  minZoom: 12,
  maxZoom: 12,
  providerId: _config.id,
  status: OfflineAreaStatus.complete,
  totalTiles: 0,
  completedTiles: 0,
  actualBytes: 0,
  createdAt: DateTime.utc(2026, 7, 16),
  updatedAt: DateTime.utc(2026, 7, 16),
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
    tileDir = await Directory.systemTemp.createTemp('area_order');
    tileStore = await TileStore.at(tileDir);
  });

  tearDown(() async {
    await database.close();
    await tileDir.delete(recursive: true);
  });

  test('reordering persists and is restored on reload', () async {
    await repository.saveOfflineArea(_area('a'));
    await repository.saveOfflineArea(_area('b'));
    await repository.saveOfflineArea(_area('c'));

    final store = await AppStore.forTesting(
      repository: repository,
      tileStore: tileStore,
      mapProvider: _config,
    );
    expect(store.offlineAreas, hasLength(3));

    // Move the last area to the top.
    final lastId = store.offlineAreas.last.id;
    await store.reorderOfflineAreas(2, 0);
    expect(store.offlineAreas.first.id, lastId);

    // A fresh store restores the saved order.
    final reloaded = await AppStore.forTesting(
      repository: repository,
      tileStore: tileStore,
      mapProvider: _config,
    );
    expect(reloaded.offlineAreas.first.id, lastId);
    expect(
      reloaded.offlineAreas.map((area) => area.id).toList(),
      store.offlineAreas.map((area) => area.id).toList(),
    );
  });
}
