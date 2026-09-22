import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:trail_runner/app/app_store.dart';
import 'package:trail_runner/data/app_database.dart';
import 'package:trail_runner/data/app_repository.dart';
import 'package:trail_runner/features/map/trail_map.dart';
import 'package:trail_runner/features/recording/record_screen.dart';
import 'package:trail_runner/features/routes/routes_screen.dart';
import 'package:trail_runner/core/geo/geo_bounds.dart';
import 'package:trail_runner/models/run_activity.dart';
import 'package:trail_runner/models/map_tracking.dart';
import 'package:trail_runner/models/trail_route.dart';
import 'package:trail_runner/services/map_provider.dart';
import 'package:trail_runner/services/location_service.dart';
import 'package:trail_runner/services/navigation_monitor.dart';
import 'package:trail_runner/services/tile_store.dart';
import 'package:trail_runner/services/route_trail_builder.dart';
import 'package:trail_runner/services/trail_network.dart';

class _OverlayBuilder extends RouteTrailBuilder {
  final permissions = <bool>[];
  @override
  Future<TrailNetwork> networkForBounds(
    GeoBounds bounds,
    String sourceUrl, {
    bool allowNetwork = true,
    bool Function()? isCancelled,
  }) async {
    permissions.add(allowNetwork);
    return const TrailNetwork([
      TrailPolyline(
        points: [LatLng(31.77, 35.20), LatLng(31.77, 35.21)],
        kind: 'path',
      ),
    ]);
  }
}

class _CurrentLocationService extends LocationService {
  const _CurrentLocationService();

  @override
  Future<Position> current() async => Position(
    latitude: 31.8,
    longitude: 35.2,
    timestamp: DateTime.utc(2026, 9, 22),
    accuracy: 3,
    altitude: 0,
    altitudeAccuracy: 3,
    heading: 90,
    headingAccuracy: 5,
    speed: 3,
    speedAccuracy: 0.2,
  );
}

class _DeferredLocationService extends LocationService {
  final requests = <Completer<Position>>[];

  @override
  Future<Position> current() {
    final request = Completer<Position>();
    requests.add(request);
    return request.future;
  }
}

const _provider = MapProviderConfig(
  id: 'test',
  urlTemplate: 'https://example.invalid/{z}/{x}/{y}.png',
  attribution: 'Test',
  offlineDownloadsAllowed: false,
  isDevelopmentOsmOverride: false,
);

TrailRoute _route(String id, double latitude) {
  final now = DateTime.utc(2026, 7, 18);
  return TrailRoute(
    id: id,
    name: 'Route $id',
    source: RouteSource.manual,
    createdAt: now,
    updatedAt: now,
    points: [
      RoutePoint(latitude: latitude, longitude: 35.20),
      RoutePoint(latitude: latitude, longitude: 35.21),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late Directory tileDirectory;
  late AppStore store;

  setUp(() async {
    sqfliteFfiInit();
    database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    tileDirectory = await Directory.systemTemp.createTemp(
      'route_map_regression',
    );
    store = await AppStore.forTesting(
      repository: AppRepository(database),
      tileStore: await TileStore.at(tileDirectory),
      mapProvider: _provider,
      locationService: const _CurrentLocationService(),
    );
    await store.setMapTileMode(MapTileMode.offline);
  });

  tearDown(() async {
    store.dispose();
    await database.close();
    await tileDirectory.delete(recursive: true);
  });

  Future<_DeferredLocationService> pumpPendingLocationMap(
    WidgetTester tester, {
    double? initialZoom = 16.25,
  }) async {
    final locations = _DeferredLocationService();
    final pendingStore = (await tester.runAsync(
      () => AppStore.forTesting(
        repository: AppRepository(database),
        tileStore: store.tileStore,
        mapProvider: _provider,
        locationService: locations,
      ),
    ))!;
    addTearDown(pendingStore.dispose);
    pendingStore.mapTileMode = MapTileMode.offline;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnimatedBuilder(
            animation: pendingStore,
            builder: (context, _) => TrailMap(
              store: pendingStore,
              initialZoom: initialZoom,
              autoFit: true,
              showControls: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return locations;
  }

  testWidgets(
    'RTE-003 dense editor preserves geometry and exposes sparse clickable controls',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final now = DateTime.utc(2026, 9, 6);
      final points = [
        for (var index = 0; index < 1000; index++)
          RoutePoint(latitude: 31.77, longitude: 35.2 + index * 0.00001),
      ];
      final route = TrailRoute(
        id: 'dense',
        name: 'Dense',
        source: RouteSource.gpx,
        createdAt: now,
        updatedAt: now,
        points: points,
      );
      store.vectorSourceUrl = 'https://example.invalid/planet';
      await tester.pumpWidget(
        MaterialApp(
          home: ManualRouteEditor(store: store, initialRoute: route),
        ),
      );
      await tester.pumpAndSettle();
      TrailMap map() => tester.widget<TrailMap>(find.byType(TrailMap));
      expect(map().waypoints.length, 1000);
      expect(map().waypointMarkers, hasLength(2));
      expect(find.text('2 controls'), findsOneWidget);
      await tester.tap(find.text('Checkpoints'));
      await tester.pumpAndSettle();
      expect(map().waypoints.length, 1000);
      await tester.tap(find.text('Follow trails'));
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(map().waypoints.length, 1000);
      expect(map().waypointMarkers, hasLength(2));
      map().onWaypointTap!(0);
      await tester.pump();
      expect(find.text('Move'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('MAP-013 vector toggle renders cached ways and hides below z14', (
    tester,
  ) async {
    final builder = _OverlayBuilder();
    final overlayStore = (await tester.runAsync(
      () => AppStore.forTesting(
        repository: AppRepository(database),
        tileStore: store.tileStore,
        mapProvider: _provider,
        routeTrailBuilder: builder,
      ),
    ))!;
    addTearDown(overlayStore.dispose);
    overlayStore.vectorSourceUrl = 'https://example.invalid/planet';
    overlayStore.mapTileMode = MapTileMode.offline;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TrailMap(
            store: overlayStore,
            initialCenter: const LatLng(31.77, 35.205),
            initialZoom: 15,
            showControls: true,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Show vector roads and trails'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    expect(builder.permissions, [false]);
    expect(find.byKey(const ValueKey('vector-way-overlay')), findsOneWidget);
    await tester.tap(find.byTooltip('Zoom out'));
    await tester.pump();
    await tester.tap(find.byTooltip('Zoom out'));
    await tester.pump();
    expect(find.byKey(const ValueKey('vector-way-overlay')), findsNothing);
    expect(find.text('Vector ways hidden at this zoom'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saved-trail toggle never hides the active navigation route', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final active = _route('active', 31.77);
    final saved = _route('saved', 31.78);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TrailMap(
            store: store,
            route: active,
            routes: [active, saved],
            showControls: true,
          ),
        ),
      ),
    );
    await tester.pump();

    List<Polyline<Object>> visiblePolylines() => tester
        .widgetList<PolylineLayer>(find.byType(PolylineLayer))
        .expand((layer) => layer.polylines)
        .toList();

    expect(
      visiblePolylines().where((line) => line.color == Colors.deepOrange),
      hasLength(1),
    );
    expect(
      visiblePolylines().where((line) => line.strokeWidth == 3),
      hasLength(1),
    );

    await tester.tap(find.byTooltip('Hide saved trails'));
    await tester.pump();

    expect(
      visiblePolylines().where((line) => line.color == Colors.deepOrange),
      hasLength(1),
    );
    expect(visiblePolylines().where((line) => line.strokeWidth == 3), isEmpty);

    await tester.tap(find.byTooltip('Show saved trails'));
    await tester.pump();
    expect(
      visiblePolylines().where((line) => line.strokeWidth == 3),
      hasLength(1),
    );
  });

  testWidgets('realtime recording supplies every saved route to the map', (
    tester,
  ) async {
    final active = _route('active', 31.77);
    final saved = _route('saved', 31.78);
    store.routes = [active, saved];
    store.activeActivity = RunActivity(
      id: 'activity',
      routeId: active.id,
      status: ActivityStatus.recording,
      startedAt: DateTime.utc(2026, 7, 18),
      elapsed: Duration.zero,
      distanceMeters: 0,
      elevationGainMeters: 0,
      samples: const [],
    );

    await tester.pumpWidget(MaterialApp(home: RecordScreen(store: store)));

    final map = tester.widget<TrailMap>(find.byType(TrailMap));
    expect(map.route?.id, active.id);
    expect(map.routes.map((route) => route.id), ['active', 'saved']);
    expect(map.followCurrentLocation, isTrue);
    expect(map.orientationMode, MapOrientationMode.courseUp);
  });

  for (final showRoute in [false, true]) {
    testWidgets(
      'MAP-008 center view keeps zoom with ${showRoute ? 'a route' : 'location only'}',
      (tester) async {
        store.currentLocation = const LatLng(31.8, 35.205);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TrailMap(
                store: store,
                route: showRoute ? _route('view', 31.8) : null,
                initialCenter: const LatLng(31.7, 35.1),
                initialZoom: 17.25,
                showControls: true,
                followCurrentLocation: false,
                orientationMode: MapOrientationMode.courseUp,
                courseDegrees: 90,
                onFollowCurrentLocationChanged: (_) {},
                onOrientationModeChanged: (_) {},
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.tap(
          find.widgetWithIcon(IconButton, Icons.center_focus_strong),
        );
        await tester.pumpAndSettle();
        final camera = MapCamera.of(
          tester.element(find.byType(RichAttributionWidget)),
        );
        expect(camera.zoom, 17.25);
        expect(camera.rotation, closeTo(270, 0.001));
        expect(camera.center.latitude, closeTo(31.8, 0.000001));
        expect(camera.center.longitude, closeTo(35.205, 0.000001));
      },
    );
  }

  for (final autoFit in [false, true]) {
    testWidgets(
      'MAP-008 ${autoFit ? 'automatic preview' : 'explicit Fit'} still frames the route',
      (tester) async {
        final route = _route('fit', 31.8);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TrailMap(
                store: store,
                route: route,
                initialCenter: const LatLng(31.7, 35.1),
                initialZoom: 17.25,
                autoFit: autoFit,
                showControls: true,
              ),
            ),
          ),
        );
        await tester.pump();
        if (!autoFit) {
          await tester.tap(
            find.byTooltip('Fit route and content (adjust zoom)'),
          );
        }
        await tester.pumpAndSettle();
        final camera = MapCamera.of(
          tester.element(find.byType(RichAttributionWidget)),
        );
        expect(camera.zoom, lessThan(17.25));
        for (final point in route.points) {
          expect(camera.visibleBounds.contains(point.latLng), isTrue);
        }
      },
    );
  }

  testWidgets('MAP-008 center view preserves zoom for a selected area', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TrailMap(
            store: store,
            selection: const GeoBounds(
              north: 31.81,
              south: 31.8,
              east: 35.22,
              west: 35.2,
            ),
            initialCenter: const LatLng(31.7, 35.1),
            initialZoom: 17.25,
            showControls: true,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Center view (keep zoom)'));
    await tester.pumpAndSettle();
    final camera = MapCamera.of(
      tester.element(find.byType(RichAttributionWidget)),
    );
    expect(camera.zoom, 17.25);
    expect(camera.center.latitude, closeTo(31.805, 0.000001));
    expect(camera.center.longitude, closeTo(35.21, 0.000001));
  });

  testWidgets('NAV-005 course-up and GPS recenter preserve the manual zoom', (
    tester,
  ) async {
    store.currentLocation = const LatLng(31.7, 35.1);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TrailMap(
            store: store,
            initialCenter: const LatLng(31.7, 35.1),
            initialZoom: 16.25,
            showControls: true,
            followCurrentLocation: true,
            orientationMode: MapOrientationMode.courseUp,
            courseDegrees: 90,
            onFollowCurrentLocationChanged: (_) {},
            onOrientationModeChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    MapCamera camera() =>
        MapCamera.of(tester.element(find.byType(RichAttributionWidget)));
    expect(camera().rotation, closeTo(270, 0.001));
    expect(camera().zoom, 16.25);

    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pump();
    expect(camera().zoom, 17.25);

    await tester.tap(find.byTooltip('Center on current location'));
    await tester.pumpAndSettle();
    expect(camera().center.latitude, closeTo(31.8, 0.000001));
    expect(camera().center.longitude, closeTo(35.2, 0.000001));
    expect(camera().zoom, 17.25);
    expect(camera().rotation, closeTo(270, 0.001));
  });

  for (final startupFinishesFirst in [true, false]) {
    testWidgets(
      'MAP-008 startup fix finishing ${startupFinishesFirst ? 'before' : 'after'} '
      'recenter preserves manual zoom',
      (tester) async {
        final locations = await pumpPendingLocationMap(tester);
        expect(locations.requests, hasLength(1));
        MapCamera camera() =>
            MapCamera.of(tester.element(find.byType(RichAttributionWidget)));
        expect(camera().zoom, 16.25);

        await tester.tap(find.byTooltip('Center on current location'));
        await tester.pump();
        expect(locations.requests, hasLength(2));
        final fix = await const _CurrentLocationService().current();
        if (startupFinishesFirst) {
          locations.requests[0].complete(fix);
          await tester.pumpAndSettle();
          expect(camera().zoom, 16.25);
        }

        await tester.tap(find.byTooltip('Zoom in'));
        await tester.pump();
        expect(camera().zoom, 17.25);
        locations.requests[1].complete(fix);
        await tester.pumpAndSettle();
        expect(camera().center, const LatLng(31.8, 35.2));
        expect(camera().zoom, 17.25);

        if (!startupFinishesFirst) {
          locations.requests[0].complete(fix);
          await tester.pumpAndSettle();
          expect(camera().center, const LatLng(31.8, 35.2));
          expect(camera().zoom, 17.25);
        }
      },
    );
  }

  for (final control in [
    'Zoom in',
    'Zoom out',
    'Center view (keep zoom)',
    'Fit route and content (adjust zoom)',
  ]) {
    testWidgets('MAP-008 $control cancels pending startup centering', (
      tester,
    ) async {
      final locations = await pumpPendingLocationMap(tester);
      MapCamera camera() =>
          MapCamera.of(tester.element(find.byType(RichAttributionWidget)));
      final center = camera().center;
      final expectedZoom = switch (control) {
        'Zoom in' => 17.25,
        'Zoom out' => 15.25,
        _ => 16.25,
      };
      await tester.tap(find.byTooltip(control));
      await tester.pump();
      expect(camera().zoom, expectedZoom);

      locations.requests.single.complete(
        await const _CurrentLocationService().current(),
      );
      await tester.pumpAndSettle();
      expect(camera().center, center);
      expect(camera().zoom, expectedZoom);
    });
  }

  testWidgets('MAP-008 untouched startup still centers at neighborhood zoom', (
    tester,
  ) async {
    final locations = await pumpPendingLocationMap(tester, initialZoom: null);
    locations.requests.single.complete(
      await const _CurrentLocationService().current(),
    );
    await tester.pumpAndSettle();
    final camera = MapCamera.of(
      tester.element(find.byType(RichAttributionWidget)),
    );
    expect(camera.center, const LatLng(31.8, 35.2));
    expect(camera.zoom, 15);
  });

  testWidgets('recording banner shows precise apex and consecutive turn', (
    tester,
  ) async {
    store.activeActivity = RunActivity(
      id: 'activity',
      status: ActivityStatus.recording,
      startedAt: DateTime.utc(2026, 8, 19),
      elapsed: Duration.zero,
      distanceMeters: 0,
      elevationGainMeters: 0,
      samples: const [],
    );
    store.navStatus = const NavStatus(
      offRoute: false,
      junctionAhead: LatLng(31.77, 35.21),
      junctionDistanceMeters: 0,
      junctionTurn: TurnDirection.right,
      junctionTurnDegrees: 90,
      maneuverPhase: ManeuverPhase.apex,
      followingTurnDegrees: -45,
    );

    await tester.pumpWidget(MaterialApp(home: RecordScreen(store: store)));

    expect(
      find.text(
        'Now \u2022 turn right 90 degrees '
        '\u2022 then immediately bear left 45 degrees',
      ),
      findsOneWidget,
    );
  });

  testWidgets('recording renders and describes only forward recovery', (
    tester,
  ) async {
    store.activeActivity = RunActivity(
      id: 'activity',
      status: ActivityStatus.recording,
      startedAt: DateTime.utc(2026, 8, 19),
      elapsed: Duration.zero,
      distanceMeters: 0,
      elevationGainMeters: 0,
      samples: const [],
    );
    store.navStatus = const NavStatus(
      offRoute: true,
      distanceToRouteMeters: 80,
      routeRelativeDirection: RouteRelativeDirection.behind,
      forwardRecoveryPath: [LatLng(31.77, 35.21), LatLng(31.77, 35.212)],
      forwardRecoveryDistanceMeters: 230,
      forwardRecoveryBearingDegrees: 90,
    );

    await tester.pumpWidget(MaterialApp(home: RecordScreen(store: store)));

    final map = tester.widget<TrailMap>(find.byType(TrailMap));
    expect(map.recoveryPath, hasLength(2));
    expect(
      find.text(
        'Off route \u2022 80 m from plan \u2022 follow mapped path E '
        '\u2022 230 m to rejoin',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('behind'), findsNothing);
  });

  testWidgets('route view and editor reserve the bottom safe area', (
    tester,
  ) async {
    final route = _route('active', 31.77);
    store.routes = [route];

    await tester.pumpWidget(
      MaterialApp(
        home: RouteDetailScreen(store: store, route: route, onStart: () {}),
      ),
    );
    expect(
      find.byKey(const ValueKey('route-detail-safe-area')),
      findsOneWidget,
    );
    expect(find.text('Snap to trails'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: ManualRouteEditor(store: store, initialRoute: route),
      ),
    );
    expect(
      find.byKey(const ValueKey('route-editor-safe-area')),
      findsOneWidget,
    );
  });
}
