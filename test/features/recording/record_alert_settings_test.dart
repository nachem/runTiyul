import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:trail_runner/app/app_store.dart';
import 'package:trail_runner/data/app_database.dart';
import 'package:trail_runner/data/app_repository.dart';
import 'package:trail_runner/features/map/trail_map.dart';
import 'package:trail_runner/features/recording/record_screen.dart';
import 'package:trail_runner/models/run_activity.dart';
import 'package:trail_runner/models/trail_route.dart';
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
      haptic: (_) async {},
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
    expect(
      find.byKey(const ValueKey('test-recovery-guidance')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('test-progress-guidance')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('nav-feedback-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Voice').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('test-junction-alert')));
    await tester.pump();

    expect(tones, isEmpty);
    expect(messages, ['In 25 meters, turn left 90 degrees.']);
    expect(
      tester
          .state<FormFieldState<NavFeedbackMode>>(
            find.byKey(const ValueKey('nav-feedback-mode')),
          )
          .value,
      NavFeedbackMode.voice,
    );
  });

  testWidgets('NAV-011 runner can choose and cancel a route-point return', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1200);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final now = DateTime.utc(2026, 9, 28, 8);
    final route = TrailRoute(
      id: 'route',
      name: 'Route',
      source: RouteSource.manual,
      createdAt: now,
      updatedAt: now,
      points: const [
        RoutePoint(latitude: 31.8, longitude: 35.2),
        RoutePoint(latitude: 31.8, longitude: 35.204),
      ],
    );
    await tester.runAsync(() async {
      await repository.saveRoute(route);
      await repository.createActivity(
        RunActivity(
          id: 'activity',
          routeId: route.id,
          status: ActivityStatus.paused,
          startedAt: now,
          elapsed: const Duration(minutes: 5),
          distanceMeters: 0,
          elevationGainMeters: 0,
          samples: const [],
        ),
      );
    });
    final store = await tester.runAsync(
      () => AppStore.forTesting(
        repository: repository,
        tileStore: tileStore,
        mapProvider: _config,
      ),
    );
    if (store == null) fail('AppStore setup did not complete');
    addTearDown(store.dispose);
    store
      ..mapTileMode = MapTileMode.offline
      ..currentLocation = const LatLng(31.8, 35.2);
    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedBuilder(
          animation: store,
          builder: (context, _) => RecordScreen(store: store),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('navigate-back-action')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Home / start'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('choose-back-route-point')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('choose-back-route-point')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Tap a point on the active route'), findsOneWidget);
    final map = tester.widget<TrailMap>(find.byType(TrailMap));
    map.onTap!(const LatLng(31.8, 35.202));
    await tester.pump();

    expect(store.navigatingBack, isTrue);
    expect(
      find.textContaining('Navigating to Selected route point'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('navigation-destination-marker')),
      findsOneWidget,
    );
    await tester.tap(find.text('Resume route'));
    await tester.pump();
    expect(store.navigatingBack, isFalse);
    expect(
      find.byKey(const ValueKey('navigation-destination-marker')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}
