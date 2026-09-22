import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:trail_runner/app/app_store.dart';
import 'package:trail_runner/core/geo/geo_bounds.dart';
import 'package:trail_runner/core/geo/tile_math.dart';
import 'package:trail_runner/data/app_database.dart';
import 'package:trail_runner/data/app_repository.dart';
import 'package:trail_runner/models/offline_area.dart';
import 'package:trail_runner/services/download_foreground_service.dart';
import 'package:trail_runner/services/map_provider.dart';
import 'package:trail_runner/services/tile_store.dart';
import 'package:trail_runner/services/vector_area_conversion_service.dart';

/// Records keep-alive start/stop calls instead of touching a platform channel.
class _RecordingService extends DownloadForegroundService {
  int starts = 0;
  int stops = 0;

  @override
  Future<void> start() async => starts++;

  @override
  Future<void> stop() async => stops++;
}

/// A converter that finishes immediately without any network or rasterization,
/// optionally reporting the first attempt as an interruption ([failFirst]).
class _InstantConverter extends VectorAreaConversionService {
  _InstantConverter({
    required super.repository,
    required super.store,
    required super.config,
    this.failFirst = false,
  });

  final bool failFirst;
  int calls = 0;

  @override
  Future<OfflineArea> convert(
    OfflineArea initial,
    TilePlan plan, {
    required void Function(OfflineArea area) onProgress,
    String? sourceOverride,
  }) async {
    calls++;
    final status = (failFirst && calls == 1)
        ? OfflineAreaStatus.failed
        : OfflineAreaStatus.complete;
    final result = _withStatus(initial, status);
    onProgress(result);
    return result;
  }

  @override
  void cancel(String areaId) {}
}

/// Holds the first write open so cancellation/edit/delete interleavings are
/// deterministic. It deliberately persists after cancel, like an in-flight
/// HTTP response finishing before the downloader observes cancellation.
class _BlockedConverter extends VectorAreaConversionService {
  _BlockedConverter({
    required super.repository,
    required super.store,
    required super.config,
  });

  final entered = Completer<void>();
  final release = Completer<void>();
  final cancelled = <String>{};
  int calls = 0;

  @override
  void cancel(String areaId) => cancelled.add(areaId);

  @override
  Future<OfflineArea> convert(
    OfflineArea initial,
    TilePlan plan, {
    required void Function(OfflineArea) onProgress,
    String? sourceOverride,
  }) async {
    cancelled.remove(initial.id);
    calls++;
    if (calls == 1) {
      entered.complete();
      await release.future;
    }
    final result = _withStatus(
      initial,
      cancelled.contains(initial.id)
          ? OfflineAreaStatus.paused
          : OfflineAreaStatus.complete,
    );
    await repository.saveOfflineArea(result);
    onProgress(result);
    return result;
  }
}

const _bounds = GeoBounds(north: 31.78, south: 31.77, east: 35.22, west: 35.21);

const _config = MapProviderConfig(
  id: 'bg-test',
  urlTemplate: 'https://example.invalid/{z}/{x}/{y}.png',
  attribution: 'Test',
  offlineDownloadsAllowed: true,
  isDevelopmentOsmOverride: false,
  vectorSourceUrl: '/tmp/bg.mbtiles',
);

OfflineArea _convertedArea(OfflineAreaStatus status) => OfflineArea(
  id: 'bg-area',
  name: 'Background area',
  bounds: _bounds,
  minZoom: 12,
  maxZoom: 12,
  providerId: _config.id,
  status: status,
  totalTiles: 4,
  completedTiles: 0,
  actualBytes: 0,
  createdAt: DateTime.utc(2026, 7, 15),
  updatedAt: DateTime.utc(2026, 7, 15),
  sourceFormat: OfflineSourceFormat.convertedVector,
);

OfflineArea _withStatus(OfflineArea area, OfflineAreaStatus status) =>
    OfflineArea(
      id: area.id,
      name: area.name,
      bounds: area.bounds,
      minZoom: area.minZoom,
      maxZoom: area.maxZoom,
      providerId: area.providerId,
      status: status,
      totalTiles: area.totalTiles,
      completedTiles: status == OfflineAreaStatus.complete
          ? area.totalTiles
          : area.completedTiles,
      actualBytes: area.actualBytes,
      createdAt: area.createdAt,
      updatedAt: DateTime.now().toUtc(),
      sourceFormat: area.sourceFormat,
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
    tileDir = await Directory.systemTemp.createTemp('bg_download');
    tileStore = await TileStore.at(tileDir);
  });

  tearDown(() async {
    await database.close();
    await tileDir.delete(recursive: true);
  });

  Future<(AppStore, _BlockedConverter)> blockedStore() async {
    final converter = _BlockedConverter(
      repository: repository,
      store: tileStore,
      config: _config,
    );
    final store = await AppStore.forTesting(
      repository: repository,
      tileStore: tileStore,
      mapProvider: _config,
      vectorConverter: converter,
    );
    addTearDown(store.dispose);
    final area = _convertedArea(OfflineAreaStatus.paused);
    await repository.saveOfflineArea(area);
    store.offlineAreas = [area];
    return (store, converter);
  }

  test('duplicate resumes share one worker', () async {
    final (store, converter) = await blockedStore();
    final area = store.offlineAreas.single;
    final first = store.resumeDownload(area);
    await converter.entered.future;
    final second = store.resumeDownload(area);
    await Future<void>.delayed(Duration.zero);
    expect(converter.calls, 1);
    converter.release.complete();
    await Future.wait([first, second]);
    expect(converter.calls, 1);
  });

  test('delete drains cancelled writes and cannot resurrect an area', () async {
    final (store, converter) = await blockedStore();
    final area = store.offlineAreas.single;
    final running = store.resumeDownload(area);
    await converter.entered.future;
    final deleting = store.deleteOfflineArea(area);
    await store.resumeDownload(area); // Ignored while deletion owns the area.
    expect(await repository.loadOfflineAreas(), hasLength(1));
    converter.release.complete();
    await Future.wait([running, deleting]);
    await store.resumeInterruptedDownloads();
    expect(await repository.loadOfflineAreas(), isEmpty);
    expect(store.offlineAreas, isEmpty);
    expect(converter.calls, 1);
  });

  test('edit drains the old plan before starting its replacement', () async {
    final (store, converter) = await blockedStore();
    final area = store.offlineAreas.single;
    final running = store.resumeDownload(area);
    await converter.entered.future;
    final editing = store.updateOfflineArea(
      area: area,
      name: 'Edited',
      bounds: area.bounds,
      minZoom: 13,
      maxZoom: 13,
    );
    await Future<void>.delayed(Duration.zero);
    expect(converter.calls, 1);
    converter.release.complete();
    await Future.wait([running, editing]);
    await store.resumeDownload(store.offlineAreas.single);
    final saved = (await repository.loadOfflineAreas()).single;
    expect(saved.name, 'Edited');
    expect(saved.minZoom, 13);
    expect(saved.status, OfflineAreaStatus.complete);
    expect(converter.calls, 2);
  });

  test('overlapping area jobs are serialized', () async {
    final (store, converter) = await blockedStore();
    final running = store.resumeDownload(store.offlineAreas.single);
    await converter.entered.future;
    await store.createOfflineArea(
      name: 'Second',
      bounds: _bounds,
      minZoom: 12,
      maxZoom: 12,
    );
    await Future<void>.delayed(Duration.zero);
    expect(converter.calls, 1);
    expect(store.isDownloadQueued(store.offlineAreas.first.id), isTrue);
    final queued = store.resumeDownload(store.offlineAreas.first);
    converter.release.complete();
    await Future.wait([running, queued]);
    expect(converter.calls, 2);
  });

  test('pausing a queued area never starts its worker', () async {
    final (store, converter) = await blockedStore();
    final running = store.resumeDownload(store.offlineAreas.single);
    await converter.entered.future;
    await store.createOfflineArea(
      name: 'Queued',
      bounds: _bounds,
      minZoom: 12,
      maxZoom: 12,
    );
    final area = store.offlineAreas.first;
    final queued = store.resumeDownload(area);
    store.cancelDownload(area);
    converter.release.complete();
    await Future.wait([running, queued]);
    expect(converter.calls, 1);
    expect(store.isDownloadQueued(area.id), isFalse);
  });

  test('resume honors an approved plan larger than the default cap', () async {
    final converter = _InstantConverter(
      repository: repository,
      store: tileStore,
      config: _config,
    );
    final store = await AppStore.forTesting(
      repository: repository,
      tileStore: tileStore,
      mapProvider: _config,
      vectorConverter: converter,
    );
    addTearDown(store.dispose);
    const bounds = GeoBounds(north: 32, south: 31.8, east: 35.4, west: 35.2);
    final plan = const TilePlanner(maxTiles: 10000).plan(bounds, 16, 16);
    expect(plan.tileCount, greaterThan(1200));
    await store.resumeDownload(
      OfflineArea(
        id: 'large',
        name: 'Large',
        bounds: bounds,
        minZoom: 16,
        maxZoom: 16,
        providerId: _config.id,
        status: OfflineAreaStatus.paused,
        totalTiles: plan.tileCount,
        completedTiles: 0,
        actualBytes: 0,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        sourceFormat: OfflineSourceFormat.convertedVector,
      ),
    );
    expect(converter.calls, 1);
    expect(store.errorMessage, isNull);
  });

  test(
    'keep-alive service starts while downloading and stops when done',
    () async {
      final service = _RecordingService();
      final store = await AppStore.forTesting(
        repository: repository,
        tileStore: tileStore,
        mapProvider: _config,
        vectorConverter: _InstantConverter(
          repository: repository,
          store: tileStore,
          config: _config,
        ),
        backgroundDownloads: service,
      );
      addTearDown(store.dispose);

      await store.resumeDownload(_convertedArea(OfflineAreaStatus.paused));

      expect(service.starts, 1);
      expect(service.stops, 1);
    },
  );

  test('auto-resumes a download interrupted in the background', () async {
    final service = _RecordingService();
    final converter = _InstantConverter(
      repository: repository,
      store: tileStore,
      config: _config,
      failFirst: true,
    );
    final store = await AppStore.forTesting(
      repository: repository,
      tileStore: tileStore,
      mapProvider: _config,
      vectorConverter: converter,
      backgroundDownloads: service,
    );
    addTearDown(store.dispose);

    final area = _convertedArea(OfflineAreaStatus.paused);
    store.offlineAreas = [area];

    // The first attempt fails, as if the OS interrupted it in the background,
    // so the area stays intended.
    await store.resumeDownload(area);
    expect(converter.calls, 1);

    // Returning to the foreground resumes it; the second attempt completes.
    await store.resumeInterruptedDownloads();
    expect(converter.calls, 2);

    // A completed download is never resumed again.
    await store.resumeInterruptedDownloads();
    expect(converter.calls, 2);
  });
}
