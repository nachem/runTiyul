import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trail_runner/features/offline_maps/offline_maps_screen.dart';
import 'package:trail_runner/models/offline_area.dart';
import 'package:trail_runner/services/map_provider.dart';

const _devStreets = MapProviderConfig(
  id: 'openstreetmap-standard',
  label: 'Streets',
  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  attribution: 'OpenStreetMap contributors',
  offlineDownloadsAllowed: true,
  isDevelopmentOsmOverride: true,
);

void main() {
  testWidgets('always shows MBTiles and current-map choices', (tester) async {
    OfflineSourceFormat? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OfflineDownloadSourcePicker(
            vectorAvailable: true,
            activeMapLayer: _devStreets,
            currentMapDownloadAllowed: true,
            selectedFormat: OfflineSourceFormat.convertedVector,
            onSelected: (format) => selected = format,
          ),
        ),
      ),
    );

    expect(find.text('MBTiles / vector'), findsOneWidget);
    expect(find.text('Current map: Streets \u00b7 DEV'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('download-source-current-map')));
    expect(selected, OfflineSourceFormat.rasterTiles);
  });

  testWidgets('keeps unavailable modes visible but disabled', (tester) async {
    var lockedTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OfflineDownloadSourcePicker(
            vectorAvailable: false,
            activeMapLayer: MapProviderConfig.esriWorldImagery,
            currentMapDownloadAllowed: false,
            selectedFormat: OfflineSourceFormat.rasterTiles,
            onSelected: (_) {},
            onLockedCurrentMapTap: () => lockedTaps++,
          ),
        ),
      ),
    );

    expect(find.text('MBTiles / vector'), findsOneWidget);
    expect(find.text('Current map: Satellite'), findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('download-source-vector')),
          )
          .onSelected,
      isNull,
    );
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('download-source-current-map')),
          )
          .onSelected,
      isNull,
    );

    await tester.tap(find.byKey(const ValueKey('download-source-current-map')));
    expect(lockedTaps, 1);
  });
}
