import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:trail_runner/app/app_store.dart';
import 'package:trail_runner/data/app_database.dart';
import 'package:trail_runner/data/app_repository.dart';
import 'package:trail_runner/services/map_provider.dart';
import 'package:trail_runner/services/navigation_alert_feedback.dart';
import 'package:trail_runner/services/navigation_monitor.dart';
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
    tileDir = await Directory.systemTemp.createTemp('nav_settings');
    tileStore = await TileStore.at(tileDir);
  });

  tearDown(() async {
    await database.close();
    await tileDir.delete(recursive: true);
  });

  Future<AppStore> openStore({NavigationAlertFeedback? feedback}) =>
      AppStore.forTesting(
        repository: repository,
        tileStore: tileStore,
        mapProvider: _config,
        navigationAlertFeedback: feedback,
      );

  test(
    'snap-to-trails setting defaults on and persists when toggled off',
    () async {
      final store = await openStore();
      expect(store.snapRoutesToTrails, isTrue);

      await store.setSnapRoutesToTrails(false);
      expect(store.snapRoutesToTrails, isFalse);

      final reloaded = await openStore();
      expect(reloaded.snapRoutesToTrails, isFalse);
    },
  );

  test('navigation alert configuration persists', () async {
    final store = await openStore();

    await store.setNavAlertConfig(
      const NavAlertConfig(
        offRouteEnabled: false,
        offRouteMeters: 55,
        offRoutePersistence: 5,
        junctionEnabled: false,
        junctionMeters: 40,
        feedbackMode: NavFeedbackMode.voice,
      ),
    );

    final reloaded = await openStore();
    final config = reloaded.navAlertConfig;
    expect(config.offRouteEnabled, isFalse);
    expect(config.offRouteMeters, 55);
    expect(config.offRoutePersistence, 5);
    expect(config.junctionEnabled, isFalse);
    expect(config.junctionMeters, 40);
    expect(config.feedbackMode, NavFeedbackMode.voice);
  });

  test(
    'preview uses the unsaved output mode and representative guidance',
    () async {
      final tones = <NavAlert>[];
      final messages = <String>[];
      final feedback = NavigationAlertFeedback(
        haptic: () async {},
        playTone: (alert) async {
          tones.add(alert);
          return true;
        },
        speak: (message) async {
          messages.add(message);
          return true;
        },
      );
      final store = await openStore(feedback: feedback);

      await store.previewNavigationAlert(
        NavAlert.junction,
        config: const NavAlertConfig(
          junctionMeters: 35,
          feedbackMode: NavFeedbackMode.voice,
        ),
      );

      expect(tones, isEmpty);
      expect(messages, ['In 35 meters, keep left.']);
    },
  );
}
