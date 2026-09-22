import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../app/app_store.dart';
import '../../core/geo/distance.dart';
import '../../core/geo/geo_bounds.dart';
import '../../core/units/formatters.dart';
import '../../models/trail_route.dart';
import '../../services/trail_network.dart';
import '../../services/trail_router.dart';
import '../../services/tile_store.dart';
import 'route_editor_draft.dart';
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
  RouteEditorDraft _draft = RouteEditorDraft(const []);
  final List<RouteEditorDraft> _undo = [];
  List<LatLng> get _points => _draft.points;
  var _saving = false;
  late bool _snap;
  int? _selected;
  var _moving = false;

  // Follow-trails mode: tap real trails and let the route follow them.
  var _followTrails = false;
  TrailNetwork _trailNetwork = const TrailNetwork([]);
  TrailRouter? _trailRouter;
  var _loadingTrails = false;
  String? _trailError;
  GeoBounds? _lastBounds;

  @override
  void initState() {
    super.initState();
    _snap = widget.initialRoute == null && widget.store.snapRoutesToTrails;
    final initial = widget.initialRoute;
    if (initial != null) {
      _draft = RouteEditorDraft(
        initial.points.map((point) => point.latLng).toList(),
      );
      _followTrails = widget.store.usesVectorSource;
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

  List<LatLng> get _activeMarkers => _draft.controls;

  void _setFollowTrails(bool value) {
    if (value == _followTrails || _loadingTrails || _saving) return;
    setState(() {
      _followTrails = value;
      _selected = null;
      _moving = false;
      _trailError = null;
    });
    if (value) unawaited(_loadTrails());
  }

  Future<void> _loadTrails({LatLng? near}) async {
    if (_loadingTrails) return;
    final source = widget.store.vectorSourceUrl;
    final bounds = _lastBounds;
    if (source.isEmpty) {
      setState(() => _trailError = 'No trail data source configured');
      return;
    }
    if (bounds == null && near == null) {
      setState(() => _trailError = 'Move the map, then reload trails');
      return;
    }
    setState(() {
      _loadingTrails = true;
      _trailError = null;
    });
    try {
      final allowNetwork = widget.store.mapTileMode != MapTileMode.offline;
      final network = near == null
          ? await widget.store.routeTrailBuilder.networkForBounds(
              bounds!,
              source,
              allowNetwork: allowNetwork,
            )
          : await widget.store.routeTrailBuilder.networkNearPoint(
              near,
              source,
              allowNetwork: allowNetwork,
            );
      if (!mounted) return;
      final merged = _trailNetwork.merge(network);
      final router = TrailRouter(merged);
      setState(() {
        _trailNetwork = merged;
        _trailRouter = router;
        _loadingTrails = false;
        if (merged.isEmpty) {
          _trailError = allowNetwork
              ? 'No mapped ways found here'
              : 'No cached mapped ways here';
        }
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loadingTrails = false;
        _trailError = 'Could not load trails here';
      });
    }
  }

  Future<void> _editAt(LatLng point) async {
    if (_loadingTrails || _saving) return;
    final original = _draft;
    final selected = _moving ? _selected : null;
    if (_followTrails &&
        selected == null &&
        _points.isNotEmpty &&
        !widget.store.routeTrailBuilder.canLoadInteractiveLeg(
          _points.last,
          point,
        )) {
      setState(
        () => _trailError =
            'Point is too far away. Add a closer trail point first',
      );
      return;
    }
    RouteEditorDraft? edit() => selected == null
        ? original.append(
            point,
            router: _trailRouter,
            followTrails: _followTrails,
          )
        : original.moveControl(
            selected,
            point,
            router: _trailRouter,
            followTrails: _followTrails,
          );
    var result = edit();
    if (_followTrails && result == null) {
      await _loadTrails(near: point);
      if (!mounted || !identical(original, _draft)) return;
      result = edit();
    }
    _applyEdit(result);
  }

  void _applyEdit(RouteEditorDraft? result) {
    if (!mounted) return;
    setState(() {
      if (result == null) {
        _trailError =
            'No connected mapped path for this edit. Route unchanged.';
        return;
      }
      _undo.add(_draft);
      if (_undo.length > 30) _undo.removeAt(0);
      _draft = result;
      _selected = null;
      _moving = false;
      _trailError = null;
    });
  }

  Future<void> _deleteControl() async {
    final selected = _selected;
    if (selected == null || _loadingTrails || _saving) return;
    if (_followTrails && _trailRouter == null) {
      await _loadTrails(near: _activeMarkers[selected]);
    }
    if (!mounted) return;
    _applyEdit(
      _draft.removeControl(
        selected,
        router: _trailRouter,
        followTrails: _followTrails,
      ),
    );
  }

  void _selectAt(LatLng point) {
    if (_loadingTrails || _saving) return;
    final nearest = _nearestWaypoint(point);
    if (nearest != null) {
      setState(() {
        _selected = nearest;
        _moving = false;
      });
      return;
    }
    final inserted = _draft.insertControl(point);
    if (inserted == null) return;
    _applyEdit(inserted.draft);
    setState(() => _selected = inserted.control);
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
    return bestMeters <= 25 ? bestIndex : null;
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
            onPressed: (_undo.isEmpty || _loadingTrails || _saving)
                ? null
                : () => setState(() {
                    _draft = _undo.removeLast();
                    _selected = null;
                    _moving = false;
                  }),
            tooltip: 'Undo route edit',
            icon: const Icon(Icons.undo),
          ),
        ],
      ),
      body: SafeArea(
        key: const ValueKey('route-editor-safe-area'),
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _nameController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Route name',
                  border: const OutlineInputBorder(),
                  errorText: _nameController.text.trim().isEmpty
                      ? 'Enter a route name'
                      : null,
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
                    onSelectionChanged: _loadingTrails || _saving
                        ? null
                        : (selection) => _setFollowTrails(selection.first),
                  ),
                  if (_followTrails || _trailError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _loadingTrails
                                  ? 'Loading trails\u2026'
                                  : (_trailError ??
                                        '${_trailNetwork.trails.length} mapped ways'),
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
                waypointMarkers: _activeMarkers,
                onWaypointTap: (index) {
                  if (_loadingTrails || _saving) return;
                  setState(() {
                    _selected = index;
                    _moving = false;
                  });
                },
                highlightedWaypoint: _selected,
                initialCenter: widget.store.currentLocation,
                initialZoom: widget.initialRoute == null ? 16 : null,
                autoFit: widget.initialRoute != null,
                refitOnContentChange: false,
                onVisibleBoundsChanged: (bounds) => _lastBounds = bounds,
                onTap: (point) => unawaited(_editAt(point)),
                onLongPress: _selectAt,
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
                      TextButton.icon(
                        onPressed: _loadingTrails || _saving
                            ? null
                            : () => setState(() => _moving = true),
                        icon: const Icon(Icons.open_with),
                        label: const Text('Move'),
                      ),
                      TextButton.icon(
                        onPressed: _loadingTrails || _saving
                            ? null
                            : () => unawaited(_deleteControl()),
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
                  Expanded(child: Text('${_activeMarkers.length} controls')),
                  FilledButton.icon(
                    onPressed:
                        _saving ||
                            _loadingTrails ||
                            _points.length < 2 ||
                            _nameController.text.trim().isEmpty
                        ? null
                        : () async {
                            setState(() => _saving = true);
                            final initial = widget.initialRoute;
                            final saved = initial == null
                                ? await widget.store.saveManualRoute(
                                    _nameController.text,
                                    _points,
                                    snapToTrailsOverride:
                                        _snap && !_followTrails,
                                    preserveGeometry: true,
                                  )
                                : await widget.store.updateManualRoute(
                                    initial,
                                    _nameController.text,
                                    _points,
                                    snapToTrailsOverride:
                                        _snap && !_followTrails,
                                    preserveGeometry: true,
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
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final currentRoute = store.routes
            .where((candidate) => candidate.id == route.id)
            .firstOrNull;
        final displayedRoute = currentRoute ?? route;
        return Scaffold(
          appBar: AppBar(
            title: Text(displayedRoute.name),
            actions: [
              IconButton(
                onPressed: () async {
                  final edited = await Navigator.of(context).push<bool>(
                    MaterialPageRoute<bool>(
                      builder: (_) => ManualRouteEditor(
                        store: store,
                        initialRoute: displayedRoute,
                      ),
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
                  final controller = TextEditingController(
                    text: displayedRoute.name,
                  );
                  final name = await showDialog<String>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Rename route'),
                      content: TextField(
                        controller: controller,
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'Route name',
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () =>
                              Navigator.pop(context, controller.text),
                          child: const Text('Save'),
                        ),
                      ],
                    ),
                  );
                  controller.dispose();
                  if (name != null) {
                    await store.renameRoute(displayedRoute, name);
                    if (context.mounted) Navigator.of(context).pop();
                  }
                },
                tooltip: 'Rename route',
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                onPressed: () async {
                  await store.duplicateRoute(displayedRoute);
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
                    await store.deleteRoute(displayedRoute);
                    if (context.mounted) Navigator.of(context).pop();
                  }
                },
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          body: SafeArea(
            key: const ValueKey('route-detail-safe-area'),
            top: false,
            child: Column(
              children: [
                Expanded(
                  child: TrailMap(
                    store: store,
                    route: displayedRoute,
                    routes: store.routes,
                    showControls: true,
                    autoFit: true,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        formatDistance(displayedRoute.distanceMeters),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      Text('${displayedRoute.points.length} route points'),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _SnapToTrailsButton(
                              store: store,
                              route: displayedRoute,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () {
                                store.selectRoute(displayedRoute);
                                Navigator.of(context).pop();
                                onStart();
                              },
                              icon: const Icon(Icons.directions_run),
                              label: const Text('Use route'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SnapToTrailsButton extends StatefulWidget {
  const _SnapToTrailsButton({required this.store, required this.route});

  final AppStore store;
  final TrailRoute route;

  @override
  State<_SnapToTrailsButton> createState() => _SnapToTrailsButtonState();
}

class _SnapToTrailsButtonState extends State<_SnapToTrailsButton> {
  var _snapping = false;

  Future<void> _snap() async {
    setState(() => _snapping = true);
    final outcome = await widget.store.snapRouteToTrails(widget.route);
    if (!mounted) return;
    setState(() => _snapping = false);
    final message = switch (outcome) {
      RouteSnapOutcome.updated => 'Route aligned to recognized trails.',
      RouteSnapOutcome.unchanged => 'Route unchanged.',
      RouteSnapOutcome.unavailable =>
        'No complete nearby mapped match. Route unchanged.',
      RouteSnapOutcome.failed => 'Route could not be snapped to trails.',
    };
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _snapping ? null : _snap,
      icon: _snapping
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.alt_route),
      label: const Text('Snap to trails'),
    );
  }
}
