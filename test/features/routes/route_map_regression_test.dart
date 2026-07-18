import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:trail_runner/app/app_store.dart';
import 'package:trail_runner/data/app_database.dart';
import 'package:trail_runner/data/app_repository.dart';
import 'package:trail_runner/features/map/trail_map.dart';
import 'package:trail_runner/features/recording/record_screen.dart';
import 'package:trail_runner/features/routes/routes_screen.dart';
import 'package:trail_runner/models/run_activity.dart';
import 'package:trail_runner/models/trail_route.dart';
import 'package:trail_runner/services/map_provider.dart';
import 'package:trail_runner/services/tile_store.dart';

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
    );
    await store.setMapTileMode(MapTileMode.offline);
  });

  tearDown(() async {
    store.dispose();
    await database.close();
    await tileDirectory.delete(recursive: true);
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
