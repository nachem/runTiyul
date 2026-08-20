import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:trail_runner/app/app_store.dart';
import 'package:trail_runner/data/app_database.dart';
import 'package:trail_runner/data/app_repository.dart';
import 'package:trail_runner/models/map_tracking.dart';
import 'package:trail_runner/models/trail_route.dart';
import 'package:trail_runner/services/map_provider.dart';
import 'package:trail_runner/services/navigation_alert_feedback.dart';
import 'package:trail_runner/services/navigation_monitor.dart';
import 'package:trail_runner/services/route_trail_builder.dart';
import 'package:trail_runner/services/tile_store.dart';
import 'package:trail_runner/services/trail_network.dart';

const _config = MapProviderConfig(
  id: 'test',
  urlTemplate: 'https://example.invalid/{z}/{x}/{y}.png',
  attribution: 'Test',
  offlineDownloadsAllowed: false,
  isDevelopmentOsmOverride: false,
);

const _vectorConfig = MapProviderConfig(
  id: 'test',
  urlTemplate: 'https://example.invalid/{z}/{x}/{y}.png',
  attribution: 'Test',
  offlineDownloadsAllowed: false,
  isDevelopmentOsmOverride: false,
  vectorSourceUrl: 'https://example.invalid/vector/{z}/{x}/{y}.pbf',
);

class _FakeRouteTrailBuilder extends RouteTrailBuilder {
  List<LatLng>? receivedRoute;

  @override
  Future<RouteTrailResult> snapToTrails(
    List<LatLng> route,
    String sourceUrl,
  ) async {
    receivedRoute = route;
    return const RouteTrailResult(
      snapped: [LatLng(0, 0), LatLng(0, 0.002)],
      network: TrailNetwork([]),
      changed: true,
    );
  }
}

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

  Future<AppStore> openStore({
    NavigationAlertFeedback? feedback,
    MapProviderConfig config = _config,
    RouteTrailBuilder? routeTrailBuilder,
  }) => AppStore.forTesting(
    repository: repository,
    tileStore: tileStore,
    mapProvider: config,
    navigationAlertFeedback: feedback,
    routeTrailBuilder: routeTrailBuilder,
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

  test('recording map tracking settings default on and persist', () async {
    final store = await openStore();
    expect(store.recordingMapFollow, isTrue);
    expect(store.recordingMapOrientation, MapOrientationMode.courseUp);

    await store.setRecordingMapFollow(false);
    await store.setRecordingMapOrientation(MapOrientationMode.northUp);

    final reloaded = await openStore();
    expect(reloaded.recordingMapFollow, isFalse);
    expect(reloaded.recordingMapOrientation, MapOrientationMode.northUp);
  });

  test(
    'whole-route snap cleans artifacts and persists imported geometry',
    () async {
      final now = DateTime.utc(2026, 8, 19);
      final route = TrailRoute(
        id: 'imported',
        name: 'Imported route',
        source: RouteSource.gpx,
        createdAt: now,
        updatedAt: now,
        points: const [
          RoutePoint(latitude: 0, longitude: 0, elevation: 42),
          RoutePoint(latitude: 0, longitude: 0.0001),
          RoutePoint(latitude: 0.000005, longitude: 0),
          RoutePoint(latitude: 0, longitude: 0.001),
        ],
      );
      await repository.saveRoute(route);
      final builder = _FakeRouteTrailBuilder();
      final store = await openStore(
        config: _vectorConfig,
        routeTrailBuilder: builder,
      );

      final outcome = await store.snapRouteToTrails(store.routes.single);

      expect(outcome, RouteSnapOutcome.updated);
      expect(builder.receivedRoute, [
        const LatLng(0, 0),
        const LatLng(0, 0.001),
      ]);
      final persisted = (await repository.loadRoutes()).single;
      expect(persisted.source, RouteSource.gpx);
      expect(persisted.points.first.elevation, 42);
      expect(persisted.points.map((point) => point.latLng), [
        const LatLng(0, 0),
        const LatLng(0, 0.002),
      ]);
    },
  );

  test(
    'whole-route snap reports unavailable without a vector source',
    () async {
      final store = await openStore();
      final now = DateTime.utc(2026, 8, 19);
      final route = TrailRoute(
        id: 'route',
        name: 'Route',
        source: RouteSource.manual,
        createdAt: now,
        updatedAt: now,
        points: const [
          RoutePoint(latitude: 0, longitude: 0),
          RoutePoint(latitude: 0, longitude: 0.001),
        ],
      );

      expect(
        await store.snapRouteToTrails(route),
        RouteSnapOutcome.unavailable,
      );
    },
  );

  test('navigation alert configuration persists', () async {
    final store = await openStore();

    await store.setNavAlertConfig(
      const NavAlertConfig(
        offRouteEnabled: false,
        offRouteMeters: 55,
        offRoutePersistence: 5,
        offRouteReminderSeconds: 35,
        junctionEnabled: false,
        junctionMeters: 40,
        progressEnabled: true,
        progressIntervalMode: ProgressIntervalMode.time,
        progressDistanceMeters: 2000,
        progressIntervalMinutes: 15,
        feedbackMode: NavFeedbackMode.voice,
      ),
    );

    final reloaded = await openStore();
    final config = reloaded.navAlertConfig;
    expect(config.offRouteEnabled, isFalse);
    expect(config.offRouteMeters, 55);
    expect(config.offRoutePersistence, 5);
    expect(config.offRouteReminderSeconds, 35);
    expect(config.junctionEnabled, isFalse);
    expect(config.junctionMeters, 40);
    expect(config.progressEnabled, isTrue);
    expect(config.progressIntervalMode, ProgressIntervalMode.time);
    expect(config.progressDistanceMeters, 2000);
    expect(config.progressIntervalMinutes, 15);
    expect(config.feedbackMode, NavFeedbackMode.voice);
  });

  test(
    'preview uses the unsaved output mode and representative guidance',
    () async {
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
      final store = await openStore(feedback: feedback);

      await store.previewNavigationAlert(
        NavAlert.junction,
        config: const NavAlertConfig(
          junctionMeters: 35,
          feedbackMode: NavFeedbackMode.voice,
        ),
      );

      expect(tones, isEmpty);
      expect(messages, ['In 35 meters, turn left 90 degrees.']);
    },
  );
}
