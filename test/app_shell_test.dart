import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trail_runner/app/app.dart';
import 'package:trail_runner/features/map/trail_map.dart';
import 'package:trail_runner/services/map_provider.dart';
import 'package:trail_runner/services/tile_store.dart';

const _streetsLayer = MapProviderConfig(
  id: 'streets',
  label: 'Streets',
  urlTemplate: 'https://example.invalid/{z}/{x}/{y}.png',
  attribution: 'Streets contributors',
  offlineDownloadsAllowed: false,
  isDevelopmentOsmOverride: false,
);

void main() {
  testWidgets('navigation bar exposes every primary feature', (tester) async {
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: TrailNavigationBar(
            selectedIndex: selected,
            onDestinationSelected: (value) => selected = value,
          ),
        ),
      ),
    );

    expect(find.text('Map'), findsOneWidget);
    expect(find.text('Routes'), findsOneWidget);
    expect(find.text('Record'), findsOneWidget);
    expect(find.text('Activities'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);

    await tester.tap(find.text('Offline'));
    expect(selected, 4);
  });

  testWidgets('map controls expose source, zoom, fit, and location actions', (
    tester,
  ) async {
    var zoomedIn = false;
    var zoomedOut = false;
    var fitted = false;
    var located = false;
    MapTileMode? selectedMode;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: TrailMapControls(
              mode: MapTileMode.auto,
              layers: const [],
              activeLayerId: '',
              onLayerSelected: (_) {},
              offlineAvailable: false,
              trailsVisible: true,
              onToggleTrails: () {},
              onModeSelected: (mode) => selectedMode = mode,
              onZoomIn: () => zoomedIn = true,
              onZoomOut: () => zoomedOut = true,
              onFitContent: () => fitted = true,
              onCurrentLocation: () => located = true,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Zoom in'));
    await tester.tap(find.byTooltip('Zoom out'));
    await tester.tap(find.byTooltip('Fit current location and checkpoints'));
    await tester.tap(find.byTooltip('Center on current location'));
    expect((zoomedIn, zoomedOut, fitted, located), (true, true, true, true));

    await tester.tap(find.byTooltip('Map source: Auto'));
    await tester.pumpAndSettle();
    expect(find.text('Downloaded tiles first, then online'), findsOneWidget);
    expect(find.text('Find and browse downloaded map areas'), findsOneWidget);
    await tester.tap(find.text('Offline'));
    await tester.pumpAndSettle();
    expect(selectedMode, MapTileMode.offline);
  });

  testWidgets('offline map controls disable unavailable zoom directions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TrailMapControls(
              mode: MapTileMode.offline,
              layers: const [],
              activeLayerId: '',
              onLayerSelected: (_) {},
              offlineAvailable: true,
              trailsVisible: true,
              onToggleTrails: () {},
              onModeSelected: (_) {},
              onZoomIn: null,
              onZoomOut: null,
              onFitContent: () {},
              onCurrentLocation: () {},
            ),
          ),
        ),
      ),
    );

    expect(
      tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.add))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.remove))
          .onPressed,
      isNull,
    );
  });

  testWidgets('base layer picker switches the active online layer', (
    tester,
  ) async {
    String? selectedLayer;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: TrailMapControls(
              mode: MapTileMode.auto,
              layers: const [_streetsLayer, MapProviderConfig.esriWorldImagery],
              activeLayerId: 'streets',
              onLayerSelected: (id) => selectedLayer = id,
              offlineAvailable: false,
              trailsVisible: true,
              onToggleTrails: () {},
              onModeSelected: (_) {},
              onZoomIn: () {},
              onZoomOut: () {},
              onFitContent: () {},
              onCurrentLocation: () {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Base map: Streets'));
    await tester.pumpAndSettle();
    expect(find.text('Satellite'), findsOneWidget);
    await tester.tap(find.text('Satellite'));
    await tester.pumpAndSettle();
    expect(selectedLayer, 'esri-world-imagery');
  });
}
