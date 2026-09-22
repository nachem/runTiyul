import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:trail_runner/core/geo/geo_bounds.dart';
import 'package:trail_runner/core/geo/tile_math.dart';
import 'package:trail_runner/core/time/clock.dart';
import 'package:trail_runner/data/app_database.dart';
import 'package:trail_runner/data/app_repository.dart';
import 'package:trail_runner/models/offline_area.dart';
import 'package:trail_runner/services/map_provider.dart';
import 'package:trail_runner/services/offline_download_service.dart';
import 'package:trail_runner/services/tile_store.dart';

const _bounds = GeoBounds(
  north: 0.001,
  south: 0.0001,
  east: 0.001,
  west: 0.0001,
);

const _config = MapProviderConfig(
  id: 'download-test',
  urlTemplate: 'https://example.invalid/{z}/{x}/{y}.png',
  attribution: 'Test',
  offlineDownloadsAllowed: true,
  isDevelopmentOsmOverride: false,
);

const _fastPolicy = RasterDownloadPolicy(
  minimumRequestInterval: Duration(milliseconds: 20),
  requestsPerBatch: 2,
  batchPause: Duration(milliseconds: 80),
  retryBaseDelay: Duration(milliseconds: 20),
  rateLimitBaseDelay: Duration(milliseconds: 40),
);

MapProviderConfig _provider({
  String id = 'download-test',
  RasterDownloadPolicy policy = _fastPolicy,
  bool allowed = true,
}) => MapProviderConfig(
  id: id,
  urlTemplate: 'https://example.invalid/{z}/{x}/{y}.png',
  attribution: 'Test',
  offlineDownloadsAllowed: allowed,
  isDevelopmentOsmOverride: false,
  downloadPolicy: policy,
);

TilePlan _plan([int count = 1]) => TilePlan([
  for (var index = 0; index < count; index++) TileCoordinate(12, index, 0),
]);

OfflineArea _area(TilePlan plan, {String providerId = 'download-test'}) =>
    OfflineArea(
      id: 'area',
      name: 'Test area',
      bounds: _bounds,
      minZoom: 12,
      maxZoom: 12,
      providerId: providerId,
      status: OfflineAreaStatus.planned,
      totalTiles: plan.tileCount,
      completedTiles: 0,
      actualBytes: 0,
      createdAt: DateTime.utc(2026, 9, 22),
      updatedAt: DateTime.utc(2026, 9, 22),
    );

http.Response _image() => http.Response.bytes(
  [137, 80, 78, 71, 13, 10, 26, 10],
  200,
  headers: {'content-type': 'image/png'},
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
    tileDir = await Directory.systemTemp.createTemp('raster_download');
    tileStore = await TileStore.at(tileDir);
  });

  tearDown(() async {
    await database.close();
    await tileDir.delete(recursive: true);
  });

  OfflineDownloadService service(
    Future<http.Response> Function(http.Request) handler, {
    MapProviderConfig? provider,
    Clock clock = const SystemClock(),
  }) {
    final downloader = OfflineDownloadService(
      repository: repository,
      store: tileStore,
      config: provider ?? _provider(),
      clock: clock,
      client: MockClient(handler),
    );
    addTearDown(downloader.dispose);
    return downloader;
  }

  Future<OfflineArea> download(
    OfflineDownloadService downloader, {
    int tiles = 1,
    String providerId = 'download-test',
  }) {
    final plan = _plan(tiles);
    return downloader.download(
      _area(plan, providerId: providerId),
      plan,
      onProgress: (_) {},
    );
  }

  test(
    'OFF-005/009: pause during a rate-limit response stops retries',
    () async {
      var requests = 0;
      late OfflineDownloadService downloader;
      downloader = OfflineDownloadService(
        repository: repository,
        store: tileStore,
        config: _config,
        client: MockClient((request) async {
          requests++;
          downloader.cancel('area');
          return http.Response('', 429, headers: {'retry-after': '60'});
        }),
      );
      addTearDown(downloader.dispose);
      final plan = const TilePlanner().plan(_bounds, 12, 12);
      final area = OfflineArea(
        id: 'area',
        name: 'Test area',
        bounds: _bounds,
        minZoom: 12,
        maxZoom: 12,
        providerId: _config.id,
        status: OfflineAreaStatus.planned,
        totalTiles: plan.tileCount,
        completedTiles: 0,
        actualBytes: 0,
        createdAt: DateTime.utc(2026, 9, 22),
        updatedAt: DateTime.utc(2026, 9, 22),
      );

      final result = await downloader.download(area, plan, onProgress: (_) {});

      expect(requests, 1);
      expect(result.status, OfflineAreaStatus.paused);
      expect(result.completedTiles, 0);
      expect(result.lastError, isNull);
    },
  );

  test('OFF-009: request starts are spaced and batches take a break', () async {
    final starts = <DateTime>[];
    final downloader = service((request) async {
      starts.add(DateTime.now().toUtc());
      return _image();
    });

    final result = await download(downloader, tiles: 5);

    expect(result.status, OfflineAreaStatus.complete);
    expect(starts, hasLength(5));
    for (var index = 1; index < starts.length; index++) {
      final minimum = index.isEven ? 80 : 20;
      expect(
        starts[index].difference(starts[index - 1]).inMilliseconds,
        greaterThanOrEqualTo(minimum - 2),
      );
    }
  });

  test('OFF-009: configured concurrency is bounded', () async {
    var active = 0;
    var maximumActive = 0;
    final twoStarted = Completer<void>();
    final release = Completer<void>();
    var requests = 0;
    final downloader = service(
      (request) async {
        requests++;
        active++;
        if (active > maximumActive) maximumActive = active;
        if (requests == 2) twoStarted.complete();
        await release.future;
        active--;
        return _image();
      },
      provider: _provider(
        policy: const RasterDownloadPolicy(
          maxConcurrentRequests: 2,
          minimumRequestInterval: Duration.zero,
        ),
      ),
    );

    final running = download(downloader, tiles: 5);
    await twoStarted.future;
    expect(requests, 2);
    release.complete();
    expect((await running).status, OfflineAreaStatus.complete);
    expect(maximumActive, 2);
  });

  test('OFF-009: Retry-After seconds delays every worker', () async {
    final starts = <DateTime>[];
    final downloader = service((request) async {
      starts.add(DateTime.now().toUtc());
      if (starts.length == 1) {
        return http.Response('', 429, headers: {'retry-after': '1'});
      }
      return _image();
    });

    final result = await download(downloader, tiles: 4);

    expect(result.status, OfflineAreaStatus.complete);
    expect(starts, hasLength(5));
    expect(
      starts[1].difference(starts.first).inMilliseconds,
      greaterThanOrEqualTo(998),
    );
    final saved = await repository.loadSetting(
      'raster_download_cooldown_v1:download-test',
    );
    expect(DateTime.parse(saved!), isNotNull);
  });

  test(
    'OFF-009: a later cooldown extends the deadline for waiting workers',
    () async {
      var requests = 0;
      final firstResponse = Completer<http.Response>();
      final secondResponse = Completer<http.Response>();
      final firstTwoStarted = Completer<void>();
      final starts = <DateTime>[];
      final downloader = service(
        (request) async {
          starts.add(DateTime.now().toUtc());
          requests++;
          if (requests == 1) return firstResponse.future;
          if (requests == 2) {
            firstTwoStarted.complete();
            return secondResponse.future;
          }
          return _image();
        },
        provider: _provider(
          policy: const RasterDownloadPolicy(
            maxConcurrentRequests: 2,
            minimumRequestInterval: Duration.zero,
            retryBaseDelay: Duration(milliseconds: 20),
          ),
        ),
      );

      final running = download(downloader, tiles: 3);
      await firstTwoStarted.future;
      firstResponse.complete(http.Response('', 503));
      final extendedAt = DateTime.now().toUtc();
      secondResponse.complete(
        http.Response('', 503, headers: {'retry-after': '1'}),
      );
      final result = await running;

      expect(result.status, OfflineAreaStatus.complete);
      expect(requests, 5);
      for (final started in starts.skip(2)) {
        expect(
          started.difference(extendedAt).inMilliseconds,
          greaterThanOrEqualTo(998),
        );
      }
    },
  );

  test(
    'OFF-005/009: HTTP-date cooldown survives restart and reuses tiles',
    () async {
      final clock = FakeClock(DateTime.utc(2026, 9, 22, 12));
      final deadline = clock.nowUtc().add(const Duration(minutes: 5));
      final provider = _provider(
        policy: const RasterDownloadPolicy(
          maxConcurrentRequests: 1,
          minimumRequestInterval: Duration.zero,
        ),
      );
      var requests = 0;
      final downloader = service(
        (request) async {
          requests++;
          return requests == 1
              ? _image()
              : http.Response(
                  '',
                  503,
                  headers: {'retry-after': HttpDate.format(deadline)},
                );
        },
        provider: provider,
        clock: clock,
      );

      final paused = await download(downloader, tiles: 2);
      expect(paused.status, OfflineAreaStatus.paused);
      expect(paused.completedTiles, 1);
      expect(paused.lastError, contains(deadline.toIso8601String()));
      expect(requests, 2);

      var resumedRequests = 0;
      final restarted = service(
        (request) async {
          resumedRequests++;
          return _image();
        },
        provider: provider,
        clock: clock,
      );
      final waiting = await download(restarted, tiles: 2);
      expect(waiting.status, OfflineAreaStatus.paused);
      expect(resumedRequests, 0);
      expect(waiting.completedTiles, 1);

      clock.set(deadline);
      final complete = await download(restarted, tiles: 2);
      expect(complete.status, OfflineAreaStatus.complete);
      expect(complete.completedTiles, 2);
      expect(complete.actualBytes, 16);
      expect(resumedRequests, 1);
    },
  );

  for (final header in ['not-a-date', '-1', 'Tue, 22 Sep 2026 00:00:00 GMT']) {
    test(
      'OFF-009: invalid or past Retry-After uses fallback: $header',
      () async {
        final clock = FakeClock(DateTime.utc(2026, 9, 22, 12));
        var requests = 0;
        final downloader = service(
          (request) async {
            requests++;
            return http.Response('', 429, headers: {'retry-after': header});
          },
          provider: _provider(
            policy: const RasterDownloadPolicy(maxAutomaticWait: Duration.zero),
          ),
          clock: clock,
        );

        final result = await download(downloader);
        expect(result.status, OfflineAreaStatus.paused);
        expect(requests, 1);
        final saved = await repository.loadSetting(
          'raster_download_cooldown_v1:download-test',
        );
        expect(
          DateTime.parse(saved!),
          clock.nowUtc().add(const Duration(seconds: 30)),
        );
      },
    );
  }

  test(
    'OFF-009: cooldown is shared across resume but isolated by provider',
    () async {
      final clock = FakeClock(DateTime.utc(2026, 9, 22));
      final first = _provider(
        policy: const RasterDownloadPolicy(maxAutomaticWait: Duration.zero),
      );
      final second = _provider(id: 'other-provider');
      var requests = 0;
      final downloader = service(
        (request) async {
          requests++;
          return requests == 1 ? http.Response('', 429) : _image();
        },
        provider: first,
        clock: clock,
      );

      expect((await download(downloader)).status, OfflineAreaStatus.paused);
      expect((await download(downloader)).status, OfflineAreaStatus.paused);
      expect(requests, 1);
      final plan = _plan();
      final other = await downloader.download(
        _area(plan, providerId: second.id),
        plan,
        provider: second,
        onProgress: (_) {},
      );
      expect(other.status, OfflineAreaStatus.complete);
      expect(requests, 2);
    },
  );

  test('OFF-005/009: pause interrupts an active cooldown wait', () async {
    final responded = Completer<void>();
    var requests = 0;
    final downloader = service((request) async {
      requests++;
      responded.complete();
      return http.Response('', 429, headers: {'retry-after': '60'});
    });

    final running = download(downloader);
    await responded.future;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    downloader.cancel('area');
    final result = await running.timeout(const Duration(seconds: 1));
    expect(result.status, OfflineAreaStatus.paused);
    expect(result.lastError, isNull);
    expect(requests, 1);
  });

  test(
    'OFF-005/009: pause interrupts a batch break and resume skips saved tiles',
    () async {
      final provider = _provider(
        policy: const RasterDownloadPolicy(
          maxConcurrentRequests: 1,
          minimumRequestInterval: Duration.zero,
          requestsPerBatch: 1,
          batchPause: Duration(minutes: 1),
        ),
      );
      final saved = Completer<void>();
      var requests = 0;
      final downloader = service((request) async {
        requests++;
        return _image();
      }, provider: provider);
      final plan = _plan(2);
      final running = downloader.download(
        _area(plan),
        plan,
        onProgress: (area) {
          if (area.completedTiles == 1 && !saved.isCompleted) saved.complete();
        },
      );
      await saved.future;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      downloader.cancel('area');
      final paused = await running.timeout(const Duration(seconds: 1));
      expect(paused.status, OfflineAreaStatus.paused);
      expect(paused.completedTiles, 1);
      expect(requests, 1);

      final restarted = service((request) async {
        requests++;
        return _image();
      }, provider: provider);
      final complete = await download(restarted, tiles: 2);
      expect(complete.status, OfflineAreaStatus.complete);
      expect(complete.completedTiles, 2);
      expect(requests, 2);
    },
  );

  test(
    'OFF-009: transient server failures use bounded exponential backoff',
    () async {
      final starts = <DateTime>[];
      final downloader = service(
        (request) async {
          starts.add(DateTime.now().toUtc());
          return http.Response('', 503);
        },
        provider: _provider(
          policy: const RasterDownloadPolicy(
            minimumRequestInterval: Duration.zero,
            retryBaseDelay: Duration(milliseconds: 40),
          ),
        ),
      );

      final result = await download(downloader);
      expect(result.status, OfflineAreaStatus.failed);
      expect(result.lastError, contains('503'));
      expect(starts, hasLength(3));
      expect(
        starts[1].difference(starts[0]).inMilliseconds,
        greaterThanOrEqualTo(38),
      );
      expect(
        starts[2].difference(starts[1]).inMilliseconds,
        greaterThanOrEqualTo(78),
      );
    },
  );

  test('OFF-009: repeated rate limiting pauses after three attempts', () async {
    var requests = 0;
    final downloader = service((request) async {
      requests++;
      return http.Response('', 429);
    });

    final result = await download(downloader);
    expect(requests, 3);
    expect(result.status, OfflineAreaStatus.paused);
    expect(result.lastError, contains('rate-limiting'));
  });

  for (final status in [401, 403, 404]) {
    test('OFF-009/012: HTTP $status is not retried', () async {
      var requests = 0;
      final downloader = service((request) async {
        requests++;
        return http.Response('', status);
      });

      final result = await download(downloader, tiles: 5);
      expect(requests, 1);
      expect(
        result.status,
        status == 404 ? OfflineAreaStatus.failed : OfflineAreaStatus.paused,
      );
      expect(result.lastError, contains('$status'));
    });
  }

  test(
    'OFF-009: network failures retry without accepting a stale response',
    () async {
      var requests = 0;
      final downloader = service((request) async {
        requests++;
        if (requests < 3) throw http.ClientException('Disconnected');
        return _image();
      });

      final result = await download(downloader);
      expect(result.status, OfflineAreaStatus.complete);
      expect(requests, 3);
      expect(result.completedTiles, 1);
    },
  );

  test('OFF-009: empty or non-image responses fail without retry', () async {
    for (final response in [
      http.Response('', 200, headers: {'content-type': 'image/png'}),
      http.Response('html', 200, headers: {'content-type': 'text/html'}),
    ]) {
      var requests = 0;
      final downloader = service((request) async {
        requests++;
        return response;
      });
      final result = await download(downloader);
      expect(result.status, OfflineAreaStatus.failed);
      expect(requests, 1);
      expect(result.completedTiles, 0);
    }
  });

  test('OFF-012: pacing does not authorize a blocked provider', () async {
    var requests = 0;
    final downloader = service((request) async {
      requests++;
      return _image();
    }, provider: _provider(allowed: false));

    await expectLater(download(downloader), throwsStateError);
    expect(requests, 0);
  });
}
