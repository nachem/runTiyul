import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
import '../services/gpx_service.dart';
import '../services/location_service.dart';
import '../services/map_provider.dart';
import '../services/navigation_monitor.dart';
import '../services/offline_download_service.dart';
import '../services/route_trail_builder.dart';
import '../services/tile_store.dart';
import '../services/vector_area_conversion_service.dart';

class AppStore extends ChangeNotifier {
  static const _mapTileModeSetting = 'map_tile_mode';
  static const _activeMapLayerSetting = 'active_map_layer';
  static const _vectorSourceSetting = 'vector_source_url';
  static const _snapRoutesSetting = 'snap_routes_to_trails';
  static const _navAlertConfigSetting = 'nav_alert_config';

  AppStore._({
    required this.repository,
    required this.tileStore,
    required this.mapProvider,
    required this.downloader,
    required this.vectorConverter,
    required this.routeTrailBuilder,
  });

  final AppRepository repository;
  final TileStore tileStore;
  final MapProviderConfig mapProvider;
  final OfflineDownloadService downloader;
  final VectorAreaConversionService vectorConverter;
  final RouteTrailBuilder routeTrailBuilder;
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
  NavAlertConfig navAlertConfig = const NavAlertConfig();
  NavStatus navStatus = NavStatus.idle;
  TrailRoute? selectedRoute;
  OfflineArea? focusedOfflineArea;
  RunActivity? activeActivity;
  LatLng? currentLocation;
  bool loading = true;
  String? errorMessage;

  /// True when a vector map data source is configured (the in-app setting or the
  /// `TRAIL_VECTOR_MBTILES` build default), so offline areas are built by
  /// on-device vector-to-raster conversion.
  bool get usesVectorSource => vectorSourceUrl.isNotEmpty;

  /// Offline downloads are allowed when the raster provider permits them or a
  /// vector source is configured (whose data license permits offline use).
  bool get offlineDownloadsAllowed =>
      mapProvider.offlineDownloadsAllowed || usesVectorSource;

  /// The selectable base map layers: the configured downloadable provider plus
  /// any online-only imagery/basemap layers. Offline downloads always target
  /// [mapProvider]; the online-only layers are for viewing.
  List<MapProviderConfig> get baseLayers => [
    mapProvider,
    ...MapProviderConfig.onlineImageryLayers,
  ];

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
    );
    final store = AppStore._(
      repository: repository,
      tileStore: tileStore,
      mapProvider: provider,
      downloader: downloader,
      vectorConverter: vectorConverter,
      routeTrailBuilder: RouteTrailBuilder(),
    );
    await store.reload();
    return store;
  }

  static Future<AppStore> forTesting({
    required AppRepository repository,
    required TileStore tileStore,
    required MapProviderConfig mapProvider,
  }) async {
    final store = AppStore._(
      repository: repository,
      tileStore: tileStore,
      mapProvider: mapProvider,
      downloader: OfflineDownloadService(
        repository: repository,
        store: tileStore,
        config: mapProvider,
      ),
      vectorConverter: VectorAreaConversionService(
        repository: repository,
        store: tileStore,
        config: mapProvider,
      ),
      routeTrailBuilder: RouteTrailBuilder(),
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
      unawaited(HapticFeedback.heavyImpact());
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
  }) async {
    try {
      final plan = TilePlanner(
        maxTiles: maxTiles,
      ).plan(bounds, minZoom, maxZoom);
      final now = DateTime.now().toUtc();
      final area = OfflineArea(
        id: OfflineAreaId.generate().value,
        name: name.trim().isEmpty ? 'Offline area' : name.trim(),
        bounds: bounds,
        minZoom: minZoom,
        maxZoom: maxZoom,
        providerId: mapProvider.id,
        status: OfflineAreaStatus.planned,
        totalTiles: plan.tileCount,
        completedTiles: 0,
        actualBytes: 0,
        createdAt: now,
        updatedAt: now,
        sourceFormat: usesVectorSource
            ? OfflineSourceFormat.convertedVector
            : OfflineSourceFormat.rasterTiles,
      );
      await repository.saveOfflineArea(area);
      offlineAreas = [area, ...offlineAreas];
      notifyListeners();
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
  }) async {
    try {
      final plan = TilePlanner(
        maxTiles: maxTiles,
      ).plan(bounds, minZoom, maxZoom);
      downloader.cancel(area.id);
      vectorConverter.cancel(area.id);
      final updated = OfflineArea(
        id: area.id,
        name: name.trim().isEmpty ? 'Offline area' : name.trim(),
        bounds: bounds,
        minZoom: minZoom,
        maxZoom: maxZoom,
        providerId: mapProvider.id,
        status: OfflineAreaStatus.planned,
        totalTiles: plan.tileCount,
        completedTiles: 0,
        actualBytes: 0,
        createdAt: area.createdAt,
        updatedAt: DateTime.now().toUtc(),
        sourceFormat: usesVectorSource
            ? OfflineSourceFormat.convertedVector
            : OfflineSourceFormat.rasterTiles,
      );
      final retainedKeys = plan.coordinates
          .map((coordinate) => '${mapProvider.id}/${coordinate.key}')
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
    try {
      if (area.sourceFormat == OfflineSourceFormat.convertedVector) {
        await vectorConverter.convert(
          area,
          plan,
          onProgress: _replaceOfflineArea,
          sourceOverride: vectorSourceUrl,
        );
      } else {
        await downloader.download(area, plan, onProgress: _replaceOfflineArea);
      }
    } on Object catch (error) {
      _setError('Offline download failed: $error');
    }
  }

  void cancelDownload(OfflineArea area) {
    downloader.cancel(area.id);
    vectorConverter.cancel(area.id);
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
    downloader.dispose();
    super.dispose();
  }
}
