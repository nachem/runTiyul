import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../app/app_store.dart';
import '../../core/geo/geo_bounds.dart';
import '../../models/offline_area.dart';
import '../../models/trail_route.dart';
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
    this.onTap,
    this.offlineOnly = false,
    this.initialCenter,
    this.initialZoom,
    this.showControls = false,
    this.controlsTop = 16,
    this.constrainOfflineZoom = true,
  });

  final AppStore store;
  final TrailRoute? route;
  final List<TrailRoute> routes;
  final List<LatLng> track;
  final List<LatLng> waypoints;
  final GeoBounds? selection;
  final ValueChanged<LatLng>? onTap;
  final bool offlineOnly;
  final LatLng? initialCenter;
  final double? initialZoom;
  final bool showControls;
  final double controlsTop;
  final bool constrainOfflineZoom;

  @override
  State<TrailMap> createState() => _TrailMapState();
}

class _TrailMapState extends State<TrailMap> {
  late final MapController _controller;
  late LatLng _cameraCenter;
  late double _cameraZoom;
  late bool _offlineCoverageAvailable;

  LatLng get _defaultCenter =>
      widget.initialCenter ??
      widget.store.currentLocation ??
      widget.route?.points.firstOrNull?.latLng ??
      widget.waypoints.firstOrNull ??
      const LatLng(31.7683, 35.2137);

  double get _defaultZoom =>
      widget.initialZoom ?? (_routePoints.isEmpty ? 11 : 13);

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
    _offlineCoverageAvailable = _hasOfflineCoverage(_cameraCenter, _cameraZoom);
  }

  @override
  void didUpdateWidget(covariant TrailMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    _offlineCoverageAvailable = _hasOfflineCoverage(_cameraCenter, _cameraZoom);
  }

  bool _hasOfflineCoverage(LatLng center, double zoom) {
    final target = widget.store.currentLocation ?? center;
    final roundedZoom = zoom.round();
    return widget.store.offlineAreas.any(
      (area) =>
          area.providerId == widget.store.mapProvider.id &&
          area.status == OfflineAreaStatus.complete &&
          area.minZoom <= roundedZoom &&
          area.maxZoom >= roundedZoom &&
          area.bounds.contains(target),
    );
  }

  List<OfflineArea> get _completedOfflineAreas => widget.store.offlineAreas
      .where(
        (area) =>
            area.providerId == widget.store.mapProvider.id &&
            area.status == OfflineAreaStatus.complete &&
            !area.bounds.crossesAntimeridian,
      )
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

  void _updateCamera(MapCamera camera, bool _) {
    final zoomChanged = (_cameraZoom - camera.zoom).abs() > 0.001;
    _cameraCenter = camera.center;
    _cameraZoom = camera.zoom;
    final available = _hasOfflineCoverage(_cameraCenter, _cameraZoom);
    if ((available != _offlineCoverageAvailable ||
            (_tileMode == MapTileMode.offline && zoomChanged)) &&
        mounted) {
      setState(() => _offlineCoverageAvailable = available);
    }
  }

  void _zoomBy(double delta) {
    final allowedRange = _tileMode == MapTileMode.offline
        ? _offlineZoomRange
        : null;
    _controller.move(
      _controller.camera.center,
      (_controller.camera.zoom + delta).clamp(
        allowedRange?.$1 ?? 1,
        allowedRange?.$2 ?? 19,
      ),
    );
  }

  Future<void> _centerOnCurrentLocation() async {
    await widget.store.locate();
    if (!mounted) return;
    final location = widget.store.currentLocation;
    if (location != null) _controller.move(location, 15);
  }

  Future<void> _selectTileMode(MapTileMode mode) async {
    await widget.store.setMapTileMode(mode);
    if (!mounted || mode != MapTileMode.offline) return;
    _fitOfflineAreas();
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

  void _fitContent() {
    final points = <LatLng>[
      ..._routePoints,
      ...widget.track,
      ...widget.waypoints,
      ?widget.store.currentLocation,
    ];
    final selection = widget.selection;
    if (selection != null && !selection.crossesAntimeridian) {
      points.addAll([
        LatLng(selection.north, selection.west),
        LatLng(selection.south, selection.east),
      ]);
    }

    if (points.length > 1) {
      _controller.fitCamera(
        CameraFit.coordinates(
          coordinates: points,
          padding: const EdgeInsets.all(56),
          maxZoom: 16,
        ),
      );
      return;
    }
    _controller.move(
      points.firstOrNull ?? _defaultCenter,
      points.isEmpty ? _defaultZoom : 15,
    );
  }

  @override
  Widget build(BuildContext context) {
    final routePoints = _routePoints;
    final otherRoutePoints = widget.routes
        .where((candidate) => candidate.id != widget.route?.id)
        .map(
          (candidate) => candidate.points.map((point) => point.latLng).toList(),
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
            minZoom: _tileMode == MapTileMode.offline
                ? offlineZoomRange?.$1
                : null,
            maxZoom: _tileMode == MapTileMode.offline
                ? offlineZoomRange?.$2
                : null,
            onTap: widget.onTap == null
                ? null
                : (_, point) => widget.onTap!(point),
            onPositionChanged: _updateCamera,
          ),
          children: [
            TileLayer(
              key: ValueKey(_tileMode),
              urlTemplate: widget.store.mapProvider.urlTemplate,
              userAgentPackageName: 'com.bernoulli.trailrunner.trail_runner',
              tileProvider: OfflineFirstTileProvider(
                store: widget.store.tileStore,
                config: widget.store.mapProvider,
                mode: _tileMode,
              ),
              maxZoom: 19,
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
                    color: Theme.of(context).colorScheme.primary.withAlpha(45),
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
                        color: Colors.teal.withAlpha(28),
                        borderColor: Colors.teal,
                        borderStrokeWidth: 2,
                      ),
                ],
              ),
            if (otherRoutePoints.isNotEmpty)
              PolylineLayer(
                polylines: [
                  for (final points in otherRoutePoints)
                    Polyline(
                      points: points,
                      color: Colors.green.shade700.withAlpha(190),
                      strokeWidth: 3,
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
                  ),
                ],
              ),
            if (widget.track.length > 1)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: widget.track,
                    color: Colors.blue,
                    strokeWidth: 5,
                  ),
                ],
              ),
            if (widget.waypoints.isNotEmpty)
              MarkerLayer(
                markers: [
                  for (var i = 0; i < widget.waypoints.length; i++)
                    Marker(
                      point: widget.waypoints[i],
                      width: 34,
                      height: 34,
                      child: CircleAvatar(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Theme.of(
                          context,
                        ).colorScheme.onPrimary,
                        child: Text('${i + 1}'),
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
              attributions: [
                TextSourceAttribution(widget.store.mapProvider.attribution),
              ],
            ),
          ],
        ),
        if (widget.showControls)
          Positioned(
            top: widget.controlsTop,
            right: 16,
            child: TrailMapControls(
              mode: widget.store.mapTileMode,
              offlineAvailable: _offlineCoverageAvailable,
              onModeSelected: (mode) => unawaited(_selectTileMode(mode)),
              onZoomIn:
                  _tileMode == MapTileMode.offline &&
                      offlineZoomRange != null &&
                      _cameraZoom >= offlineZoomRange.$2
                  ? null
                  : () => _zoomBy(1),
              onZoomOut:
                  _tileMode == MapTileMode.offline &&
                      offlineZoomRange != null &&
                      _cameraZoom <= offlineZoomRange.$1
                  ? null
                  : () => _zoomBy(-1),
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
    required this.offlineAvailable,
    required this.onModeSelected,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFitContent,
    required this.onCurrentLocation,
  });

  final MapTileMode mode;
  final bool offlineAvailable;
  final ValueChanged<MapTileMode> onModeSelected;
  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;
  final VoidCallback onFitContent;
  final VoidCallback onCurrentLocation;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
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
