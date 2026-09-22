import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:trail_runner/app/app_store.dart';
import 'package:trail_runner/data/app_database.dart';
import 'package:trail_runner/data/app_repository.dart';
import 'package:trail_runner/models/run_activity.dart';
import 'package:trail_runner/models/trail_route.dart';
import 'package:trail_runner/services/location_service.dart';
import 'package:trail_runner/services/map_provider.dart';
import 'package:trail_runner/services/navigation_monitor.dart';
import 'package:trail_runner/services/route_trail_builder.dart';
import 'package:trail_runner/services/tile_store.dart';
import 'package:trail_runner/services/trail_network.dart';

class _Locations extends LocationService {
  final positionsController = StreamController<Position>.broadcast();
  @override
  Future<void> ensurePermission() async {}
  @override
  Stream<Position> positions() => positionsController.stream;
}

class _Repository extends AppRepository {
  _Repository(super.database);
  Completer<void>? saved;
  @override
  Future<void> appendActivitySample(
    RunActivity activity,
    ActivitySample sample,
  ) async {
    await super.appendActivitySample(activity, sample);
    saved?.complete();
  }
}

class _NetworkBuilder extends RouteTrailBuilder {
  final permissions = <bool>[];
  @override
  Future<TrailNetwork> networkNearPoint(
    LatLng point,
    String sourceUrl, {
    bool allowNetwork = true,
  }) async {
    permissions.add(allowNetwork);
    return const TrailNetwork([
      TrailPolyline(
        points: [LatLng(0, 0), LatLng(0, 0.003), LatLng(0, 0.01)],
        kind: 'path',
      ),
      TrailPolyline(
        points: [LatLng(0.001, 0.001), LatLng(0.001, 0.003)],
        kind: 'path',
      ),
      TrailPolyline(
        points: [LatLng(0.001, 0.003), LatLng(0, 0.003)],
        kind: 'path',
      ),
    ]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'NAV-007 recording guides and advances a cached forward recovery',
    () async {
      sqfliteFfiInit();
      final database = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      final repository = _Repository(database);
      final directory = await Directory.systemTemp.createTemp(
        'recording_recovery',
      );
      final locations = _Locations();
      final builder = _NetworkBuilder();
      final now = DateTime.now().toUtc();
      final route = TrailRoute(
        id: 'plan',
        name: 'Plan',
        source: RouteSource.manual,
        createdAt: now,
        updatedAt: now,
        points: const [
          RoutePoint(latitude: 0, longitude: 0),
          RoutePoint(latitude: 0, longitude: 0.01),
        ],
      );
      await repository.saveRoute(route);
      final store = await AppStore.forTesting(
        repository: repository,
        tileStore: await TileStore.at(directory),
        locationService: locations,
        routeTrailBuilder: builder,
        mapProvider: const MapProviderConfig(
          id: 'test',
          urlTemplate: 'https://example.invalid/{z}/{x}/{y}',
          vectorSourceUrl: 'https://example.invalid/planet',
          attribution: 'Test',
          offlineDownloadsAllowed: false,
          isDevelopmentOsmOverride: false,
        ),
      );
      addTearDown(() async {
        store.dispose();
        await locations.positionsController.close();
        await database.close();
        await directory.delete(recursive: true);
      });
      await store.setMapTileMode(MapTileMode.offline);
      await store.setNavAlertConfig(
        const NavAlertConfig(offRoutePersistence: 1, junctionEnabled: false),
      );
      store.selectRoute(store.routes.single);
      await store.startActivity();

      Future<void> fix(
        double latitude,
        double longitude,
        int seconds, {
        double heading = 90,
      }) async {
        repository.saved = Completer<void>();
        locations.positionsController.add(
          Position(
            latitude: latitude,
            longitude: longitude,
            timestamp: now.add(Duration(seconds: seconds)),
            accuracy: 3,
            altitude: 0,
            altitudeAccuracy: 3,
            heading: heading,
            headingAccuracy: 5,
            speed: 3,
            speedAccuracy: 0.2,
          ),
        );
        await repository.saved!.future;
      }

      await fix(0, 0.001, 0);
      final completed = store.navStatus.routeCompletedMeters;
      await fix(0.001, 0.0012, 10);
      expect(store.navStatus.hasForwardRecovery, isTrue);
      expect(store.navStatus.routeCompletedMeters, completed);
      final firstDistance = store.navStatus.forwardRecoveryDistanceMeters!;
      await fix(0.001, 0.002, 12);
      expect(
        store.navStatus.forwardRecoveryPath.first.longitude,
        closeTo(0.002, 0.000001),
      );
      expect(
        store.navStatus.forwardRecoveryDistanceMeters,
        lessThan(firstDistance),
      );
      expect(builder.permissions, [false]);
      await store.pauseActivity();
      await store.resumeActivity();
      await fix(0.001, 0.0021, 14);
      expect(store.navStatus.routeCompletedMeters, completed);
      await store.pauseActivity();
    },
  );

  test('ACT-004 recording accepts a plausible delayed location fix', () async {
    sqfliteFfiInit();
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final repository = _Repository(database);
    final directory = await Directory.systemTemp.createTemp(
      'recording_delayed_fix',
    );
    final locations = _Locations();
    final store = await AppStore.forTesting(
      repository: repository,
      tileStore: await TileStore.at(directory),
      locationService: locations,
      mapProvider: const MapProviderConfig(
        id: 'test',
        urlTemplate: 'https://example.invalid/{z}/{x}/{y}',
        attribution: 'Test',
        offlineDownloadsAllowed: false,
        isDevelopmentOsmOverride: false,
      ),
    );
    addTearDown(() async {
      store.dispose();
      await locations.positionsController.close();
      await database.close();
      await directory.delete(recursive: true);
    });
    await store.startActivity();
    final startedAt = DateTime.utc(2026, 9, 22, 8);

    Future<void> addFix(double longitude, Duration elapsed) async {
      repository.saved = Completer<void>();
      locations.positionsController.add(
        Position(
          latitude: 0,
          longitude: longitude,
          timestamp: startedAt.add(elapsed),
          accuracy: 3,
          altitude: 0,
          altitudeAccuracy: 3,
          heading: 90,
          headingAccuracy: 5,
          speed: 3,
          speedAccuracy: 0.2,
        ),
      );
      await repository.saved!.future;
    }

    await addFix(0, Duration.zero);
    await addFix(0.0027, const Duration(minutes: 2));

    expect(store.activeActivity!.samples, hasLength(2));
    expect(store.activeActivity!.distanceMeters, closeTo(300, 5));
    final persisted = (await repository.loadActivities()).single;
    expect(persisted.samples, hasLength(2));
    expect(persisted.distanceMeters, closeTo(300, 5));
  });

  test('ACT-007 a GPS stream failure pauses the recording', () async {
    sqfliteFfiInit();
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final repository = _Repository(database);
    final directory = await Directory.systemTemp.createTemp(
      'recording_stream_error',
    );
    final locations = _Locations();
    final store = await AppStore.forTesting(
      repository: repository,
      tileStore: await TileStore.at(directory),
      locationService: locations,
      mapProvider: const MapProviderConfig(
        id: 'test',
        urlTemplate: 'https://example.invalid/{z}/{x}/{y}',
        attribution: 'Test',
        offlineDownloadsAllowed: false,
        isDevelopmentOsmOverride: false,
      ),
    );
    addTearDown(() async {
      store.dispose();
      await locations.positionsController.close();
      await database.close();
      await directory.delete(recursive: true);
    });
    await store.startActivity();
    final paused = Completer<void>();
    void observePausedState() {
      if (store.activeActivity?.status == ActivityStatus.paused &&
          store.errorMessage != null &&
          !paused.isCompleted) {
        paused.complete();
      }
    }

    store.addListener(observePausedState);
    addTearDown(() => store.removeListener(observePausedState));

    locations.positionsController.addError(StateError('location unavailable'));
    await paused.future;

    expect(store.activeActivity!.status, ActivityStatus.paused);
    expect(store.errorMessage, contains('Recording was paused'));
    expect(
      (await repository.loadActivities()).single.status,
      ActivityStatus.paused,
    );
  });
}
