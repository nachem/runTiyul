import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:trail_runner/app/app_store.dart';
import 'package:trail_runner/core/geo/geo_bounds.dart';
import 'package:trail_runner/data/app_database.dart';
import 'package:trail_runner/data/app_repository.dart';
import 'package:trail_runner/models/offline_area.dart';
import 'package:trail_runner/models/trail_route.dart';
import 'package:trail_runner/services/map_provider.dart';
import 'package:trail_runner/services/tile_store.dart';

void main() {
  late AppDatabase database;
  late AppRepository repository;

  setUp(() {
    sqfliteFfiInit();
    database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    repository = AppRepository(database);
  });

  tearDown(() => database.close());

  test('schema persists and cascades route points', () async {
    final now = DateTime.utc(2026, 7, 14);
    final route = TrailRoute(
      id: 'route-1',
      name: 'Test route',
      source: RouteSource.manual,
      createdAt: now,
      updatedAt: now,
      points: const [
        RoutePoint(latitude: 31.7, longitude: 35.2),
        RoutePoint(latitude: 31.71, longitude: 35.21),
      ],
    );

    await repository.saveRoute(route);
    final loaded = await repository.loadRoutes();

    expect(loaded, hasLength(1));
    expect(loaded.single.name, 'Test route');
    expect(loaded.single.points, hasLength(2));

    await repository.deleteRoute(route.id);
    expect(await repository.loadRoutes(), isEmpty);
  });

  test('interrupted downloads recover as paused', () async {
    final now = DateTime.utc(2026, 7, 14);
    await repository.saveOfflineArea(
      OfflineArea(
        id: 'area-1',
        name: 'Interrupted',
        bounds: const GeoBounds(
          north: 31.8,
          south: 31.7,
          east: 35.3,
          west: 35.2,
        ),
        minZoom: 12,
        maxZoom: 13,
        providerId: 'test',
        status: OfflineAreaStatus.downloading,
        totalTiles: 10,
        completedTiles: 4,
        actualBytes: 1024,
        createdAt: now,
        updatedAt: now,
      ),
    );
    final directory = await Directory.systemTemp.createTemp(
      'trail_runner_tiles',
    );
    final store = await AppStore.forTesting(
      repository: repository,
      tileStore: await TileStore.at(directory),
      mapProvider: const MapProviderConfig(
        id: 'test',
        urlTemplate: 'https://example.invalid/{z}/{x}/{y}.png',
        attribution: 'Test',
        offlineDownloadsAllowed: false,
        isDevelopmentOsmOverride: false,
      ),
    );
    addTearDown(() async {
      store.dispose();
      await directory.delete(recursive: true);
    });

    expect(store.offlineAreas.single.status, OfflineAreaStatus.paused);
    expect(store.offlineAreas.single.completedTiles, 4);
  });

  test('route rename and duplicate persist', () async {
    final now = DateTime.utc(2026, 7, 14);
    final route = TrailRoute(
      id: 'route-1',
      name: 'Original',
      source: RouteSource.manual,
      createdAt: now,
      updatedAt: now,
      points: const [
        RoutePoint(latitude: 31.7, longitude: 35.2),
        RoutePoint(latitude: 31.71, longitude: 35.21),
      ],
    );
    await repository.saveRoute(route);
    final directory = await Directory.systemTemp.createTemp(
      'trail_runner_tiles',
    );
    final store = await AppStore.forTesting(
      repository: repository,
      tileStore: await TileStore.at(directory),
      mapProvider: const MapProviderConfig(
        id: 'test',
        urlTemplate: 'https://example.invalid/{z}/{x}/{y}.png',
        attribution: 'Test',
        offlineDownloadsAllowed: false,
        isDevelopmentOsmOverride: false,
      ),
    );
    addTearDown(() async {
      store.dispose();
      await directory.delete(recursive: true);
    });

    await store.renameRoute(store.routes.single, 'Renamed');
    await store.duplicateRoute(store.routes.single);

    final loaded = await repository.loadRoutes();
    expect(loaded, hasLength(2));
    expect(
      loaded.map((item) => item.name),
      containsAll(['Renamed', 'Renamed copy']),
    );
    expect(loaded.map((item) => item.id).toSet(), hasLength(2));
  });

  test('map tile source choice persists', () async {
    final directory = await Directory.systemTemp.createTemp(
      'trail_runner_tiles',
    );
    final tileStore = await TileStore.at(directory);
    final store = await AppStore.forTesting(
      repository: repository,
      tileStore: tileStore,
      mapProvider: const MapProviderConfig(
        id: 'test',
        urlTemplate: 'https://example.invalid/{z}/{x}/{y}.png',
        attribution: 'Test',
        offlineDownloadsAllowed: false,
        isDevelopmentOsmOverride: false,
      ),
    );

    await store.setMapTileMode(MapTileMode.online);
    store.dispose();
    final restored = await AppStore.forTesting(
      repository: repository,
      tileStore: tileStore,
      mapProvider: const MapProviderConfig(
        id: 'test',
        urlTemplate: 'https://example.invalid/{z}/{x}/{y}.png',
        attribution: 'Test',
        offlineDownloadsAllowed: false,
        isDevelopmentOsmOverride: false,
      ),
    );
    addTearDown(() async {
      restored.dispose();
      await directory.delete(recursive: true);
    });

    expect(restored.mapTileMode, MapTileMode.online);
  });

  test(
    'editing offline bounds removes only obsolete tile references',
    () async {
      final now = DateTime.utc(2026, 7, 14);
      final original = OfflineArea(
        id: 'area-1',
        name: 'Original bounds',
        bounds: const GeoBounds(
          north: 31.8,
          south: 31.7,
          east: 35.3,
          west: 35.2,
        ),
        minZoom: 12,
        maxZoom: 13,
        providerId: 'test',
        status: OfflineAreaStatus.complete,
        totalTiles: 2,
        completedTiles: 2,
        actualBytes: 200,
        createdAt: now,
        updatedAt: now,
      );
      await repository.saveOfflineArea(original);
      await repository.attachTile(
        areaId: original.id,
        tileKey: 'test/12/1/1',
        providerId: 'test',
        zoom: 12,
        x: 1,
        y: 1,
        relativePath: 'test/12/1/1.png',
        byteCount: 100,
      );
      await repository.attachTile(
        areaId: original.id,
        tileKey: 'test/12/2/2',
        providerId: 'test',
        zoom: 12,
        x: 2,
        y: 2,
        relativePath: 'test/12/2/2.png',
        byteCount: 100,
      );
      final updated = OfflineArea(
        id: original.id,
        name: 'Edited bounds',
        bounds: const GeoBounds(
          north: 31.75,
          south: 31.7,
          east: 35.25,
          west: 35.2,
        ),
        minZoom: 12,
        maxZoom: 12,
        providerId: 'test',
        status: OfflineAreaStatus.planned,
        totalTiles: 1,
        completedTiles: 0,
        actualBytes: 0,
        createdAt: now,
        updatedAt: now.add(const Duration(minutes: 1)),
      );

      final orphanPaths = await repository.replaceOfflineAreaPlan(updated, {
        'test/12/1/1',
      });

      expect(orphanPaths, ['test/12/2/2.png']);
      expect(
        (await repository.loadOfflineAreas()).single.name,
        'Edited bounds',
      );
      final remaining = await repository.unsharedTiles(original.id);
      expect(remaining, hasLength(1));
      expect(remaining.single['tile_key'], 'test/12/1/1');
    },
  );
}
