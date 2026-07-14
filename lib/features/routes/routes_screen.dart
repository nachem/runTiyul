import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../app/app_store.dart';
import '../../core/units/formatters.dart';
import '../../models/trail_route.dart';
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
  const ManualRouteEditor({super.key, required this.store});

  final AppStore store;

  @override
  State<ManualRouteEditor> createState() => _ManualRouteEditorState();
}

class _ManualRouteEditorState extends State<ManualRouteEditor> {
  final _nameController = TextEditingController();
  final List<LatLng> _points = [];
  var _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create route'),
        actions: [
          IconButton(
            onPressed: _points.isEmpty
                ? null
                : () => setState(() => _points.removeLast()),
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
          Expanded(
            child: TrailMap(
              store: widget.store,
              waypoints: _points,
              onTap: (point) => setState(() => _points.add(point)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(child: Text('${_points.length} waypoints')),
                FilledButton.icon(
                  onPressed: _saving || _points.length < 2
                      ? null
                      : () async {
                          setState(() => _saving = true);
                          await widget.store.saveManualRoute(
                            _nameController.text,
                            _points,
                          );
                          if (context.mounted) Navigator.of(context).pop();
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
            child: TrailMap(store: store, route: route, showControls: true),
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
