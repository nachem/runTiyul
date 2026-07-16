import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:trail_runner/core/geo/geo_bounds.dart';
import 'package:trail_runner/core/geo/tile_math.dart';
import 'package:trail_runner/data/app_database.dart';
import 'package:trail_runner/data/app_repository.dart';
import 'package:trail_runner/models/offline_area.dart';
import 'package:trail_runner/services/map_provider.dart';
import 'package:trail_runner/services/tile_store.dart';
import 'package:trail_runner/services/vector_area_conversion_service.dart';
import 'package:trail_runner/services/vector_terrain_baker.dart';
import 'package:trail_runner/services/vector_tile_source.dart';

class _FakeVectorSource implements VectorTileSource {
  _FakeVectorSource({this.returnsNull = false, this.maxZoom = 22});

  @override
  int get minZoom => 0;

  @override
  final int maxZoom;

  final bool returnsNull;
  final List<int> tile = const <int>[];
  int reads = 0;
  final List<int> readZooms = [];
  bool closed = false;

  @override
  Future<List<int>?> readTile(int z, int x, int y) async {
    reads++;
    readZooms.add(z);
    return returnsNull ? null : tile;
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

class _RecordingTerrainBaker implements VectorTerrainBaker {
  final List<TileCoordinate> coordinates = [];

  @override
  Future<Uint8List> bake(Uint8List basePng, TileCoordinate coordinate) async {
    coordinates.add(coordinate);
    return basePng;
  }

  @override
  void reset() => coordinates.clear();

  @override
  void dispose() {}
}

const _bounds = GeoBounds(north: 31.78, south: 31.77, east: 35.22, west: 35.21);

const _config = MapProviderConfig(
  id: 'trail-vector',
  urlTemplate: 'https://example.invalid/{z}/{x}/{y}.png',
  attribution: 'Test',
  offlineDownloadsAllowed: true,
  isDevelopmentOsmOverride: false,
  vectorSourceUrl: '/tmp/example.mbtiles',
);

final _vecNamespace = offlineTileNamespace(
  _config.id,
  OfflineSourceFormat.convertedVector,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late AppRepository repository;
  late Directory tileDir;
  late TileStore store;

  setUp(() async {
    sqfliteFfiInit();
    database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    repository = AppRepository(database);
    tileDir = await Directory.systemTemp.createTemp('vector_convert');
    store = await TileStore.at(tileDir);
  });

  tearDown(() async {
    await database.close();
    await tileDir.delete(recursive: true);
  });

  OfflineArea plannedArea(TilePlan plan) => OfflineArea(
    id: 'area-vector',
    name: 'Vector area',
    bounds: _bounds,
    minZoom: 12,
    maxZoom: 12,
    providerId: _config.id,
    status: OfflineAreaStatus.planned,
    totalTiles: plan.tileCount,
    completedTiles: 0,
    actualBytes: 0,
    createdAt: DateTime.utc(2026, 7, 14),
    updatedAt: DateTime.utc(2026, 7, 14),
    sourceFormat: OfflineSourceFormat.convertedVector,
  );

  test('converts vector tiles into stored PNGs on the device', () async {
    final fake = _FakeVectorSource();
    final terrainBaker = _RecordingTerrainBaker();
    final service = VectorAreaConversionService(
      repository: repository,
      store: store,
      config: _config,
      terrainBaker: terrainBaker,
      openSource: (_) async => fake,
    );
    final plan = const TilePlanner(maxTiles: 100).plan(_bounds, 12, 12);

    final result = await service.convert(
      plannedArea(plan),
      plan,
      onProgress: (_) {},
    );

    expect(result.status, OfflineAreaStatus.complete);
    expect(result.completedTiles, plan.tileCount);
    expect(result.sourceFormat, OfflineSourceFormat.convertedVector);
    expect(fake.reads, plan.tileCount);
    expect(terrainBaker.coordinates, plan.coordinates);
    expect(fake.closed, isTrue);
    for (final coordinate in plan.coordinates) {
      final file = store.fileFor(
        _vecNamespace,
        coordinate.z,
        coordinate.x,
        coordinate.y,
      );
      expect(file.existsSync(), isTrue);
      // Every stored tile is a valid PNG produced by the rasterizer.
      expect(file.readAsBytesSync().sublist(0, 4), [0x89, 0x50, 0x4e, 0x47]);
    }

    final loaded = await repository.loadOfflineAreas();
    expect(loaded.single.status, OfflineAreaStatus.complete);
    expect(loaded.single.sourceFormat, OfflineSourceFormat.convertedVector);
    final tracked = await repository.unsharedTiles(result.id);
    expect(tracked.every((row) => row['provider_id'] == _vecNamespace), isTrue);
  });

  test('missing tiles are skipped and the area still completes', () async {
    final fake = _FakeVectorSource(returnsNull: true);
    final service = VectorAreaConversionService(
      repository: repository,
      store: store,
      config: _config,
      openSource: (_) async => fake,
    );
    final plan = const TilePlanner(maxTiles: 100).plan(_bounds, 12, 12);

    final result = await service.convert(
      plannedArea(plan),
      plan,
      onProgress: (_) {},
    );

    expect(result.status, OfflineAreaStatus.complete);
    expect(fake.reads, plan.tileCount);
    expect(fake.closed, isTrue);
    for (final coordinate in plan.coordinates) {
      expect(
        store
            .fileFor(_vecNamespace, coordinate.z, coordinate.x, coordinate.y)
            .existsSync(),
        isFalse,
      );
    }
  });

  test('over-renders tiles above the source maximum from the parent', () async {
    final fake = _FakeVectorSource(maxZoom: 14);
    final service = VectorAreaConversionService(
      repository: repository,
      store: store,
      config: _config,
      openSource: (_) async => fake,
    );
    // Plan at zoom 16, above the source's z14 maximum, so every tile is
    // produced by over-rendering the covering z14 parent tile.
    final plan = const TilePlanner(maxTiles: 500).plan(_bounds, 16, 16);

    final result = await service.convert(
      plannedArea(plan),
      plan,
      onProgress: (_) {},
    );

    expect(result.status, OfflineAreaStatus.complete);
    expect(result.completedTiles, plan.tileCount);
    // The source is only ever read at its maximum zoom (parent tiles), never at
    // the deeper requested zoom.
    expect(fake.readZooms, isNotEmpty);
    expect(fake.readZooms.every((z) => z == 14), isTrue);
    for (final coordinate in plan.coordinates) {
      final file = store.fileFor(
        _vecNamespace,
        coordinate.z,
        coordinate.x,
        coordinate.y,
      );
      expect(file.existsSync(), isTrue);
      expect(file.readAsBytesSync().sublist(0, 4), [0x89, 0x50, 0x4e, 0x47]);
    }
  });
}
