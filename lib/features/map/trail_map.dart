import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../app/app_store.dart';
import '../../core/geo/geo_bounds.dart';
import '../../core/geo/polyline_simplifier.dart';
import '../../models/offline_area.dart';
import '../../models/trail_route.dart';
import '../../services/map_provider.dart';
import '../../services/tile_store.dart';

class TrailMap extends StatefulWidget {
  const TrailMap({
    super.key,
    required this.store,
    this.route,
    this.routes = const [],
    this.track = const [],
    this.waypoints = const [],
    this.selection,
    this.selectionStart,
    this.onTap,
    this.onLongPress,
    this.highlightedWaypoint,
    this.trailOverlay = const [],
    this.waypointMarkers,
    this.onVisibleBoundsChanged,
    this.offlineOnly = false,
    this.initialCenter,
    this.initialZoom,
    this.showControls = false,
    this.controlsTop = 16,
    this.constrainOfflineZoom = true,
    this.autoFit = false,
    this.refitOnContentChange = true,
  });

  final AppStore store;
  final TrailRoute? route;
  final List<TrailRoute> routes;
  final List<LatLng> track;
  final List<LatLng> waypoints;
  final GeoBounds? selection;

  /// A point to highlight as the anchor/start corner of [selection] while the
  /// user is still defining the area (before the opposite corner is placed).
  final LatLng? selectionStart;
  final ValueChanged<LatLng>? onTap;

  /// Called with the long-pressed map point, used to select a waypoint to move
  /// or delete.
  final ValueChanged<LatLng>? onLongPress;

  /// Index of a waypoint to visually emphasize (for example the selected one).
  final int? highlightedWaypoint;

  /// Faint reference trails drawn beneath the route (the real trail network in
  /// follow-trails editing mode).
  final List<List<LatLng>> trailOverlay;

  /// When set, these are shown as the numbered markers instead of [waypoints],
  /// so the route line and its editable anchors can differ.
  final List<LatLng>? waypointMarkers;

  /// Reports the map's visible bounds as the camera settles, so callers can
  /// load data (such as trails) for the area in view.
  final void Function(GeoBounds bounds)? onVisibleBoundsChanged;

  final bool offlineOnly;
  final LatLng? initialCenter;
  final double? initialZoom;
  final bool showControls;
  final double controlsTop;
  final bool constrainOfflineZoom;

  /// When true, the camera fits the primary content (route, track, waypoints,
  /// or selection) once the map is laid out and, when [refitOnContentChange],
  /// again whenever that content changes.
  final bool autoFit;

  /// When false, [autoFit] only frames the content once on first layout and
  /// never re-fits as the content changes, so actively adding or moving points
  /// does not reset the user's zoom.
  final bool refitOnContentChange;

  @override
  State<TrailMap> createState() => _TrailMapState();
}

class _TrailMapState extends State<TrailMap> {
  late final MapController _controller;
  late LatLng _cameraCenter;
  late double _cameraZoom;
  late double _renderZoom;
  late bool _offlineCoverageAvailable;
  late String _lastAutoFitSignature;

  /// Neighborhood-level zoom used when the map opens centered on the runner's
  /// current position.
  static const double _locationZoom = 15;

  /// Whether saved trails/routes are drawn on the map (toggled from controls).
  bool _showTrails = true;

  /// True once the user pans or pinches the map, so the initial auto-center on
  /// the current location never overrides a deliberate interaction.
  bool _userInteracted = false;

  LatLng get _defaultCenter =>
      widget.initialCenter ??
      widget.store.currentLocation ??
      widget.route?.points.firstOrNull?.latLng ??
      widget.waypoints.firstOrNull ??
      const LatLng(31.7683, 35.2137);

  double get _defaultZoom {
    if (widget.initialZoom != null) return widget.initialZoom!;
    // When the map opens on the runner (no explicit target or content) and a
    // fix is already known, use a close, neighborhood-level zoom.
    if (_shouldAutoCenterOnLocation && widget.store.currentLocation != null) {
      return _locationZoom;
    }
    return _routePoints.isEmpty ? 11 : 13;
  }

  /// True when the map has no explicit camera target and no primary content, so
  /// it should open centered on the runner's current location instead of the
  /// fallback region.
  bool get _shouldAutoCenterOnLocation =>
      widget.initialCenter == null && !_hasPrimaryContent;

  List<LatLng> get _routePoints =>
      widget.route?.points.map((point) => point.latLng).toList() ??
      const <LatLng>[];

  MapTileMode get _tileMode =>
      widget.offlineOnly ? MapTileMode.offline : widget.store.mapTileMode;

  @override
  void initState() {
    super.initState();
    _controller = MapController();
    _cameraCenter = _defaultCenter;
    _cameraZoom = _defaultZoom;
    _renderZoom = _cameraZoom;
    _offlineCoverageAvailable = _hasOfflineCoverage(_cameraCenter, _cameraZoom);
    _lastAutoFitSignature = _contentSignature;
    if (widget.autoFit && _hasPrimaryContent) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fitContent(includeLocation: false);
      });
    } else if (_shouldAutoCenterOnLocation &&
        widget.store.currentLocation == null) {
      // Open on the runner's location: fetch a fix, then center on it at a
      // reasonable zoom unless the user has already moved the map.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_locateAndCenter());
      });
    }
  }

  @override
  void didUpdateWidget(covariant TrailMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    _offlineCoverageAvailable = _hasOfflineCoverage(_cameraCenter, _cameraZoom);
    _maybeAutoFit();
  }

  bool get _hasPrimaryContent =>
      _routePoints.isNotEmpty ||
      widget.track.isNotEmpty ||
      widget.waypoints.isNotEmpty ||
      (widget.selection != null && !widget.selection!.crossesAntimeridian);

  /// A stable fingerprint of the primary content so auto-fit only re-runs when
  /// the displayed route/track/waypoints/selection actually change, not on
  /// every rebuild (for example a live location update).
  String get _contentSignature {
    final selection = widget.selection;
    return [
      widget.route?.id ?? '',
      _routePoints.length,
      widget.track.length,
      widget.waypoints.length,
      selection == null
          ? ''
          : '${selection.north},${selection.south},'
                '${selection.east},${selection.west}',
      widget.store.focusedOfflineArea?.id ?? '',
    ].join('|');
  }

  void _maybeAutoFit() {
    if (!widget.autoFit) return;
    if (!widget.refitOnContentChange) return;
    final signature = _contentSignature;
    if (signature == _lastAutoFitSignature) return;
    _lastAutoFitSignature = signature;
    if (!_hasPrimaryContent) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fitContent(includeLocation: false);
    });
  }

  /// The attribution to show for the tiles currently on screen. Credits the
  /// active online layer when its tiles are visible, the saved provider (or a
  /// focused downloaded area's source) when showing saved tiles, and both when
  /// Auto layers a different online layer over the saved base.
  String get _attributionText {
    final activeLayer = widget.store.activeMapLayer;
    final focused = widget.store.focusedOfflineArea;

    if (_tileMode != MapTileMode.online && focused != null) {
      return _attributionForArea(focused);
    }

    final savedAttributions = _completedOfflineAreas
        .map(_attributionForArea)
        .toSet();

    switch (_tileMode) {
      case MapTileMode.offline:
        return savedAttributions.isEmpty
            ? widget.store.mapProvider.attribution
            : savedAttributions.join(' \u2022 ');
      case MapTileMode.online:
        return activeLayer.attribution;
      case MapTileMode.auto:
        return {activeLayer.attribution, ...savedAttributions}.join(' \u2022 ');
    }
  }

  String _attributionForProvider(String providerId) =>
      widget.store.mapProviderById(providerId)?.attribution ?? providerId;

  String _attributionForArea(OfflineArea area) {
    final base = _attributionForProvider(area.providerId);
    if (area.sourceFormat != OfflineSourceFormat.convertedVector) return base;
    return '$base \u2022 ${MapProviderConfig.terrainSource().attribution}';
  }

  bool _hasOfflineCoverage(LatLng center, double zoom) {
    final target = widget.store.currentLocation ?? center;
    final roundedZoom = zoom.round();
    return widget.store.offlineAreas.any(
      (area) =>
          area.status == OfflineAreaStatus.complete &&
          area.minZoom <= roundedZoom &&
          area.maxZoom >= roundedZoom &&
          area.bounds.contains(target),
    );
  }

  List<OfflineArea> get _completedOfflineAreas => widget.store.offlineAreas
      .where(
        (area) =>
            area.status == OfflineAreaStatus.complete &&
            !area.bounds.crossesAntimeridian,
      )
      .toList();

  /// Base-map areas whose saved tiles should render, in the user's top-first
  /// order. Includes in-progress downloads so their partial tiles still show;
  /// the ordered provider draws the top area over the ones beneath it.
  List<OfflineArea> get _renderableOfflineAreas => widget.store.offlineAreas
      .where((area) => !area.bounds.crossesAntimeridian)
      .toList();

  (double, double)? get _offlineZoomRange {
    final focusedArea = widget.store.focusedOfflineArea;
    if (focusedArea != null) {
      return (focusedArea.minZoom.toDouble(), focusedArea.maxZoom.toDouble());
    }
    final areas = _completedOfflineAreas;
    if (areas.isEmpty) return null;
    return (
      areas
          .map((area) => area.minZoom)
          .reduce((a, b) => a < b ? a : b)
          .toDouble(),
      areas
          .map((area) => area.maxZoom)
          .reduce((a, b) => a > b ? a : b)
          .toDouble(),
    );
  }

  void _updateCamera(MapCamera camera, bool hasGesture) {
    if (hasGesture) _userInteracted = true;
    final zoomChanged = (_cameraZoom - camera.zoom).abs() > 0.001;
    _cameraCenter = camera.center;
    _cameraZoom = camera.zoom;
    final renderZoomChanged = (_renderZoom - camera.zoom).abs() >= 0.75;
    if (renderZoomChanged) _renderZoom = camera.zoom;
    final available = _hasOfflineCoverage(_cameraCenter, _cameraZoom);
    if ((available != _offlineCoverageAvailable ||
            (_tileMode == MapTileMode.offline && zoomChanged) ||
            renderZoomChanged) &&
        mounted) {
      setState(() => _offlineCoverageAvailable = available);
    }
    _reportVisibleBounds(camera);
  }

  void _reportVisibleBounds([MapCamera? camera]) {
    final onBounds = widget.onVisibleBoundsChanged;
    if (onBounds == null) return;
    final bounds = (camera ?? _controller.camera).visibleBounds;
    onBounds(
      GeoBounds(
        north: bounds.north,
        south: bounds.south,
        east: bounds.east,
        west: bounds.west,
      ),
    );
  }

  void _zoomBy(double delta) {
    // Offline mode uses the same zoom range as online: zooming out is not
    // capped at the downloaded minimum, and zooming in overzooms the deepest
    // saved tiles instead of going blank past the downloaded maximum.
    _controller.move(
      _controller.camera.center,
      (_controller.camera.zoom + delta).clamp(1, 19).toDouble(),
    );
  }

  Future<void> _centerOnCurrentLocation() async {
    await widget.store.locate();
    if (!mounted) return;
    final location = widget.store.currentLocation;
    if (location != null) _controller.move(location, _locationZoom);
  }

  /// Obtains a location fix if one is not already known and centers the camera
  /// on the runner at [_locationZoom]. Skips the move if the user has already
  /// interacted with the map, so the initial auto-center never fights a
  /// deliberate pan or zoom.
  Future<void> _locateAndCenter() async {
    if (widget.store.currentLocation == null) {
      await widget.store.locate();
    }
    if (!mounted || _userInteracted) return;
    final location = widget.store.currentLocation;
    if (location != null) _controller.move(location, _locationZoom);
  }

  Future<void> _selectTileMode(MapTileMode mode) async {
    await widget.store.setMapTileMode(mode);
    if (!mounted) return;
    // Rebuild locally so map surfaces pushed above the app shell (route,
    // activity, and area editors) reflect the new source immediately. The
    // shell rebuilds its own pages through its store listener.
    setState(() {});
    if (mode != MapTileMode.offline) return;
    _fitOfflineAreas();
  }

  Future<void> _selectMapLayer(String layerId) async {
    await widget.store.setActiveMapLayer(layerId);
    if (!mounted) return;
    // Rebuild locally so map surfaces pushed above the app shell reflect the
    // new base layer immediately (mirrors _selectTileMode).
    setState(() {});
  }

  void _fitOfflineAreas() {
    final focusedArea = widget.store.focusedOfflineArea;
    final areas = focusedArea == null ? _completedOfflineAreas : [focusedArea];
    if (areas.isEmpty) return;
    _controller.fitCamera(
      CameraFit.coordinates(
        coordinates: [
          for (final area in areas) ...[
            LatLng(area.bounds.north, area.bounds.west),
            LatLng(area.bounds.south, area.bounds.east),
          ],
        ],
        padding: const EdgeInsets.all(56),
        maxZoom: _offlineZoomRange?.$2,
        minZoom: _offlineZoomRange?.$1 ?? 1,
      ),
    );
  }

  void _fitContent({bool includeLocation = true}) {
    final points = <LatLng>[
      ..._routePoints,
      ...widget.track,
      ...widget.waypoints,
      if (includeLocation && widget.store.currentLocation != null)
        widget.store.currentLocation!,
    ];
    final selection = widget.selection;
    if (selection != null && !selection.crossesAntimeridian) {
      points.addAll([
        LatLng(selection.north, selection.west),
        LatLng(selection.south, selection.east),
      ]);
    }

    // In offline mode the map only has saved tiles within the downloaded zoom
    // range, so fitting to a zoom below that range leaves the camera on a blank
    // (gray) map. Floor the fit at the downloaded minimum so "Show on map"
    // always lands on real tiles, even when the area was downloaded only at
    // deep zoom levels.
    final offlineRange = widget.constrainOfflineZoom ? _offlineZoomRange : null;
    final fit = offlineAwareFitZoom(
      offlineMode: _tileMode == MapTileMode.offline,
      offlineRange: offlineRange,
    );

    if (points.length > 1) {
      _controller.fitCamera(
        CameraFit.coordinates(
          coordinates: points,
          padding: const EdgeInsets.all(56),
          minZoom: fit.min ?? 0,
          maxZoom: fit.max,
        ),
      );
      return;
    }
    if (points.isNotEmpty) {
      final target = fit.min == null || fit.min! < 15 ? 15.0 : fit.min!;
      _controller.move(points.first, target);
      return;
    }
    if (includeLocation) {
      _controller.move(_defaultCenter, _defaultZoom);
    }
  }

  /// The tile layers for the current [_tileMode].
  ///
  /// Auto mode draws the saved (offline) map as a base with the live online
  /// map layered on top, so you always get the freshest, most detailed tiles
  /// where there is connectivity and fall back to the saved map where there is
  /// not. Offline mode scales the deepest saved tiles so zooming past what was
  /// downloaded still shows the map instead of going blank.
  List<Widget> _buildTileLayers((double, double)? offlineZoomRange) {
    // Saved tiles can come from any provider persisted on an offline area. The
    // ordered provider resolves the matching provider/format namespace; online
    // tiles still come from the user's currently selected base layer.
    final savedProvider = widget.store.mapProvider;
    final onlineProvider = widget.store.activeMapLayer;
    final savedMaxNative = offlineZoomRange?.$2.round();

    TileLayer savedLayer() => TileLayer(
      key: const ValueKey('tiles-saved'),
      urlTemplate: savedProvider.urlTemplate,
      userAgentPackageName: 'com.bernoulli.trailrunner.trail_runner',
      tileProvider: OrderedOfflineTileProvider(
        store: widget.store.tileStore,
        areas: _renderableOfflineAreas,
      ),
      maxNativeZoom: savedMaxNative ?? 19,
      maxZoom: 19,
    );

    TileLayer onlineLayer({required bool overlay}) => TileLayer(
      key: ValueKey(
        '${overlay ? 'tiles-online-overlay' : 'tiles-online'}'
        '-${onlineProvider.id}',
      ),
      urlTemplate: onlineProvider.urlTemplate,
      userAgentPackageName: 'com.bernoulli.trailrunner.trail_runner',
      tileProvider: OfflineFirstTileProvider(
        store: widget.store.tileStore,
        config: onlineProvider,
        mode: MapTileMode.online,
      ),
      maxZoom: 19,
      // When a tile cannot be fetched (no connectivity), show nothing so the
      // saved base layer beneath stays visible instead of a broken tile.
      errorImage: overlay ? MemoryImage(TileProvider.transparentImage) : null,
      evictErrorTileStrategy: EvictErrorTileStrategy.notVisible,
    );

    switch (_tileMode) {
      case MapTileMode.online:
        return [onlineLayer(overlay: false)];
      case MapTileMode.offline:
        return [savedLayer()];
      case MapTileMode.auto:
        return [
          if (_completedOfflineAreas.isNotEmpty) savedLayer(),
          onlineLayer(overlay: true),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    List<LatLng> renderPoints(List<LatLng> points) =>
        simplifyPolylineForRendering(
          points,
          toleranceMeters: renderingToleranceMeters(
            _cameraCenter.latitude,
            _renderZoom,
          ),
        );

    final routePoints = renderPoints(_routePoints);
    final markerPoints = widget.waypointMarkers ?? widget.waypoints;
    final otherRoutePoints = widget.routes
        .where((candidate) => candidate.id != widget.route?.id)
        .map(
          (candidate) => renderPoints(
            candidate.points.map((point) => point.latLng).toList(),
          ),
        )
        .where((points) => points.length > 1)
        .toList();
    final selectionBounds = widget.selection;
    final offlineZoomRange = widget.constrainOfflineZoom
        ? _offlineZoomRange
        : null;

    return Stack(
      children: [
        FlutterMap(
          mapController: _controller,
          options: MapOptions(
            initialCenter: _defaultCenter,
            initialZoom: _defaultZoom,
            // Offline mode shares the online map's zoom range: no lower lock at
            // the downloaded minimum, and zooming in past the downloaded
            // maximum overzooms the deepest saved tiles instead of going blank.
            maxZoom: 19,
            onTap: widget.onTap == null
                ? null
                : (_, point) => widget.onTap!(point),
            onLongPress: widget.onLongPress == null
                ? null
                : (_, point) => widget.onLongPress!(point),
            onPositionChanged: _updateCamera,
            onMapReady: _reportVisibleBounds,
          ),
          children: [
            ..._buildTileLayers(offlineZoomRange),
            if (widget.trailOverlay.isNotEmpty)
              PolylineLayer(
                polylines: [
                  for (final line in widget.trailOverlay)
                    Polyline(
                      points: renderPoints(line),
                      color: Colors.brown.withAlpha(120),
                      strokeWidth: 2,
                    ),
                ],
              ),
            if (selectionBounds != null && !selectionBounds.crossesAntimeridian)
              PolygonLayer(
                polygons: [
                  Polygon(
                    points: [
                      LatLng(selectionBounds.north, selectionBounds.west),
                      LatLng(selectionBounds.north, selectionBounds.east),
                      LatLng(selectionBounds.south, selectionBounds.east),
                      LatLng(selectionBounds.south, selectionBounds.west),
                    ],
                    color: Colors.transparent,
                    borderColor: Theme.of(context).colorScheme.primary,
                    borderStrokeWidth: 3,
                  ),
                ],
              ),
            if (_tileMode == MapTileMode.offline &&
                _completedOfflineAreas.isNotEmpty)
              PolygonLayer(
                polygons: [
                  for (final area in _completedOfflineAreas)
                    if (area.id != widget.store.focusedOfflineArea?.id)
                      Polygon(
                        points: [
                          LatLng(area.bounds.north, area.bounds.west),
                          LatLng(area.bounds.north, area.bounds.east),
                          LatLng(area.bounds.south, area.bounds.east),
                          LatLng(area.bounds.south, area.bounds.west),
                        ],
                        color: Colors.transparent,
                        borderColor: Colors.teal,
                        borderStrokeWidth: 2,
                      ),
                ],
              ),
            if (_showTrails && otherRoutePoints.isNotEmpty)
              PolylineLayer(
                polylines: [
                  for (final points in otherRoutePoints)
                    Polyline(
                      points: points,
                      color: Colors.green.shade700.withAlpha(190),
                      strokeWidth: 3,
                      pattern: StrokePattern.dashed(
                        segments: const [10.0, 8.0],
                      ),
                    ),
                ],
              ),
            if (routePoints.length > 1)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: routePoints,
                    color: Colors.deepOrange,
                    strokeWidth: 5,
                    pattern: StrokePattern.dashed(segments: const [14.0, 9.0]),
                  ),
                ],
              ),
            if (widget.track.length > 1)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: renderPoints(widget.track),
                    color: Colors.blue,
                    strokeWidth: 5,
                  ),
                ],
              ),
            if (widget.waypoints.length > 1)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: renderPoints(widget.waypoints),
                    color: Theme.of(context).colorScheme.primary,
                    strokeWidth: 4,
                  ),
                ],
              ),
            if (markerPoints.isNotEmpty)
              MarkerLayer(
                markers: [
                  for (var i = 0; i < markerPoints.length; i++)
                    Marker(
                      point: markerPoints[i],
                      width: 40,
                      height: 40,
                      child: CircleAvatar(
                        backgroundColor: i == widget.highlightedWaypoint
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).colorScheme.primary,
                        foregroundColor: i == widget.highlightedWaypoint
                            ? Theme.of(context).colorScheme.onError
                            : Theme.of(context).colorScheme.onPrimary,
                        child: Text('${i + 1}'),
                      ),
                    ),
                ],
              ),
            if (widget.selectionStart != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: widget.selectionStart!,
                    width: 22,
                    height: 22,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                        border: const Border.fromBorderSide(
                          BorderSide(color: Colors.white, width: 3),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            if (widget.store.currentLocation != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: widget.store.currentLocation!,
                    width: 28,
                    height: 28,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                        border: Border.fromBorderSide(
                          BorderSide(color: Colors.white, width: 4),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            RichAttributionWidget(
              attributions: [TextSourceAttribution(_attributionText)],
            ),
          ],
        ),
        if (widget.showControls)
          Positioned(
            top: widget.controlsTop,
            right: 16,
            child: TrailMapControls(
              mode: widget.store.mapTileMode,
              layers: widget.store.baseLayers,
              activeLayerId: widget.store.activeMapLayer.id,
              onLayerSelected: (id) => unawaited(_selectMapLayer(id)),
              offlineAvailable: _offlineCoverageAvailable,
              trailsVisible: _showTrails,
              onToggleTrails: () => setState(() => _showTrails = !_showTrails),
              onModeSelected: (mode) => unawaited(_selectTileMode(mode)),
              onZoomIn: _cameraZoom >= 19 ? null : () => _zoomBy(1),
              onZoomOut: _cameraZoom <= 1 ? null : () => _zoomBy(-1),
              onFitContent: _fitContent,
              onCurrentLocation: _centerOnCurrentLocation,
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class TrailMapControls extends StatelessWidget {
  const TrailMapControls({
    super.key,
    required this.mode,
    required this.layers,
    required this.activeLayerId,
    required this.onLayerSelected,
    required this.offlineAvailable,
    required this.trailsVisible,
    required this.onToggleTrails,
    required this.onModeSelected,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFitContent,
    required this.onCurrentLocation,
  });

  final MapTileMode mode;
  final List<MapProviderConfig> layers;
  final String activeLayerId;
  final ValueChanged<String> onLayerSelected;
  final bool offlineAvailable;
  final bool trailsVisible;
  final VoidCallback onToggleTrails;
  final ValueChanged<MapTileMode> onModeSelected;
  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;
  final VoidCallback onFitContent;
  final VoidCallback onCurrentLocation;

  @override
  Widget build(BuildContext context) {
    final activeLayer = layers.isEmpty
        ? null
        : layers.firstWhere(
            (layer) => layer.id == activeLayerId,
            orElse: () => layers.first,
          );
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (layers.length > 1 && activeLayer != null) ...[
            PopupMenuButton<String>(
              initialValue: activeLayerId,
              tooltip: 'Base map: ${activeLayer.label}',
              onSelected: onLayerSelected,
              itemBuilder: (context) => [
                for (final layer in layers)
                  PopupMenuItem(
                    value: layer.id,
                    child: ListTile(
                      leading: Icon(
                        layer.id == activeLayerId
                            ? Icons.check_circle
                            : Icons.circle_outlined,
                      ),
                      title: Text(layer.label),
                      subtitle: Text(
                        layer.attribution,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
              ],
              child: SizedBox(
                width: 48,
                height: 56,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.map_outlined, size: 21),
                    Text(
                      activeLayer.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
          ],
          PopupMenuButton<MapTileMode>(
            initialValue: mode,
            tooltip: 'Map source: ${mode.label}',
            onSelected: onModeSelected,
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: MapTileMode.auto,
                child: ListTile(
                  leading: Icon(Icons.sync),
                  title: Text('Auto'),
                  subtitle: Text('Downloaded tiles first, then online'),
                ),
              ),
              const PopupMenuItem(
                value: MapTileMode.online,
                child: ListTile(
                  leading: Icon(Icons.cloud_outlined),
                  title: Text('Online'),
                  subtitle: Text('Always use the network'),
                ),
              ),
              PopupMenuItem(
                value: MapTileMode.offline,
                child: ListTile(
                  leading: const Icon(Icons.cloud_off_outlined),
                  title: const Text('Offline'),
                  subtitle: Text(
                    offlineAvailable
                        ? 'Downloaded coverage is available here'
                        : 'Find and browse downloaded map areas',
                  ),
                ),
              ),
            ],
            child: SizedBox(
              width: 48,
              height: 56,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(mode.icon, size: 21),
                  Text(
                    mode.label,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          IconButton(
            onPressed: onZoomIn,
            tooltip: 'Zoom in',
            icon: const Icon(Icons.add),
          ),
          IconButton(
            onPressed: onZoomOut,
            tooltip: 'Zoom out',
            icon: const Icon(Icons.remove),
          ),
          IconButton(
            onPressed: onToggleTrails,
            tooltip: trailsVisible ? 'Hide saved trails' : 'Show saved trails',
            icon: Icon(trailsVisible ? Icons.layers : Icons.layers_clear),
          ),
          IconButton(
            onPressed: onFitContent,
            tooltip: 'Fit current location and checkpoints',
            icon: const Icon(Icons.center_focus_strong),
          ),
          IconButton(
            onPressed: onCurrentLocation,
            tooltip: 'Center on current location',
            icon: const Icon(Icons.my_location),
          ),
        ],
      ),
    );
  }
}

/// The zoom clamp used when auto-fitting the camera so it never lands where no
/// tiles exist. In offline mode the saved map only has tiles within the
/// downloaded [offlineRange]; fitting below its minimum shows a blank (gray)
/// map, so the fit is floored at that minimum (and the cap is raised to match
/// when a download starts deeper than [maxCap]). Returns a null minimum when
/// online tiles can fill any zoom, so online/auto fitting is unaffected.
@visibleForTesting
({double? min, double max}) offlineAwareFitZoom({
  required bool offlineMode,
  required (double, double)? offlineRange,
  double maxCap = 16,
}) {
  if (!offlineMode || offlineRange == null) return (min: null, max: maxCap);
  final floor = offlineRange.$1;
  return (min: floor, max: floor > maxCap ? floor : maxCap);
}

extension on MapTileMode {
  String get label => switch (this) {
    MapTileMode.auto => 'Auto',
    MapTileMode.online => 'Online',
    MapTileMode.offline => 'Offline',
  };

  IconData get icon => switch (this) {
    MapTileMode.auto => Icons.sync,
    MapTileMode.online => Icons.cloud_outlined,
    MapTileMode.offline => Icons.cloud_off_outlined,
  };
}
