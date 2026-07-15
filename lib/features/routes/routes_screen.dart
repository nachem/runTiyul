import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../app/app_store.dart';
import '../../core/geo/distance.dart';
import '../../core/geo/geo_bounds.dart';
import '../../core/units/formatters.dart';
import '../../models/trail_route.dart';
import '../../services/trail_router.dart';
import '../map/trail_map.dart';

class RoutesScreen extends StatelessWidget {
  const RoutesScreen({
    super.key,
    required this.store,
    required this.onShowMap,
    required this.onStart,
  });

  final AppStore store;
  final VoidCallback onShowMap;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Routes'),
        actions: [
          IconButton(
            onPressed: store.importGpx,
            tooltip: 'Import GPX',
            icon: const Icon(Icons.file_upload_outlined),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ManualRouteEditor(store: store),
              ),
            ),
            tooltip: 'Create route',
            icon: const Icon(Icons.add_location_alt_outlined),
          ),
        ],
      ),
      body: store.routes.isEmpty
          ? _EmptyRoutes(
              onImport: store.importGpx,
              onCreate: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ManualRouteEditor(store: store),
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: store.routes.length,
              itemBuilder: (context, index) {
                final route = store.routes[index];
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Icon(
                        route.source == RouteSource.gpx
                            ? Icons.upload_file
                            : Icons.edit_road,
                      ),
                    ),
                    title: Text(route.name),
                    subtitle: Text(
                      '${formatDistance(route.distanceMeters)}'
                      ' • ${route.points.length} points'
                      ' • ${route.source.name.toUpperCase()}',
                    ),
                    trailing: IconButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => RouteDetailScreen(
                            store: store,
                            route: route,
                            onStart: onStart,
                          ),
                        ),
                      ),
                      tooltip: 'Manage route',
                      icon: const Icon(Icons.more_vert),
                    ),
                    onTap: () {
                      store.selectRoute(route);
                      onShowMap();
                    },
                  ),
                );
              },
            ),
    );
  }
}

class _EmptyRoutes extends StatelessWidget {
  const _EmptyRoutes({required this.onImport, required this.onCreate});

  final VoidCallback onImport;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.route,
              size: 72,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'No routes yet',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Import a GPX file or tap points on the map to create a route.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              children: [
                OutlinedButton.icon(
                  onPressed: onImport,
                  icon: const Icon(Icons.file_upload_outlined),
                  label: const Text('Import GPX'),
                ),
                FilledButton.icon(
                  onPressed: onCreate,
                  icon: const Icon(Icons.add_location_alt),
                  label: const Text('Create route'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ManualRouteEditor extends StatefulWidget {
  const ManualRouteEditor({super.key, required this.store, this.initialRoute});

  final AppStore store;

  /// When provided, the editor loads this route's waypoints for editing and
  /// saves the changes back onto it instead of creating a new route.
  final TrailRoute? initialRoute;

  @override
  State<ManualRouteEditor> createState() => _ManualRouteEditorState();
}

class _ManualRouteEditorState extends State<ManualRouteEditor> {
  final _nameController = TextEditingController();
  final List<LatLng> _points = [];
  var _saving = false;
  late bool _snap;
  int? _selected;
  var _moving = false;

  // Follow-trails mode: tap real trails and let the route follow them.
  var _followTrails = false;
  final List<TrailAnchor> _followAnchors = [];
  TrailRouter? _trailRouter;
  List<List<LatLng>> _trailLines = const [];
  var _loadingTrails = false;
  String? _trailError;
  GeoBounds? _lastBounds;

  @override
  void initState() {
    super.initState();
    _snap = widget.store.snapRoutesToTrails;
    final initial = widget.initialRoute;
    if (initial != null) {
      _points.addAll(initial.points.map((point) => point.latLng));
      _nameController.text = initial.name;
    } else {
      _nameController.text = 'Route ${widget.store.routes.length + 1}';
      // Center a brand-new route on the runner's current position.
      unawaited(widget.store.locate());
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// The points shown as editable markers for the current mode: the drawn
  /// checkpoints, or the trail anchors when following trails.
  List<LatLng> get _activeMarkers => _followTrails
      ? [for (final anchor in _followAnchors) anchor.point]
      : _points;

  void _setFollowTrails(bool value) {
    setState(() {
      _followTrails = value;
      _selected = null;
      _moving = false;
      _points.clear();
      _followAnchors.clear();
      _trailError = null;
    });
    if (value) unawaited(_loadTrails());
  }

  Future<void> _loadTrails() async {
    final source = widget.store.vectorSourceUrl;
    final bounds = _lastBounds;
    if (source.isEmpty) {
      setState(() => _trailError = 'No trail data source configured');
      return;
    }
    if (bounds == null) {
      setState(() => _trailError = 'Move the map, then reload trails');
      return;
    }
    setState(() {
      _loadingTrails = true;
      _trailError = null;
    });
    try {
      final network = await widget.store.routeTrailBuilder.networkForBounds(
        bounds,
        source,
      );
      if (!mounted) return;
      setState(() {
        _trailRouter = TrailRouter(network);
        _trailLines = [for (final trail in network.trails) trail.points];
        _loadingTrails = false;
        if (network.isEmpty) _trailError = 'No trails found in this area';
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loadingTrails = false;
        _trailError = 'Could not load trails here';
      });
    }
  }

  void _addFollowAnchor(LatLng point) {
    final router = _trailRouter;
    if (router == null || router.isEmpty) {
      setState(() => _trailError = 'Reload trails for this area first');
      return;
    }
    final anchor = router.snap(point, maxMeters: 40);
    if (anchor == null) {
      setState(() => _trailError = 'Tap on or near a trail');
      return;
    }
    setState(() {
      _followAnchors.add(anchor);
      _rebuildFollowRoute();
      _selected = null;
      _moving = false;
      _trailError = null;
    });
  }

  void _rebuildFollowRoute() {
    final router = _trailRouter;
    _points
      ..clear()
      ..addAll(
        router == null
            ? [for (final anchor in _followAnchors) anchor.point]
            : router.buildRoute(_followAnchors),
      );
  }

  int? _nearestWaypoint(LatLng target) {
    final markers = _activeMarkers;
    if (markers.isEmpty) return null;
    const distance = GeoDistance();
    var bestIndex = 0;
    var bestMeters = distance.metersBetween(markers.first, target);
    for (var i = 1; i < markers.length; i++) {
      final meters = distance.metersBetween(markers[i], target);
      if (meters < bestMeters) {
        bestMeters = meters;
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.initialRoute == null ? 'Create route' : 'Edit route',
        ),
        actions: [
          IconButton(
            onPressed:
                (_followTrails ? _followAnchors.isEmpty : _points.isEmpty)
                ? null
                : () => setState(() {
                    if (_followTrails) {
                      if (_followAnchors.isNotEmpty) {
                        _followAnchors.removeLast();
                      }
                      _rebuildFollowRoute();
                    } else {
                      _points.removeLast();
                    }
                    _selected = null;
                    _moving = false;
                  }),
            tooltip: 'Undo last point',
            icon: const Icon(Icons.undo),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Route name',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.touch_app_outlined),
                      label: Text('Checkpoints'),
                    ),
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.alt_route),
                      label: Text('Follow trails'),
                    ),
                  ],
                  selected: {_followTrails},
                  onSelectionChanged: (selection) =>
                      _setFollowTrails(selection.first),
                ),
                if (_followTrails)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _loadingTrails
                                ? 'Loading trails\u2026'
                                : (_trailError ??
                                      'Tap trails to build the route'),
                            style: Theme.of(context).textTheme.bodySmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _loadingTrails
                              ? null
                              : () => unawaited(_loadTrails()),
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Reload'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: TrailMap(
              store: widget.store,
              waypoints: _points,
              waypointMarkers: _followTrails ? _activeMarkers : null,
              trailOverlay: _followTrails ? _trailLines : const [],
              highlightedWaypoint: _selected,
              initialCenter: widget.store.currentLocation,
              initialZoom: widget.initialRoute == null ? 16 : null,
              autoFit: widget.initialRoute != null,
              onVisibleBoundsChanged: (bounds) => _lastBounds = bounds,
              onTap: (point) {
                if (_followTrails) {
                  _addFollowAnchor(point);
                  return;
                }
                setState(() {
                  final selected = _selected;
                  if (_moving && selected != null) {
                    _points[selected] = point;
                    _moving = false;
                  } else {
                    _points.add(point);
                  }
                });
              },
              onLongPress: (point) =>
                  setState(() => _selected = _nearestWaypoint(point)),
              showControls: true,
            ),
          ),
          if (_selected != null)
            Material(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _moving
                            ? 'Point ${_selected! + 1}: tap the map to move it'
                            : (_followTrails
                                  ? 'Anchor ${_selected! + 1} selected'
                                  : 'Point ${_selected! + 1} selected'),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!_followTrails)
                      TextButton.icon(
                        onPressed: () => setState(() => _moving = true),
                        icon: const Icon(Icons.open_with),
                        label: const Text('Move'),
                      ),
                    TextButton.icon(
                      onPressed: () => setState(() {
                        final selected = _selected!;
                        if (_followTrails) {
                          if (selected < _followAnchors.length) {
                            _followAnchors.removeAt(selected);
                          }
                          _rebuildFollowRoute();
                        } else {
                          _points.removeAt(selected);
                        }
                        _selected = null;
                        _moving = false;
                      }),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete'),
                    ),
                    IconButton(
                      tooltip: 'Deselect',
                      onPressed: () => setState(() {
                        _selected = null;
                        _moving = false;
                      }),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            ),
          if (!_followTrails)
            SwitchListTile(
              value: _snap,
              onChanged: (value) => setState(() => _snap = value),
              title: const Text('Snap to nearby trail'),
              subtitle: const Text(
                'Aligns the saved route to a close real trail when one is found.',
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _followTrails
                        ? '${_followAnchors.length} trail points'
                        : '${_points.length} waypoints',
                  ),
                ),
                FilledButton.icon(
                  onPressed: _saving || _points.length < 2
                      ? null
                      : () async {
                          setState(() => _saving = true);
                          await widget.store.setSnapRoutesToTrails(_snap);
                          final initial = widget.initialRoute;
                          final saved = initial == null
                              ? await widget.store.saveManualRoute(
                                  _nameController.text,
                                  _points,
                                )
                              : await widget.store.updateManualRoute(
                                  initial,
                                  _nameController.text,
                                  _points,
                                );
                          if (!context.mounted) return;
                          if (saved) {
                            Navigator.of(context).pop(true);
                          } else {
                            setState(() => _saving = false);
                          }
                        },
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: const Text('Save'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class RouteDetailScreen extends StatelessWidget {
  const RouteDetailScreen({
    super.key,
    required this.store,
    required this.route,
    required this.onStart,
  });

  final AppStore store;
  final TrailRoute route;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(route.name),
        actions: [
          IconButton(
            onPressed: () async {
              final edited = await Navigator.of(context).push<bool>(
                MaterialPageRoute<bool>(
                  builder: (_) =>
                      ManualRouteEditor(store: store, initialRoute: route),
                ),
              );
              if (edited == true && context.mounted) {
                Navigator.of(context).pop();
              }
            },
            tooltip: 'Edit waypoints',
            icon: const Icon(Icons.edit_location_alt_outlined),
          ),
          IconButton(
            onPressed: () async {
              final controller = TextEditingController(text: route.name);
              final name = await showDialog<String>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Rename route'),
                  content: TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Route name'),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, controller.text),
                      child: const Text('Save'),
                    ),
                  ],
                ),
              );
              controller.dispose();
              if (name != null) {
                await store.renameRoute(route, name);
                if (context.mounted) Navigator.of(context).pop();
              }
            },
            tooltip: 'Rename route',
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            onPressed: () async {
              await store.duplicateRoute(route);
              if (context.mounted) Navigator.of(context).pop();
            },
            tooltip: 'Duplicate route',
            icon: const Icon(Icons.copy_outlined),
          ),
          IconButton(
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Delete route?'),
                  content: const Text(
                    'Saved activities will keep their tracks.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                await store.deleteRoute(route);
                if (context.mounted) Navigator.of(context).pop();
              }
            },
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: TrailMap(
              store: store,
              route: route,
              showControls: true,
              autoFit: true,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formatDistance(route.distanceMeters),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      Text('${route.points.length} route points'),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: () {
                    store.selectRoute(route);
                    Navigator.of(context).pop();
                    onStart();
                  },
                  icon: const Icon(Icons.directions_run),
                  label: const Text('Use route'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
