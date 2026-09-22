import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/geo/tile_math.dart';
import '../core/time/clock.dart';
import '../data/app_repository.dart';
import '../models/offline_area.dart';
import 'map_provider.dart';
import 'tile_store.dart';

class OfflineDownloadService {
  OfflineDownloadService({
    required this.repository,
    required this.store,
    required this.config,
    http.Client? client,
    this.clock = const SystemClock(),
  }) : _client = client ?? http.Client();

  final AppRepository repository;
  final TileStore store;
  final MapProviderConfig config;
  final Clock clock;
  final http.Client _client;
  final Map<String, _DownloadControl> _downloads = {};
  final Map<String, Future<_ProviderDownloadState>> _providers = {};

  void cancel(String areaId) => _downloads[areaId]?.stop(cancelled: true);

  void dispose() {
    for (final control in _downloads.values) {
      control.stop(cancelled: true);
    }
    _client.close();
  }

  Future<OfflineArea> download(
    OfflineArea initial,
    TilePlan plan, {
    required void Function(OfflineArea area) onProgress,
    MapProviderConfig? provider,
  }) async {
    final activeConfig = provider ?? config;
    if (initial.providerId != activeConfig.id) {
      throw StateError(
        'Offline area provider ${initial.providerId} does not match '
        '${activeConfig.id}.',
      );
    }
    if (!activeConfig.offlineDownloadsAllowed) {
      throw StateError(
        'This map provider is not configured to permit offline downloads.',
      );
    }
    final control = _DownloadControl();
    _downloads[initial.id] = control;
    try {
      return await _download(initial, plan, activeConfig, control, onProgress);
    } finally {
      control.stop();
      _downloads.remove(initial.id);
    }
  }

  Future<OfflineArea> _download(
    OfflineArea initial,
    TilePlan plan,
    MapProviderConfig activeConfig,
    _DownloadControl control,
    void Function(OfflineArea) onProgress,
  ) async {
    final state = await _providerState(activeConfig.id);
    var area = _copyArea(
      initial,
      status: OfflineAreaStatus.downloading,
      lastError: null,
    );
    await repository.saveOfflineArea(area);
    onProgress(area);

    var completed = 0;
    var bytes = 0;
    var nextIndex = 0;
    Object? firstError;

    Future<void> worker() async {
      while (nextIndex < plan.coordinates.length && !control.stopped) {
        final coordinate = plan.coordinates[nextIndex++];
        try {
          final tileBytes = await _downloadTile(
            area,
            coordinate,
            activeConfig,
            state,
            control,
          );
          completed++;
          bytes += tileBytes;
          area = _copyArea(area, completedTiles: completed, actualBytes: bytes);
          await repository.saveOfflineArea(area);
          onProgress(area);
        } on _DownloadStopped {
          return;
        } on Object catch (error) {
          firstError ??= error;
          control.stop();
        }
      }
    }

    await Future.wait(
      List.generate(
        activeConfig.downloadPolicy.maxConcurrentRequests,
        (_) => worker(),
      ),
    );
    if (control.cancelled) {
      area = _copyArea(area, status: OfflineAreaStatus.paused);
    } else if (firstError != null) {
      area = _copyArea(
        area,
        status: firstError is _DownloadDeferred
            ? OfflineAreaStatus.paused
            : OfflineAreaStatus.failed,
        lastError: firstError.toString(),
      );
    } else {
      area = _copyArea(area, status: OfflineAreaStatus.complete);
    }
    await repository.saveOfflineArea(area);
    onProgress(area);
    return area;
  }

  Future<int> _downloadTile(
    OfflineArea area,
    TileCoordinate coordinate,
    MapProviderConfig activeConfig,
    _ProviderDownloadState state,
    _DownloadControl control,
  ) async {
    final namespace = offlineTileNamespace(
      activeConfig.id,
      OfflineSourceFormat.rasterTiles,
    );
    final file = store.fileFor(
      namespace,
      coordinate.z,
      coordinate.x,
      coordinate.y,
    );
    if (!await file.exists()) {
      await file.parent.create(recursive: true);
      http.Response? response;
      Object? lastError;
      for (var attempt = 0; attempt < 3; attempt++) {
        await _waitForRequest(state, activeConfig.downloadPolicy, control);
        response = null;
        try {
          response = await _client
              .get(
                activeConfig.tileUri(coordinate.z, coordinate.x, coordinate.y),
                headers: {'User-Agent': 'TrailRunner/1.0'},
              )
              .timeout(const Duration(seconds: 15));
        } on Object catch (error) {
          if (error is! TimeoutException &&
              error is! SocketException &&
              error is! http.ClientException) {
            rethrow;
          }
          lastError = error;
        }
        if (response != null) {
          if (response.statusCode == 200 &&
              response.bodyBytes.isNotEmpty &&
              (response.headers['content-type']?.startsWith('image/') ??
                  false)) {
            if (state.cooldownUntil == null ||
                !clock.nowUtc().isBefore(state.cooldownUntil!)) {
              state.rateLimitFailures = 0;
            }
            break;
          }
          lastError = HttpException(
            'Tile request returned HTTP ${response.statusCode}.',
          );
          if (response.statusCode == 401 || response.statusCode == 403) {
            throw _DownloadDeferred(
              'The provider refused the download (HTTP ${response.statusCode}). '
              'Check provider permission before resuming.',
            );
          }
          if (response.statusCode != 408 &&
              response.statusCode != 429 &&
              response.statusCode < 500) {
            throw lastError;
          }
          await _recordCooldown(state, activeConfig, response, attempt);
          control.ensureActive();
          if (attempt == 2 && response.statusCode == 429) {
            throw _DownloadDeferred(
              'The provider is rate-limiting downloads. Resume after '
              '${state.cooldownUntil!.toIso8601String()} (UTC).',
            );
          }
        } else if (attempt < 2) {
          await control.wait(
            activeConfig.downloadPolicy.retryBaseDelay * (1 << attempt),
          );
        }
        control.ensureActive();
        if (attempt == 2) throw lastError!;
      }
      if (response == null ||
          response.statusCode != 200 ||
          response.bodyBytes.isEmpty ||
          !(response.headers['content-type']?.startsWith('image/') ?? false)) {
        throw lastError ?? const HttpException('Tile download failed.');
      }
      final temporary = File('${file.path}.part');
      await temporary.writeAsBytes(response.bodyBytes, flush: true);
      await temporary.rename(file.path);
    }

    final length = await file.length();
    final key = '$namespace/${coordinate.key}';
    await repository.attachTile(
      areaId: area.id,
      tileKey: key,
      providerId: namespace,
      zoom: coordinate.z,
      x: coordinate.x,
      y: coordinate.y,
      relativePath: store.relativePath(file),
      byteCount: length,
    );
    return length;
  }

  Future<_ProviderDownloadState> _providerState(String providerId) async {
    final loading = _providers.putIfAbsent(providerId, () async {
      final saved = await repository.loadSetting(_cooldownKey(providerId));
      return _ProviderDownloadState(
        saved == null ? null : DateTime.parse(saved).toUtc(),
      );
    });
    try {
      return await loading;
    } on Object {
      _providers.remove(providerId);
      rethrow;
    }
  }

  String _cooldownKey(String providerId) =>
      'raster_download_cooldown_v1:$providerId';

  Future<void> _waitForRequest(
    _ProviderDownloadState state,
    RasterDownloadPolicy policy,
    _DownloadControl control,
  ) async {
    while (true) {
      control.ensureActive();
      final now = clock.nowUtc();
      var readyAt = state.nextRequestAt ?? now;
      if (state.cooldownUntil != null &&
          state.cooldownUntil!.isAfter(readyAt)) {
        readyAt = state.cooldownUntil!;
      }
      final delay = readyAt.difference(now);
      if (delay > policy.maxAutomaticWait) {
        throw _DownloadDeferred(
          'The provider requested a cooldown. Resume after '
          '${readyAt.toIso8601String()} (UTC).',
        );
      }
      if (delay > Duration.zero) {
        await control.wait(delay);
        continue;
      }
      state.requestsInBatch++;
      var interval = policy.minimumRequestInterval;
      if (state.requestsInBatch >= policy.requestsPerBatch) {
        state.requestsInBatch = 0;
        if (policy.batchPause > interval) interval = policy.batchPause;
      }
      state.nextRequestAt = now.add(interval);
      return;
    }
  }

  Future<void> _recordCooldown(
    _ProviderDownloadState state,
    MapProviderConfig activeConfig,
    http.Response response,
    int attempt,
  ) async {
    final policy = activeConfig.downloadPolicy;
    var delay = policy.retryBaseDelay * (1 << attempt);
    if (response.statusCode == 429) {
      delay =
          policy.rateLimitBaseDelay *
          (1 << state.rateLimitFailures.clamp(0, 3));
      state.rateLimitFailures++;
    }
    final now = clock.nowUtc();
    var deadline = now.add(delay);
    final retryAfter = response.headers['retry-after'];
    if (retryAfter != null) {
      final seconds = int.tryParse(retryAfter.trim());
      DateTime? requested;
      if (seconds != null && seconds >= 0) {
        requested = now.add(Duration(seconds: seconds));
      } else {
        try {
          requested = HttpDate.parse(retryAfter);
        } on HttpException {
          requested = null;
        } on FormatException {
          requested = null;
        }
      }
      if (requested != null && requested.isAfter(deadline)) {
        deadline = requested;
      }
    }
    if (state.cooldownUntil == null || deadline.isAfter(state.cooldownUntil!)) {
      state.cooldownUntil = deadline;
    }
    final saving = state.pendingSave.then(
      (_) => repository.saveSetting(
        _cooldownKey(activeConfig.id),
        state.cooldownUntil!.toIso8601String(),
      ),
    );
    state.pendingSave = saving.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    await saving;
  }

  OfflineArea _copyArea(
    OfflineArea area, {
    OfflineAreaStatus? status,
    int? completedTiles,
    int? actualBytes,
    String? lastError,
  }) {
    return OfflineArea(
      id: area.id,
      name: area.name,
      bounds: area.bounds,
      minZoom: area.minZoom,
      maxZoom: area.maxZoom,
      providerId: area.providerId,
      status: status ?? area.status,
      totalTiles: area.totalTiles,
      completedTiles: completedTiles ?? area.completedTiles,
      actualBytes: actualBytes ?? area.actualBytes,
      createdAt: area.createdAt,
      updatedAt: clock.nowUtc(),
      lastError: lastError,
      sourceFormat: area.sourceFormat,
    );
  }
}

class _ProviderDownloadState {
  _ProviderDownloadState(this.cooldownUntil);

  DateTime? cooldownUntil;
  DateTime? nextRequestAt;
  int requestsInBatch = 0;
  int rateLimitFailures = 0;
  Future<void> pendingSave = Future<void>.value();
}

class _DownloadControl {
  bool stopped = false;
  bool cancelled = false;
  final Map<Timer, Completer<void>> _waits = {};

  void stop({bool cancelled = false}) {
    this.cancelled = this.cancelled || cancelled;
    stopped = true;
    for (final entry in _waits.entries) {
      entry.key.cancel();
      if (!entry.value.isCompleted) entry.value.complete();
    }
    _waits.clear();
  }

  void ensureActive() {
    if (stopped) throw const _DownloadStopped();
  }

  Future<void> wait(Duration duration) async {
    ensureActive();
    if (duration <= Duration.zero) return;
    final wake = Completer<void>();
    final timer = Timer(duration, wake.complete);
    _waits[timer] = wake;
    try {
      await wake.future;
      ensureActive();
    } finally {
      timer.cancel();
      _waits.remove(timer);
    }
  }
}

class _DownloadStopped implements Exception {
  const _DownloadStopped();
}

class _DownloadDeferred implements Exception {
  const _DownloadDeferred(this.message);

  final String message;

  @override
  String toString() => message;
}
