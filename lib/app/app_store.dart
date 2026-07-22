import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as p;

import '../core/geo/distance.dart';
import '../core/geo/geo_bounds.dart';
import '../core/geo/tile_math.dart';
import '../core/ids.dart';
import '../data/app_database.dart';
import '../data/app_repository.dart';
import '../models/offline_area.dart';
import '../models/run_activity.dart';
import '../models/trail_route.dart';
import '../services/app_version_service.dart';
import '../services/download_foreground_service.dart';
import '../services/gpx_service.dart';
import '../services/location_service.dart';
import '../services/map_provider.dart';
import '../services/navigation_alert_feedback.dart';
import '../services/navigation_monitor.dart';
import '../services/offline_download_service.dart';
import '../services/route_trail_builder.dart';
import '../services/tile_store.dart';
import '../services/trail_extractor.dart';
import '../services/vector_area_conversion_service.dart';
import '../services/vector_terrain_baker.dart';

class AppStore extends ChangeNotifier {
  static const _mapTileModeSetting = 'map_tile_mode';
  static const _activeMapLayerSetting = 'active_map_layer';
  static const _vectorSourceSetting = 'vector_source_url';
  static const _snapRoutesSetting = 'snap_routes_to_trails';
  static const _navAlertConfigSetting = 'nav_alert_config';
  static const _offlineAreaOrderSetting = 'offline_area_order';
  static const _legacyTerrainCleanupSetting = 'legacy_terrain_cleanup_v1';
  static const _lastAcknowledgedAppVersionSetting =
      'last_acknowledged_app_version';
  static const _publicRasterDevUnlockSetting =
      'public_raster_dev_downloads_unlocked';

  AppStore._({
    required this.repository,
    required this.tileStore,
    required this.appVersion,
    required this.mapProvider,
    required this.downloader,
    required this.vectorConverter,
    required this.routeTrailBuilder,
    required this.backgroundDownloads,
    required this._navigationAlertFeedback,
    required this._publicRasterDevUnlockCompiled,
  });

  final AppRepository repository;
  final TileStore tileStore;
  final AppVersionInfo appVersion;
  final MapProviderConfig mapProvider;
  final OfflineDownloadService downloader;
  final VectorAreaConversionService vectorConverter;
  final RouteTrailBuilder routeTrailBuilder;

  /// Keeps downloads alive while the app is backgrounded (an Android foreground
  /// service; a no-op on other platforms).
  final DownloadForegroundService backgroundDownloads;
  final NavigationAlertFeedback _navigationAlertFeedback;
  final bool _publicRasterDevUnlockCompiled;
  final GpxService _gpxService = const GpxService();
  final LocationService _locationService = const LocationService();
  final GeoDistance _distance = const GeoDistance();
  final NavigationMonitor _navMonitor = NavigationMonitor();

  List<TrailRoute> routes = [];
  List<RunActivity> activities = [];
  List<OfflineArea> offlineAreas = [];
  MapTileMode mapTileMode = MapTileMode.auto;
  String activeMapLayerId = '';
  String vectorSourceUrl = '';
  bool snapRoutesToTrails = true;
  bool publicRasterDevDownloadsUnlocked = false;
  String? previousAppVersion;

  /// APP-006: true when this installation has moved to a different app build.
  bool get hasPendingAppUpdate => previousAppVersion != null;

  NavAlertConfig navAlertConfig = const NavAlertConfig();
  NavStatus navStatus = NavStatus.idle;
  TrailRoute? selectedRoute;
  OfflineArea? focusedOfflineArea;
  RunActivity? activeActivity;
  LatLng? currentLocation;
  bool loading = true;
  String? errorMessage;

  /// Areas the app currently wants downloaded: added when a download starts and
  /// removed once it completes or the user pauses it. A failed or interrupted
  /// area stays here so it can be auto-resumed when the app next returns to the
  /// foreground.
  final Set<String> _intendedDownloads = {};

  /// Areas whose download loop is in flight on this isolate right now.
  final Set<String> _runningDownloads = {};

  /// Whether the keep-alive foreground service is currently requested.
  bool _backgroundServiceActive = false;

  /// True when a vector map data source is configured (the in-app setting or the
  /// `TRAIL_VECTOR_MBTILES` build default), so offline areas are built by
  /// on-device vector-to-raster conversion.
  bool get usesVectorSource => vectorSourceUrl.isNotEmpty;

  /// Offline downloads are allowed when at least one raster provider is enabled
  /// for this build or a vector source is configured.
  bool get offlineDownloadsAllowed =>
      rasterDownloadProviders.isNotEmpty || usesVectorSource;

  /// The source format used when a download does not choose one explicitly:
  /// on-device vector conversion when a vector source is configured, otherwise a
  /// per-tile raster download.
  OfflineSourceFormat get _defaultSourceFormat => usesVectorSource
      ? OfflineSourceFormat.convertedVector
      : OfflineSourceFormat.rasterTiles;

  /// The selectable online base maps. CyclOSM includes provider-rendered
  /// contours and hillshade, so viewing it never downloads separate height data.
  List<MapProviderConfig> get baseLayers {
    final candidates = [
      mapProvider,
      MapProviderConfig.cyclOsm(),
      ...MapProviderConfig.onlineImageryLayers,
    ];
    final seen = <String>{};
    return [
      for (final layer in candidates)
        if (seen.add(layer.id)) layer,
    ];
  }

  /// Whether this build can expose the seven-tap internal-release unlock.
  bool get publicRasterDevUnlockAvailable =>
      _publicRasterDevUnlockCompiled && !publicRasterDevDownloadsUnlocked;

  /// Raster sources currently allowed for area download. Debug providers carry
  /// their permission directly; an internal release can grant the same local
  /// policy after the persisted developer unlock is confirmed.
  List<MapProviderConfig> get rasterDownloadProviders => [
    for (final layer in baseLayers)
      if (layer.offlineDownloadsAllowed)
        layer
      else if (publicRasterDevDownloadsUnlocked &&
          layer.isPublicDevelopmentRaster)
        layer.withDevelopmentDownloadEnabled(),
  ];

  /// Resolves a persisted provider id to the current provider configuration.
  MapProviderConfig? mapProviderById(String id) {
    for (final layer in rasterDownloadProviders) {
      if (layer.id == id) return layer;
    }
    for (final layer in baseLayers) {
      if (layer.id == id) return layer;
    }
    return null;
  }

  /// The base layer currently shown for online rendering and attribution.
  /// Defaults to [mapProvider] when nothing valid is selected.
  MapProviderConfig get activeMapLayer => baseLayers.firstWhere(
    (layer) => layer.id == activeMapLayerId,
    orElse: () => mapProvider,
  );

  StreamSubscription<Position>? _positionSubscription;
  Timer? _elapsedTimer;
  List<LatLng> _navRoute = const [];
  List<LatLng> _navJunctions = const [];

  static Future<AppStore> create() async {
    final repository = AppRepository(AppDatabase());
    final tileStore = await TileStore.create();
    final appVersion = await const AppVersionService().load();
    final provider = MapProviderConfig.fromEnvironment();
    final downloader = OfflineDownloadService(
      repository: repository,
      store: tileStore,
      config: provider,
    );
    final vectorConverter = VectorAreaConversionService(
      repository: repository,
      store: tileStore,
      config: provider,
      terrainBaker: TerrariumVectorTerrainBaker(
        config: MapProviderConfig.terrainSource(),
      ),
    );
    final store = AppStore._(
      repository: repository,
      tileStore: tileStore,
      appVersion: appVersion,
      mapProvider: provider,
      downloader: downloader,
      vectorConverter: vectorConverter,
      routeTrailBuilder: RouteTrailBuilder(
        // Route snapping and Follow-trails routing use trails plus roads of any
        // kind, so a route can stitch onto residential streets and service
        // roads as well as paths and tracks.
        extractor: const TrailExtractor(
          trailClasses: TrailExtractor.trailAndRoadClasses,
        ),
      ),
      backgroundDownloads: DownloadForegroundService(),
      navigationAlertFeedback: NavigationAlertFeedback.device(),
      publicRasterDevUnlockCompiled:
          MapProviderConfig.publicRasterDevUnlockCompiled,
    );
    await store.reload();
    return store;
  }

  static Future<AppStore> forTesting({
    required AppRepository repository,
    required TileStore tileStore,
    required MapProviderConfig mapProvider,
    AppVersionInfo appVersion = const AppVersionInfo(
      appName: 'RunTiyul',
      packageName: 'com.bernoulli.trailrunner.trail_runner',
      version: '0.0.0',
      buildNumber: '0',
    ),
    OfflineDownloadService? downloader,
    VectorAreaConversionService? vectorConverter,
    DownloadForegroundService? backgroundDownloads,
    NavigationAlertFeedback? navigationAlertFeedback,
    bool publicRasterDevUnlockCompiled = false,
  }) async {
    final store = AppStore._(
      repository: repository,
      tileStore: tileStore,
      appVersion: appVersion,
      mapProvider: mapProvider,
      downloader:
          downloader ??
          OfflineDownloadService(
            repository: repository,
            store: tileStore,
            config: mapProvider,
          ),
      vectorConverter:
          vectorConverter ??
          VectorAreaConversionService(
            repository: repository,
            store: tileStore,
            config: mapProvider,
          ),
      routeTrailBuilder: RouteTrailBuilder(
        extractor: const TrailExtractor(
          trailClasses: TrailExtractor.trailAndRoadClasses,
        ),
      ),
      backgroundDownloads: backgroundDownloads ?? DownloadForegroundService(),
      navigationAlertFeedback:
          navigationAlertFeedback ?? NavigationAlertFeedback.silent(),
      publicRasterDevUnlockCompiled: publicRasterDevUnlockCompiled,
    );
    await store.reload();
    return store;
  }

  Future<void> reload() async {
    loading = true;
    notifyListeners();
    try {
      routes = await repository.loadRoutes();
      activities = await repository.loadActivities();
      offlineAreas = await repository.loadOfflineAreas();
      offlineAreas = await _applySavedOfflineOrder(offlineAreas);
      await _cleanupLegacyTerrainStorage();
      await _loadAppVersionState();
      final savedMapMode = await repository.loadSetting(_mapTileModeSetting);
      mapTileMode =
          MapTileMode.values
              .where((mode) => mode.name == savedMapMode)
              .firstOrNull ??
          MapTileMode.auto;
      final savedLayer = await repository.loadSetting(_activeMapLayerSetting);
      activeMapLayerId =
          (savedLayer != null &&
              baseLayers.any((layer) => layer.id == savedLayer))
          ? savedLayer
          : mapProvider.id;
      final savedVectorSource = await repository.loadSetting(
        _vectorSourceSetting,
      );
      vectorSourceUrl =
          (savedVectorSource != null && savedVectorSource.isNotEmpty)
          ? savedVectorSource
          : mapProvider.vectorSourceUrl;
      final savedSnap = await repository.loadSetting(_snapRoutesSetting);
      snapRoutesToTrails = savedSnap == null ? true : savedSnap == 'true';
      final savedPublicRasterUnlock = await repository.loadSetting(
        _publicRasterDevUnlockSetting,
      );
      publicRasterDevDownloadsUnlocked =
          _publicRasterDevUnlockCompiled && savedPublicRasterUnlock == 'true';
      final savedNav = await repository.loadSetting(_navAlertConfigSetting);
      if (savedNav != null && savedNav.isNotEmpty) {
        try {
          navAlertConfig = NavAlertConfig.fromJson(
            jsonDecode(savedNav) as Map<String, dynamic>,
          );
        } on Object {
          navAlertConfig = const NavAlertConfig();
        }
      }
      _navMonitor.config = navAlertConfig;
      for (var index = 0; index < offlineAreas.length; index++) {
        final area = offlineAreas[index];
        if (area.status != OfflineAreaStatus.downloading) continue;
        final recovered = OfflineArea(
          id: area.id,
          name: area.name,
          bounds: area.bounds,
          minZoom: area.minZoom,
          maxZoom: area.maxZoom,
          providerId: area.providerId,
          status: OfflineAreaStatus.paused,
          totalTiles: area.totalTiles,
          completedTiles: area.completedTiles,
          actualBytes: area.actualBytes,
          createdAt: area.createdAt,
          updatedAt: DateTime.now().toUtc(),
          lastError: 'Download was interrupted and can be resumed.',
          sourceFormat: area.sourceFormat,
        );
        offlineAreas[index] = recovered;
        await repository.saveOfflineArea(recovered);
      }
      activeActivity = activities
          .where((activity) => activity.status != ActivityStatus.completed)
          .firstOrNull;
      if (activeActivity != null &&
          activeActivity!.status == ActivityStatus.recording) {
        activeActivity = activeActivity!.copyWith(
          status: ActivityStatus.paused,
        );
        await repository.updateActivity(activeActivity!);
      }
      errorMessage = null;
    } on Object catch (error) {
      errorMessage = 'Could not load local data: $error';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void selectRoute(TrailRoute? route) {
    selectedRoute = route;
    if (route != null) focusedOfflineArea = null;
    notifyListeners();
  }

  void focusOfflineArea(OfflineArea? area) {
    focusedOfflineArea = area;
    notifyListeners();
  }

  Future<void> acknowledgeAppUpdate() async {
    try {
      await repository.saveSetting(
        _lastAcknowledgedAppVersionSetting,
        appVersion.identity,
      );
      previousAppVersion = null;
      notifyListeners();
    } on Object catch (error) {
      _setError('Could not save the installed app version: $error');
    }
  }

  Future<void> importGpx() async {
    try {
      var route = await _gpxService.pickAndImport();
      if (routes.any((existing) => existing.name == route.name)) {
        route = TrailRoute(
          id: route.id,
          name: '${route.name} (${routes.length + 1})',
          source: route.source,
          createdAt: route.createdAt,
          updatedAt: route.updatedAt,
          points: route.points,
        );
      }
      await repository.saveRoute(route);
      routes = [route, ...routes];
      selectedRoute = route;
      errorMessage = null;
      notifyListeners();
    } on GpxImportCancelled {
      return;
    } on Object catch (error) {
      _setError('Could not import GPX: $error');
    }
  }

  Future<bool> saveManualRoute(String name, List<LatLng> points) async {
    if (points.length < 2) {
      _setError('A route needs at least two map points.');
      return false;
    }
    final trimmed = name.trim();
    final now = DateTime.now().toUtc();
    final route = TrailRoute(
      id: RouteId.generate().value,
      name: trimmed.isEmpty ? 'Route ${routes.length + 1}' : trimmed,
      source: RouteSource.manual,
      createdAt: now,
      updatedAt: now,
      points: points
          .map(
            (point) => RoutePoint(
              latitude: point.latitude,
              longitude: point.longitude,
            ),
          )
          .toList(),
    );
    try {
      await repository.saveRoute(route);
      routes = [route, ...routes];
      selectedRoute = route;
      errorMessage = null;
      notifyListeners();
      // Snapping to nearby trails needs the network, so it runs after the
      // route is saved and visible rather than blocking the save.
      if (snapRoutesToTrails && vectorSourceUrl.isNotEmpty) {
        unawaited(_snapSavedRoute(route, points));
      }
      return true;
    } on Object catch (error) {
      _setError('Could not save route: $error');
      return false;
    }
  }

  Future<void> _snapSavedRoute(TrailRoute route, List<LatLng> points) async {
    try {
      final result = await routeTrailBuilder.snapToTrails(
        points,
        vectorSourceUrl,
      );
      if (!result.changed || result.snapped.length < 2) return;
      final updated = TrailRoute(
        id: route.id,
        name: route.name,
        source: route.source,
        createdAt: route.createdAt,
        updatedAt: DateTime.now().toUtc(),
        points: result.snapped
            .map(
              (point) => RoutePoint(
                latitude: point.latitude,
                longitude: point.longitude,
              ),
            )
            .toList(),
      );
      await repository.saveRoute(updated);
      routes = routes
          .map((item) => item.id == updated.id ? updated : item)
          .toList();
      if (selectedRoute?.id == updated.id) selectedRoute = updated;
      notifyListeners();
    } on Object {
      // Best-effort: keep the drawn route if snapping fails.
    }
  }

  /// Replaces an existing route's name and waypoints in place, keeping its id,
  /// source, and creation time. Used by the editor when editing an existing
  /// route rather than creating a new one.
  Future<bool> updateManualRoute(
    TrailRoute original,
    String name,
    List<LatLng> points,
  ) async {
    if (points.length < 2) {
      _setError('A route needs at least two map points.');
      return false;
    }
    final trimmed = name.trim();
    final updated = TrailRoute(
      id: original.id,
      name: trimmed.isEmpty ? original.name : trimmed,
      source: original.source,
      createdAt: original.createdAt,
      updatedAt: DateTime.now().toUtc(),
      points: points
          .map(
            (point) => RoutePoint(
              latitude: point.latitude,
              longitude: point.longitude,
            ),
          )
          .toList(),
    );
    try {
      await repository.saveRoute(updated);
      routes = routes
          .map((item) => item.id == updated.id ? updated : item)
          .toList();
      if (selectedRoute?.id == updated.id) selectedRoute = updated;
      errorMessage = null;
      notifyListeners();
      if (snapRoutesToTrails && vectorSourceUrl.isNotEmpty) {
        unawaited(_snapSavedRoute(updated, points));
      }
      return true;
    } on Object catch (error) {
      _setError('Could not update route: $error');
      return false;
    }
  }

  Future<void> deleteRoute(TrailRoute route) async {
    try {
      await repository.deleteRoute(route.id);
      routes = routes.where((item) => item.id != route.id).toList();
      if (selectedRoute?.id == route.id) selectedRoute = null;
      notifyListeners();
    } on Object catch (error) {
      _setError('Could not delete route: $error');
    }
  }

  Future<void> renameRoute(TrailRoute route, String name) async {
    if (name.trim().isEmpty) {
      _setError('Route name cannot be empty.');
      return;
    }
    final updated = TrailRoute(
      id: route.id,
      name: name.trim(),
      source: route.source,
      createdAt: route.createdAt,
      updatedAt: DateTime.now().toUtc(),
      points: route.points,
      distanceMeters: route.distanceMeters,
    );
    try {
      await repository.saveRoute(updated);
      routes = routes
          .map((item) => item.id == updated.id ? updated : item)
          .toList();
      if (selectedRoute?.id == updated.id) selectedRoute = updated;
      notifyListeners();
    } on Object catch (error) {
      _setError('Could not rename route: $error');
    }
  }

  Future<void> duplicateRoute(TrailRoute route) async {
    final now = DateTime.now().toUtc();
    final duplicate = TrailRoute(
      id: RouteId.generate().value,
      name: '${route.name} copy',
      source: route.source,
      createdAt: now,
      updatedAt: now,
      points: route.points,
      distanceMeters: route.distanceMeters,
    );
    try {
      await repository.saveRoute(duplicate);
      routes = [duplicate, ...routes];
      selectedRoute = duplicate;
      notifyListeners();
    } on Object catch (error) {
      _setError('Could not duplicate route: $error');
    }
  }

  Future<void> locate() async {
    try {
      final position = await _locationService.current();
      currentLocation = LatLng(position.latitude, position.longitude);
      errorMessage = null;
      notifyListeners();
    } on Object catch (error) {
      _setError('Location unavailable: $error');
    }
  }

  Future<void> setMapTileMode(MapTileMode mode) async {
    try {
      await repository.saveSetting(_mapTileModeSetting, mode.name);
      mapTileMode = mode;
      errorMessage = null;
      notifyListeners();
    } on Object catch (error) {
      _setError('Could not save the map source: $error');
    }
  }

  /// Persists which base map layer is shown for online rendering. Only affects
  /// the displayed online tiles and attribution; offline coverage and downloads
  /// stay bound to [mapProvider].
  Future<void> setActiveMapLayer(String layerId) async {
    if (!baseLayers.any((layer) => layer.id == layerId)) return;
    if (layerId == activeMapLayerId) return;
    try {
      await repository.saveSetting(_activeMapLayerSetting, layerId);
      activeMapLayerId = layerId;
      errorMessage = null;
      notifyListeners();
    } on Object catch (error) {
      _setError('Could not save the map layer: $error');
    }
  }

  /// Persists the vector map data source (an MBTiles URL or local path). When
  /// set, offline areas are downloaded as free vector data and converted to
  /// raster tiles on the device.
  Future<void> setVectorSourceUrl(String url) async {
    try {
      final trimmed = url.trim();
      await repository.saveSetting(_vectorSourceSetting, trimmed);
      vectorSourceUrl = trimmed;
      errorMessage = null;
      notifyListeners();
    } on Object catch (error) {
      _setError('Could not save the map data source: $error');
    }
  }

  /// Permanently enables public-raster development downloads on this device for
  /// an explicitly compiled internal-release build. Returns false in normal
  /// release builds, where the capability does not exist.
  Future<bool> enablePublicRasterDevDownloads() async {
    if (!_publicRasterDevUnlockCompiled) return false;
    try {
      await repository.saveSetting(_publicRasterDevUnlockSetting, 'true');
      publicRasterDevDownloadsUnlocked = true;
      errorMessage = null;
      notifyListeners();
      return true;
    } on Object catch (error) {
      _setError('Could not enable developer raster downloads: $error');
      return false;
    }
  }

  /// Persists whether saved routes are snapped onto nearby real trails.
  Future<void> setSnapRoutesToTrails(bool value) async {
    try {
      await repository.saveSetting(_snapRoutesSetting, '$value');
      snapRoutesToTrails = value;
      notifyListeners();
    } on Object catch (error) {
      _setError('Could not save the snap setting: $error');
    }
  }

  /// Persists the live navigation alert configuration.
  Future<void> setNavAlertConfig(NavAlertConfig config) async {
    try {
      await repository.saveSetting(
        _navAlertConfigSetting,
        jsonEncode(config.toJson()),
      );
      navAlertConfig = config;
      _navMonitor.config = config;
      notifyListeners();
    } on Object catch (error) {
      _setError('Could not save alert settings: $error');
    }
  }

  /// Plays a representative alert with the settings currently shown in the UI.
  Future<NavigationFeedbackResult> previewNavigationAlert(
    NavAlert alert, {
    NavAlertConfig? config,
  }) {
    final effectiveConfig = config ?? navAlertConfig;
    final status = switch (alert) {
      NavAlert.offRoute => NavStatus(
        offRoute: true,
        distanceToRouteMeters: effectiveConfig.offRouteMeters + 10,
        triggered: alert,
      ),
      NavAlert.junction => NavStatus(
        offRoute: false,
        junctionDistanceMeters: effectiveConfig.junctionMeters,
        junctionTurn: TurnDirection.left,
        triggered: alert,
      ),
      NavAlert.none => NavStatus.idle,
    };
    return _navigationAlertFeedback.notify(
      status,
      mode: effectiveConfig.feedbackMode,
    );
  }

  Future<void> startActivity() async {
    if (activeActivity != null) {
      _setError('Finish or discard the current activity first.');
      return;
    }
    try {
      await _locationService.ensurePermission();
      final activity = RunActivity(
        id: ActivityId.generate().value,
        routeId: selectedRoute?.id,
        status: ActivityStatus.recording,
        startedAt: DateTime.now().toUtc(),
        elapsed: Duration.zero,
        distanceMeters: 0,
        elevationGainMeters: 0,
        samples: const [],
      );
      await repository.createActivity(activity);
      activeActivity = activity;
      activities = [activity, ...activities];
      _beginNavigation();
      _startLocationStream();
      _startElapsedTimer();
      errorMessage = null;
      notifyListeners();
    } on Object catch (error) {
      _setError('Could not start recording: $error');
    }
  }

  Future<void> pauseActivity() async {
    final activity = activeActivity;
    if (activity == null || activity.status != ActivityStatus.recording) return;
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    _elapsedTimer?.cancel();
    activeActivity = activity.copyWith(status: ActivityStatus.paused);
    await repository.updateActivity(activeActivity!);
    _replaceActivity(activeActivity!);
  }

  Future<void> resumeActivity() async {
    final activity = activeActivity;
    if (activity == null || activity.status != ActivityStatus.paused) return;
    try {
      await _locationService.ensurePermission();
      activeActivity = activity.copyWith(status: ActivityStatus.recording);
      await repository.updateActivity(activeActivity!);
      _replaceActivity(activeActivity!);
      _beginNavigation();
      _startLocationStream();
      _startElapsedTimer();
    } on Object catch (error) {
      _setError('Could not resume recording: $error');
    }
  }

  Future<void> finishActivity() async {
    final activity = activeActivity;
    if (activity == null) return;
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    _elapsedTimer?.cancel();
    final completed = activity.copyWith(
      status: ActivityStatus.completed,
      endedAt: DateTime.now().toUtc(),
    );
    try {
      await repository.updateActivity(completed);
      _replaceActivity(completed);
      activeActivity = null;
      _endNavigation();
      notifyListeners();
    } on Object catch (error) {
      _setError('Could not finish activity: $error');
    }
  }

  Future<void> discardActivity() async {
    final activity = activeActivity;
    if (activity == null) return;
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    _elapsedTimer?.cancel();
    try {
      await repository.deleteActivity(activity.id);
      activities = activities.where((item) => item.id != activity.id).toList();
      activeActivity = null;
      _endNavigation();
      notifyListeners();
    } on Object catch (error) {
      _setError('Could not discard activity: $error');
    }
  }

  Future<void> deleteActivity(RunActivity activity) async {
    try {
      await repository.deleteActivity(activity.id);
      activities = activities.where((item) => item.id != activity.id).toList();
      notifyListeners();
    } on Object catch (error) {
      _setError('Could not delete activity: $error');
    }
  }

  Future<void> exportActivity(RunActivity activity) async {
    try {
      final exported = await _gpxService.exportActivity(activity);
      if (!exported) return;
      errorMessage = null;
      notifyListeners();
    } on Object catch (error) {
      _setError('Could not export activity: $error');
    }
  }

  void _startLocationStream() {
    _positionSubscription?.cancel();
    _positionSubscription = _locationService.positions().listen(
      (position) => unawaited(_acceptPosition(position)),
      onError: (Object error) => _setError('GPS stream failed: $error'),
    );
  }

  void _beginNavigation() {
    _navMonitor
      ..config = navAlertConfig
      ..reset();
    navStatus = NavStatus.idle;
    final route = selectedRoute;
    _navRoute = route == null
        ? const []
        : route.points.map((point) => point.latLng).toList(growable: false);
    _navJunctions = const [];
    if (route != null &&
        _navRoute.length >= 2 &&
        vectorSourceUrl.isNotEmpty &&
        navAlertConfig.junctionEnabled) {
      unawaited(_loadJunctions(_navRoute));
    }
  }

  Future<void> _loadJunctions(List<LatLng> route) async {
    try {
      final network = await routeTrailBuilder.buildNetwork(
        route,
        vectorSourceUrl,
      );
      _navJunctions = network.junctions();
    } on Object {
      // Junction alerts are best-effort; ignore fetch/parse failures.
    }
  }

  void _endNavigation() {
    _navRoute = const [];
    _navJunctions = const [];
    navStatus = NavStatus.idle;
    _navMonitor.reset();
  }

  void _updateNavigation(LatLng position) {
    if (_navRoute.length < 2) return;
    navStatus = _navMonitor.update(
      position,
      route: _navRoute,
      junctions: _navJunctions,
    );
    if (navStatus.triggered == NavAlert.offRoute ||
        navStatus.triggered == NavAlert.junction) {
      unawaited(
        _navigationAlertFeedback.notify(
          navStatus,
          mode: navAlertConfig.feedbackMode,
        ),
      );
    }
  }

  void _startElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final activity = activeActivity;
      if (activity == null || activity.status != ActivityStatus.recording) {
        return;
      }
      activeActivity = activity.copyWith(
        elapsed: activity.elapsed + const Duration(seconds: 1),
      );
      _replaceActivity(activeActivity!, persist: false);
      if (activeActivity!.elapsed.inSeconds % 10 == 0) {
        unawaited(repository.updateActivity(activeActivity!));
      }
    });
  }

  Future<void> _acceptPosition(Position position) async {
    final activity = activeActivity;
    if (activity == null || activity.status != ActivityStatus.recording) return;
    if (!position.accuracy.isFinite || position.accuracy > 60) return;

    final previous = activity.samples.lastOrNull;
    var addedDistance = 0.0;
    var addedElevation = 0.0;
    if (previous != null) {
      addedDistance = _distance.metersBetween(
        previous.latLng,
        LatLng(position.latitude, position.longitude),
      );
      if (addedDistance > 200) return;
      final previousAltitude = previous.altitude;
      if (previousAltitude != null) {
        final delta = position.altitude - previousAltitude;
        if (delta > 1 && delta < 50) addedElevation = delta;
      }
    }
    final sample = ActivitySample(
      latitude: position.latitude,
      longitude: position.longitude,
      recordedAt: position.timestamp.toUtc(),
      accuracy: position.accuracy,
      altitude: position.altitude,
      speed: position.speed >= 0 ? position.speed : null,
      heading: position.heading >= 0 ? position.heading : null,
    );
    final updated = activity.copyWith(
      distanceMeters: activity.distanceMeters + addedDistance,
      elevationGainMeters: activity.elevationGainMeters + addedElevation,
      samples: [...activity.samples, sample],
    );
    currentLocation = sample.latLng;
    _updateNavigation(sample.latLng);
    activeActivity = updated;
    _replaceActivity(updated, persist: false);
    try {
      await repository.appendActivitySample(updated, sample);
    } on Object catch (error) {
      await pauseActivity();
      _setError(
        'Recording was paused because a sample could not be saved: $error',
      );
    }
  }

  void _replaceActivity(RunActivity activity, {bool persist = true}) {
    activities = activities
        .map((item) => item.id == activity.id ? activity : item)
        .toList();
    notifyListeners();
  }

  Future<void> createOfflineArea({
    required String name,
    required GeoBounds bounds,
    required int minZoom,
    required int maxZoom,
    int maxTiles = 1200,
    OfflineSourceFormat? format,
    String? providerId,
  }) async {
    try {
      final plan = TilePlanner(
        maxTiles: maxTiles,
      ).plan(bounds, minZoom, maxZoom);
      final now = DateTime.now().toUtc();
      final sourceFormat = format ?? _defaultSourceFormat;
      final sourceProviderId =
          sourceFormat == OfflineSourceFormat.convertedVector
          ? mapProvider.id
          : providerId ?? mapProvider.id;
      if (sourceFormat == OfflineSourceFormat.rasterTiles) {
        final rasterProvider = mapProviderById(sourceProviderId);
        if (rasterProvider == null || !rasterProvider.offlineDownloadsAllowed) {
          throw StateError(
            'Raster provider $sourceProviderId is not enabled for downloads.',
          );
        }
      }
      final area = OfflineArea(
        id: OfflineAreaId.generate().value,
        name: name.trim().isEmpty ? 'Offline area' : name.trim(),
        bounds: bounds,
        minZoom: minZoom,
        maxZoom: maxZoom,
        providerId: sourceProviderId,
        status: OfflineAreaStatus.planned,
        totalTiles: plan.tileCount,
        completedTiles: 0,
        actualBytes: 0,
        createdAt: now,
        updatedAt: now,
        sourceFormat: sourceFormat,
      );
      await repository.saveOfflineArea(area);
      offlineAreas = [area, ...offlineAreas];
      notifyListeners();
      unawaited(_persistOfflineAreaOrder());
      unawaited(_runDownload(area, plan));
    } on Object catch (error) {
      _setError('Could not create offline area: $error');
    }
  }

  Future<void> updateOfflineArea({
    required OfflineArea area,
    required String name,
    required GeoBounds bounds,
    required int minZoom,
    required int maxZoom,
    int maxTiles = 1200,
    OfflineSourceFormat? format,
    String? providerId,
  }) async {
    try {
      final plan = TilePlanner(
        maxTiles: maxTiles,
      ).plan(bounds, minZoom, maxZoom);
      downloader.cancel(area.id);
      vectorConverter.cancel(area.id);
      final sourceFormat = format ?? area.sourceFormat;
      final sourceProviderId =
          sourceFormat == OfflineSourceFormat.convertedVector
          ? mapProvider.id
          : providerId ?? area.providerId;
      if (sourceFormat == OfflineSourceFormat.rasterTiles) {
        final rasterProvider = mapProviderById(sourceProviderId);
        if (rasterProvider == null || !rasterProvider.offlineDownloadsAllowed) {
          throw StateError(
            'Raster provider $sourceProviderId is not enabled for downloads.',
          );
        }
      }
      final updated = OfflineArea(
        id: area.id,
        name: name.trim().isEmpty ? 'Offline area' : name.trim(),
        bounds: bounds,
        minZoom: minZoom,
        maxZoom: maxZoom,
        providerId: sourceProviderId,
        status: OfflineAreaStatus.planned,
        totalTiles: plan.tileCount,
        completedTiles: 0,
        actualBytes: 0,
        createdAt: area.createdAt,
        updatedAt: DateTime.now().toUtc(),
        sourceFormat: sourceFormat,
      );
      final namespace = offlineTileNamespace(
        updated.providerId,
        updated.sourceFormat,
      );
      final retainedKeys = plan.coordinates
          .map((coordinate) => '$namespace/${coordinate.key}')
          .toSet();
      final orphanPaths = await repository.replaceOfflineAreaPlan(
        updated,
        retainedKeys,
      );
      for (final relativePath in orphanPaths) {
        final file = File(p.join(tileStore.root.path, relativePath));
        if (await file.exists()) await file.delete();
      }
      _replaceOfflineArea(updated);
      focusedOfflineArea = updated;
      notifyListeners();
      unawaited(_runDownload(updated, plan));
    } on Object catch (error) {
      _setError('Could not update offline area: $error');
    }
  }

  Future<void> resumeDownload(OfflineArea area) async {
    try {
      final plan = const TilePlanner(
        maxTiles: 1200,
      ).plan(area.bounds, area.minZoom, area.maxZoom);
      await _runDownload(area, plan);
    } on Object catch (error) {
      _setError('Could not resume download: $error');
    }
  }

  Future<void> _runDownload(OfflineArea area, TilePlan plan) async {
    _intendedDownloads.add(area.id);
    _runningDownloads.add(area.id);
    _updateBackgroundService();
    try {
      final OfflineArea result;
      if (area.sourceFormat == OfflineSourceFormat.convertedVector) {
        result = await vectorConverter.convert(
          area,
          plan,
          onProgress: _replaceOfflineArea,
          sourceOverride: vectorSourceUrl,
        );
      } else {
        final rasterProvider = mapProviderById(area.providerId);
        if (rasterProvider == null) {
          throw StateError(
            'The saved raster provider ${area.providerId} is not configured.',
          );
        }
        result = await downloader.download(
          area,
          plan,
          provider: rasterProvider,
          onProgress: _replaceOfflineArea,
        );
      }
      // A completed area is done; a paused one was cancelled by the user. Both
      // should stop being auto-resumed. A failed/interrupted area stays intended
      // so it resumes when the app next returns to the foreground.
      if (result.status == OfflineAreaStatus.complete ||
          result.status == OfflineAreaStatus.paused) {
        _intendedDownloads.remove(area.id);
      }
    } on Object catch (error) {
      _setError('Offline download failed: $error');
    } finally {
      _runningDownloads.remove(area.id);
      _updateBackgroundService();
    }
  }

  void cancelDownload(OfflineArea area) {
    _intendedDownloads.remove(area.id);
    downloader.cancel(area.id);
    vectorConverter.cancel(area.id);
  }

  /// Resumes downloads that were interrupted (for example by the OS suspending
  /// the app in the background) but were not paused by the user. Safe to call
  /// repeatedly; it never resumes a completed area or one already in flight.
  Future<void> resumeInterruptedDownloads() async {
    final pending = _intendedDownloads
        .difference(_runningDownloads)
        .toList(growable: false);
    for (final id in pending) {
      final area = offlineAreas.where((item) => item.id == id).firstOrNull;
      if (area == null || area.status == OfflineAreaStatus.complete) {
        _intendedDownloads.remove(id);
        continue;
      }
      await resumeDownload(area);
    }
  }

  /// Starts the keep-alive foreground service while any download is running and
  /// stops it once none remain, so the OS keeps the process alive in the
  /// background only for as long as it is needed.
  void _updateBackgroundService() {
    final shouldRun = _runningDownloads.isNotEmpty;
    if (shouldRun == _backgroundServiceActive) return;
    _backgroundServiceActive = shouldRun;
    unawaited(
      shouldRun ? backgroundDownloads.start() : backgroundDownloads.stop(),
    );
  }

  Future<void> deleteOfflineArea(OfflineArea area) async {
    try {
      final unshared = await repository.unsharedTiles(area.id);
      for (final row in unshared) {
        final relative = row['relative_path']! as String;
        final file = File(p.join(tileStore.root.path, relative));
        if (await file.exists()) await file.delete();
      }
      await repository.deleteOfflineArea(area.id);
      offlineAreas = offlineAreas.where((item) => item.id != area.id).toList();
      if (focusedOfflineArea?.id == area.id) focusedOfflineArea = null;
      notifyListeners();
      unawaited(_persistOfflineAreaOrder());
    } on Object catch (error) {
      _setError('Could not delete offline area: $error');
    }
  }

  void _replaceOfflineArea(OfflineArea area) {
    offlineAreas = offlineAreas
        .map((item) => item.id == area.id ? area : item)
        .toList();
    if (focusedOfflineArea?.id == area.id) focusedOfflineArea = area;
    notifyListeners();
  }

  /// Reorders saved offline areas. Index 0 is the top area, drawn over the ones
  /// beneath it where they overlap on the map. [newIndex] is the target index
  /// after the moved item is removed (the `onReorderItem` convention).
  Future<void> reorderOfflineAreas(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= offlineAreas.length) return;
    final list = [...offlineAreas];
    final moved = list.removeAt(oldIndex);
    final target = newIndex.clamp(0, list.length);
    list.insert(target, moved);
    offlineAreas = list;
    notifyListeners();
    await _persistOfflineAreaOrder();
  }

  /// Applies the saved user ordering to [areas], keeping any areas absent from
  /// the saved order after the ordered ones.
  Future<List<OfflineArea>> _applySavedOfflineOrder(
    List<OfflineArea> areas,
  ) async {
    final saved = await repository.loadSetting(_offlineAreaOrderSetting);
    if (saved == null || saved.isEmpty) return areas;
    List<String> orderedIds;
    try {
      orderedIds = (jsonDecode(saved) as List).cast<String>();
    } on Object {
      return areas;
    }
    final byId = {for (final area in areas) area.id: area};
    final ordered = <OfflineArea>[];
    for (final id in orderedIds) {
      final area = byId.remove(id);
      if (area != null) ordered.add(area);
    }
    ordered.addAll(byId.values);
    return ordered;
  }

  Future<void> _loadAppVersionState() async {
    final savedVersion = await repository.loadSetting(
      _lastAcknowledgedAppVersionSetting,
    );
    if (savedVersion == null) {
      await repository.saveSetting(
        _lastAcknowledgedAppVersionSetting,
        appVersion.identity,
      );
      previousAppVersion = null;
      return;
    }
    previousAppVersion = savedVersion == appVersion.identity
        ? null
        : savedVersion;
  }

  Future<void> _persistOfflineAreaOrder() async {
    try {
      await repository.saveSetting(
        _offlineAreaOrderSetting,
        jsonEncode(offlineAreas.map((area) => area.id).toList()),
      );
    } on Object {
      // Ordering is a convenience; ignore persistence failures.
    }
  }

  /// Removes raw elevation data created by the superseded runtime contour
  /// overlay. Current topography is baked into converted vector PNGs, so neither
  /// the raw `aws-terrarium` files nor the browsing cache are needed anymore.
  Future<void> _cleanupLegacyTerrainStorage() async {
    final completed = await repository.loadSetting(
      _legacyTerrainCleanupSetting,
    );
    if (completed == 'true') return;
    try {
      final paths = await repository.removeTilesForProvider(
        MapProviderConfig.terrariumTerrain.id,
      );
      for (final relativePath in paths) {
        final file = File(p.join(tileStore.root.path, relativePath));
        if (await file.exists()) await file.delete();
      }
      for (final namespace in const ['aws-terrarium', 'aws-terrarium-cache']) {
        final directory = tileStore.dirFor(namespace);
        if (await directory.exists()) await directory.delete(recursive: true);
      }
      await repository.deleteSetting('show_contours');
      await repository.deleteSetting('terrain_cache_limit_bytes');
      await repository.saveSetting(_legacyTerrainCleanupSetting, 'true');
    } on Object {
      // Best effort and retryable: do not block app startup on cleanup failure.
    }
  }

  void clearError() {
    errorMessage = null;
    notifyListeners();
  }

  void _setError(String message) {
    errorMessage = message;
    notifyListeners();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _elapsedTimer?.cancel();
    if (_backgroundServiceActive) unawaited(backgroundDownloads.stop());
    unawaited(_navigationAlertFeedback.dispose());
    downloader.dispose();
    vectorConverter.dispose();
    super.dispose();
  }
}
