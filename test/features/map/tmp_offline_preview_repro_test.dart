import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:trail_runner/app/app_store.dart';
import 'package:trail_runner/core/geo/geo_bounds.dart';
import 'package:trail_runner/data/app_database.dart';
import 'package:trail_runner/data/app_repository.dart';
import 'package:trail_runner/features/map/map_screen.dart';
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

OfflineArea _area({required int minZoom, required int maxZoom}) => OfflineArea(
  id: 'high-min',
  name: 'High min zoom',
  bounds: const GeoBounds(north: 31.78, south: 31.76, east: 35.23, west: 35.21),
  minZoom: minZoom,
  maxZoom: maxZoom,
  providerId: _config.id,
  status: OfflineAreaStatus.complete,
  totalTiles: 4,
  completedTiles: 4,
  actualBytes: 4096,
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
    tileDir = await Directory.systemTemp.createTemp('offline_preview_repro');
    tileStore = await TileStore.at(tileDir);
  });

  tearDown(() async {
    await database.close();
    await tileDir.delete(recursive: true);
  });

  Future<void> run(WidgetTester tester, int minZoom, int maxZoom) async {
    final area = _area(minZoom: minZoom, maxZoom: maxZoom);
    final store = await tester.runAsync(() async {
      await repository.saveOfflineArea(area);
      final created = await AppStore.forTesting(
        repository: repository,
        tileStore: tileStore,
        mapProvider: _config,
      );
      created.focusOfflineArea(created.offlineAreas.single);
      await created.setMapTileMode(MapTileMode.offline);
      return created;
    });
    if (store == null) fail('AppStore setup did not complete');
    addTearDown(store.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MapScreen(store: store)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    final polygons = tester
        .widgetList<PolygonLayer>(find.byType(PolygonLayer))
        .expand((layer) => layer.polygons)
        .toList();
    expect(polygons, isNotEmpty);
    expect(
      polygons.every((polygon) => polygon.color == Colors.transparent),
      isTrue,
      reason: 'offline bounds should use outlines without tinting the map',
    );
  }

  testWidgets(
    'control 14-16',
    (tester) => run(tester, 14, 16),
    timeout: const Timeout(Duration(seconds: 20)),
  );

  testWidgets(
    'high min 17-17',
    (tester) => run(tester, 17, 17),
    timeout: const Timeout(Duration(seconds: 20)),
  );
}
