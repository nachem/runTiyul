import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:trail_runner/app/app_store.dart';
import 'package:trail_runner/data/app_database.dart';
import 'package:trail_runner/data/app_repository.dart';
import 'package:trail_runner/features/recording/record_screen.dart';
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
    tileDir = await Directory.systemTemp.createTemp('record_alert_settings');
    tileStore = await TileStore.at(tileDir);
  });

  tearDown(() async {
    await database.close();
    await tileDir.delete(recursive: true);
  });

  testWidgets('runner can select and preview voice guidance', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
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
    final store = await tester.runAsync(
      () => AppStore.forTesting(
        repository: repository,
        tileStore: tileStore,
        mapProvider: _config,
        navigationAlertFeedback: feedback,
      ),
    );
    if (store == null) fail('AppStore setup did not complete');
    addTearDown(store.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AlertSettingsSheet(store: store)),
      ),
    );

    expect(find.text('Alert output'), findsOneWidget);
    expect(find.byKey(const ValueKey('test-off-route-alert')), findsOneWidget);
    expect(find.byKey(const ValueKey('test-junction-alert')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nav-feedback-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Voice').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('test-junction-alert')));
    await tester.pump();

    expect(tones, isEmpty);
    expect(messages, ['In 25 meters, keep left.']);
    expect(
      tester
          .state<FormFieldState<NavFeedbackMode>>(
            find.byKey(const ValueKey('nav-feedback-mode')),
          )
          .value,
      NavFeedbackMode.voice,
    );
  });
}
