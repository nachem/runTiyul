import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:trail_runner/app/app_store.dart';
import 'package:trail_runner/core/geo/geo_bounds.dart';
import 'package:trail_runner/core/geo/tile_math.dart';
import 'package:trail_runner/data/app_database.dart';
import 'package:trail_runner/data/app_repository.dart';
import 'package:trail_runner/models/offline_area.dart';
import 'package:trail_runner/services/map_provider.dart';
import 'package:trail_runner/services/offline_download_service.dart';
import 'package:trail_runner/services/tile_store.dart';

const _lockedOsm = MapProviderConfig(
  id: 'openstreetmap-standard',
  label: 'Streets',
  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  attribution: 'OpenStreetMap contributors',
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
    tileDir = await Directory.systemTemp.createTemp('raster_dev_unlock');
    tileStore = await TileStore.at(tileDir);
  });

  tearDown(() async {
    await database.close();
    if (await tileDir.exists()) await tileDir.delete(recursive: true);
  });

  test(
    'developer raster unlock persists and promotes only public dev layers',
    () async {
      final store = await AppStore.forTesting(
        repository: repository,
        tileStore: tileStore,
        mapProvider: _lockedOsm,
        publicRasterDevUnlockCompiled: true,
      );
      addTearDown(store.dispose);

      expect(store.publicRasterDevUnlockAvailable, isTrue);
      expect(store.publicRasterDevDownloadsUnlocked, isFalse);
      expect(
        store.rasterDownloadProviders.map((provider) => provider.id),
        isNot(contains(_lockedOsm.id)),
      );

      expect(await store.enablePublicRasterDevDownloads(), isTrue);
      expect(store.publicRasterDevDownloadsUnlocked, isTrue);
      expect(store.publicRasterDevUnlockAvailable, isFalse);
      expect(
        store.rasterDownloadProviders.map((provider) => provider.id),
        contains(_lockedOsm.id),
      );
      expect(
        store.rasterDownloadProviders.map((provider) => provider.id),
        isNot(contains(MapProviderConfig.esriWorldImagery.id)),
      );

      final reloaded = await AppStore.forTesting(
        repository: repository,
        tileStore: tileStore,
        mapProvider: _lockedOsm,
        publicRasterDevUnlockCompiled: true,
      );
      addTearDown(reloaded.dispose);
      expect(reloaded.publicRasterDevDownloadsUnlocked, isTrue);
      expect(
        reloaded.rasterDownloadProviders.map((provider) => provider.id),
        contains(_lockedOsm.id),
      );
    },
  );

  test('unlock is impossible when the capability is compiled out', () async {
    final store = await AppStore.forTesting(
      repository: repository,
      tileStore: tileStore,
      mapProvider: _lockedOsm,
      publicRasterDevUnlockCompiled: false,
    );
    addTearDown(store.dispose);

    expect(store.publicRasterDevUnlockAvailable, isFalse);
    expect(await store.enablePublicRasterDevDownloads(), isFalse);
    expect(store.publicRasterDevDownloadsUnlocked, isFalse);
  });

  test('explicit authorized capability promotes topo and satellite', () async {
    final store = await AppStore.forTesting(
      repository: repository,
      tileStore: tileStore,
      mapProvider: _lockedOsm,
      publicRasterDevUnlockCompiled: true,
      authorizedViewRasterDevUnlockCompiled: true,
    );
    addTearDown(store.dispose);

    expect(await store.enablePublicRasterDevDownloads(), isTrue);
    expect(
      store.rasterDownloadProviders.map((provider) => provider.id),
      containsAll([
        MapProviderConfig.openTopoMap.id,
        MapProviderConfig.esriWorldImagery.id,
      ]),
    );
  });

  test(
    'OFF-012: authorized Esri download uses its endpoint and storage namespace',
    () async {
      final requests = <Uri>[];
      final store = await AppStore.forTesting(
        repository: repository,
        tileStore: tileStore,
        mapProvider: _lockedOsm,
        publicRasterDevUnlockCompiled: true,
        authorizedViewRasterDevUnlockCompiled: true,
        downloader: OfflineDownloadService(
          repository: repository,
          store: tileStore,
          config: _lockedOsm,
          client: MockClient((request) async {
            requests.add(request.url);
            return http.Response.bytes(
              [137, 80, 78, 71, 13, 10, 26, 10],
              200,
              headers: {'content-type': 'image/png'},
            );
          }),
        ),
      );
      addTearDown(store.dispose);
      await store.enablePublicRasterDevDownloads();
      await store.setActiveMapLayer(MapProviderConfig.esriWorldImagery.id);
      const bounds = GeoBounds(north: 1.001, south: 1, east: 1.001, west: 1);
      final coordinate = const TilePlanner()
          .plan(bounds, 12, 12)
          .coordinates
          .single;
      await store.createOfflineArea(
        name: 'Authorized Esri test',
        bounds: bounds,
        minZoom: 12,
        maxZoom: 12,
        format: OfflineSourceFormat.rasterTiles,
        providerId: MapProviderConfig.esriWorldImagery.id,
      );
      await store.resumeDownload(store.offlineAreas.single);

      expect(requests, hasLength(1));
      expect(requests.single.host, 'server.arcgisonline.com');
      expect(
        requests.single.path,
        endsWith('/tile/${coordinate.z}/${coordinate.y}/${coordinate.x}'),
      );
      final area = (await repository.loadOfflineAreas()).single;
      expect(area.providerId, MapProviderConfig.esriWorldImagery.id);
      expect(area.status, OfflineAreaStatus.complete);
      expect(
        await tileStore
            .fileFor(
              offlineTileNamespace(
                area.providerId,
                OfflineSourceFormat.rasterTiles,
              ),
              coordinate.z,
              coordinate.x,
              coordinate.y,
            )
            .exists(),
        isTrue,
      );
    },
  );
}
