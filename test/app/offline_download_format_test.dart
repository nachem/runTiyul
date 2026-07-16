import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:trail_runner/app/app_store.dart';
import 'package:trail_runner/core/geo/geo_bounds.dart';
import 'package:trail_runner/data/app_database.dart';
import 'package:trail_runner/data/app_repository.dart';
import 'package:trail_runner/models/offline_area.dart';
import 'package:trail_runner/services/map_provider.dart';
import 'package:trail_runner/services/offline_download_service.dart';
import 'package:trail_runner/services/tile_store.dart';

// An OpenStreetMap-standard raster provider that also has a vector source
// configured, so the default download format is vector conversion unless a
// download explicitly chooses raster.
const _osmConfig = MapProviderConfig(
  id: 'openstreetmap-standard',
  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  attribution: 'OpenStreetMap contributors',
  offlineDownloadsAllowed: true,
  isDevelopmentOsmOverride: true,
  vectorSourceUrl: 'https://example.invalid/region.mbtiles',
);

const _vectorOnlyConfig = MapProviderConfig(
  id: 'vector-only',
  urlTemplate: 'https://tiles.example.invalid/{z}/{x}/{y}.png',
  attribution: 'Vector-only test',
  offlineDownloadsAllowed: false,
  isDevelopmentOsmOverride: false,
  vectorSourceUrl: 'https://example.invalid/region.mbtiles',
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
    tileDir = await Directory.systemTemp.createTemp('offline_format');
    tileStore = await TileStore.at(tileDir);
  });

  tearDown(() async {
    await database.close();
    await tileDir.delete(recursive: true);
  });

  test(
    'downloadable raster providers include OSM and CyclOSM in debug',
    () async {
      final store = await AppStore.forTesting(
        repository: repository,
        tileStore: tileStore,
        mapProvider: _osmConfig,
      );
      expect(
        store.rasterDownloadProviders.map((provider) => provider.id),
        containsAll(['openstreetmap-standard', 'cyclosm']),
      );
    },
  );

  test(
    'a vector source does not authorize its unapproved raster source',
    () async {
      final store = await AppStore.forTesting(
        repository: repository,
        tileStore: tileStore,
        mapProvider: _vectorOnlyConfig,
      );

      expect(store.offlineDownloadsAllowed, isTrue);
      expect(store.usesVectorSource, isTrue);
      expect(
        store.rasterDownloadProviders.map((provider) => provider.id),
        isNot(contains(_vectorOnlyConfig.id)),
      );
    },
  );

  test('an explicit raster format overrides the vector default and downloads '
      'from the OSM raster provider', () async {
    final requestedHosts = <String>{};
    final client = MockClient((request) async {
      requestedHosts.add(request.url.host);
      return http.Response.bytes(
        Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
        200,
        headers: {'content-type': 'image/png'},
      );
    });
    final store = await AppStore.forTesting(
      repository: repository,
      tileStore: tileStore,
      mapProvider: _osmConfig,
      downloader: OfflineDownloadService(
        repository: repository,
        store: tileStore,
        config: _osmConfig,
        client: client,
      ),
    );

    // The default would be on-device vector conversion, but the download
    // explicitly requests raster.
    expect(store.usesVectorSource, isTrue);

    await store.createOfflineArea(
      name: 'Dev raster',
      bounds: const GeoBounds(north: 0.001, south: 0.0, east: 0.001, west: 0.0),
      minZoom: 12,
      maxZoom: 12,
      format: OfflineSourceFormat.rasterTiles,
    );

    // Let the unawaited raster download settle.
    for (
      var i = 0;
      i < 100 && store.offlineAreas.first.status != OfflineAreaStatus.complete;
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    final area = store.offlineAreas.first;
    expect(area.sourceFormat, OfflineSourceFormat.rasterTiles);
    expect(area.status, OfflineAreaStatus.complete);
    // Tiles came from the OSM standard raster service, not a vector source.
    expect(requestedHosts, contains('tile.openstreetmap.org'));
  });

  test('an explicit CyclOSM raster area downloads from CyclOSM', () async {
    final requestedHosts = <String>{};
    final client = MockClient((request) async {
      requestedHosts.add(request.url.host);
      return http.Response.bytes(
        Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
        200,
        headers: {'content-type': 'image/png'},
      );
    });
    final store = await AppStore.forTesting(
      repository: repository,
      tileStore: tileStore,
      mapProvider: _osmConfig,
      downloader: OfflineDownloadService(
        repository: repository,
        store: tileStore,
        config: _osmConfig,
        client: client,
      ),
    );

    await store.createOfflineArea(
      name: 'CyclOSM raster',
      bounds: const GeoBounds(north: 0.001, south: 0.0, east: 0.001, west: 0.0),
      minZoom: 12,
      maxZoom: 12,
      format: OfflineSourceFormat.rasterTiles,
      providerId: 'cyclosm',
    );

    for (
      var i = 0;
      i < 100 && store.offlineAreas.first.status != OfflineAreaStatus.complete;
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    expect(store.offlineAreas.first.providerId, 'cyclosm');
    expect(requestedHosts, contains('a.tile-cyclosm.openstreetmap.fr'));
  });
}
