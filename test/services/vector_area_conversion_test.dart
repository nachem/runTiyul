import 'dart:io';

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
import 'package:trail_runner/services/vector_tile_source.dart';

class _FakeVectorSource implements VectorTileSource {
  _FakeVectorSource({this.returnsNull = false});

  @override
  int get minZoom => 0;

  @override
  int get maxZoom => 22;

  final bool returnsNull;
  final List<int> tile = const <int>[];
  int reads = 0;
  bool closed = false;

  @override
  Future<List<int>?> readTile(int z, int x, int y) async {
    reads++;
    return returnsNull ? null : tile;
  }

  @override
  Future<void> close() async {
    closed = true;
  }
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
    expect(result.completedTiles, plan.tileCount);
    expect(result.sourceFormat, OfflineSourceFormat.convertedVector);
    expect(fake.reads, plan.tileCount);
    expect(fake.closed, isTrue);
    for (final coordinate in plan.coordinates) {
      final file = store.fileFor(
        _config.id,
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
            .fileFor(_config.id, coordinate.z, coordinate.x, coordinate.y)
            .existsSync(),
        isFalse,
      );
    }
  });
}
