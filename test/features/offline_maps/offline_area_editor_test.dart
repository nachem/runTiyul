import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:trail_runner/app/app_store.dart';
import 'package:trail_runner/core/geo/geo_bounds.dart';
import 'package:trail_runner/data/app_database.dart';
import 'package:trail_runner/data/app_repository.dart';
import 'package:trail_runner/features/offline_maps/offline_maps_screen.dart';
import 'package:trail_runner/models/offline_area.dart';
import 'package:trail_runner/services/map_provider.dart';
import 'package:trail_runner/services/tile_store.dart';

const _provider = MapProviderConfig(
  id: 'editor-test',
  urlTemplate: 'https://example.invalid/{z}/{x}/{y}.png',
  attribution: 'Test',
  offlineDownloadsAllowed: false,
  isDevelopmentOsmOverride: false,
);

class _EditorRepository extends AppRepository {
  _EditorRepository(super.database);

  final settings = <String, String>{};

  @override
  Future<String?> loadSetting(String key) async => settings[key];

  @override
  Future<void> saveSetting(String key, String value) async {
    settings[key] = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late _EditorRepository repository;
  late Directory tileDirectory;
  late AppStore store;

  setUp(() async {
    sqfliteFfiInit();
    database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    tileDirectory = await Directory.systemTemp.createTemp('offline_editor');
    repository = _EditorRepository(database);
    store = await AppStore.forTesting(
      repository: repository,
      tileStore: await TileStore.at(tileDirectory),
      mapProvider: _provider,
      publicRasterDevUnlockCompiled: true,
      authorizedViewRasterDevUnlockCompiled: true,
    );
    store.mapTileMode = MapTileMode.offline;
    store.activeMapLayerId = MapProviderConfig.esriWorldImagery.id;
  });

  tearDown(() async {
    store.dispose();
    await database.close();
    await tileDirectory.delete(recursive: true);
  });

  testWidgets(
    'OFF-012: authorized Esri is reachable through the tappable editor picker',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(430, 932);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final area = OfflineArea(
        id: 'editor-area',
        name: 'Authorized imagery',
        bounds: const GeoBounds(north: 1.001, south: 1, east: 1.001, west: 1),
        minZoom: 12,
        maxZoom: 12,
        providerId: MapProviderConfig.esriWorldImagery.id,
        status: OfflineAreaStatus.planned,
        totalTiles: 1,
        completedTiles: 0,
        actualBytes: 0,
        createdAt: DateTime.utc(2026, 9, 22),
        updatedAt: DateTime.utc(2026, 9, 22),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: OfflineAreaEditor(store: store, area: area),
        ),
      );
      final currentMap = find.byKey(
        const ValueKey('download-source-current-map'),
      );
      await tester.ensureVisible(currentMap);
      expect(tester.widget<ChoiceChip>(currentMap).onSelected, isNotNull);
      for (var tap = 0; tap < 7; tap++) {
        await tester.tap(currentMap);
        await tester.pump(const Duration(milliseconds: 30));
      }
      await tester.pumpAndSettle();

      expect(find.text('Enable developer raster downloads?'), findsOneWidget);
      expect(store.publicRasterDevDownloadsUnlocked, isFalse);
      await tester.tap(find.text('Enable DEV downloads'));
      await tester.pumpAndSettle();

      expect(store.publicRasterDevDownloadsUnlocked, isTrue);
      expect(
        repository.settings['public_raster_dev_downloads_unlocked'],
        'true',
      );
      expect(find.text('Current map: Satellite \u00b7 DEV'), findsOneWidget);
      expect(
        store
            .mapProviderById(MapProviderConfig.esriWorldImagery.id)!
            .downloadPolicy,
        same(RasterDownloadPolicy.development),
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Review & update'),
            )
            .onPressed,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
