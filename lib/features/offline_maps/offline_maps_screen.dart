import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../app/app_store.dart';
import '../../core/geo/geo_bounds.dart';
import '../../core/geo/tile_math.dart';
import '../../core/units/formatters.dart';
import '../../models/offline_area.dart';
import '../map/trail_map.dart';

class OfflineMapsScreen extends StatelessWidget {
  const OfflineMapsScreen({
    super.key,
    required this.store,
    required this.onPreview,
  });

  final AppStore store;
  final ValueChanged<OfflineArea> onPreview;

  @override
  Widget build(BuildContext context) {
    final totalBytes = store.offlineAreas.fold<int>(
      0,
      (sum, area) => sum + area.actualBytes,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline maps'),
        actions: [
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => OfflineAreaEditor(store: store),
              ),
            ),
            tooltip: 'Download area',
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: Column(
        children: [
          Card(
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: ListTile(
              leading: const Icon(Icons.storage),
              title: Text(formatBytes(totalBytes)),
              subtitle: Text(
                '${store.offlineAreas.length} saved area'
                '${store.offlineAreas.length == 1 ? '' : 's'}',
              ),
            ),
          ),
          Expanded(
            child: store.offlineAreas.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.map_outlined, size: 72),
                          const SizedBox(height: 16),
                          const Text(
                            'Select a small area and zoom range to prepare it '
                            'before heading off-grid.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => OfflineAreaEditor(store: store),
                              ),
                            ),
                            icon: const Icon(Icons.download),
                            label: const Text('Select area'),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: store.offlineAreas.length,
                    itemBuilder: (context, index) {
                      final area = store.offlineAreas[index];
                      return _AreaCard(
                        store: store,
                        area: area,
                        onPreview: onPreview,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _AreaCard extends StatelessWidget {
  const _AreaCard({
    required this.store,
    required this.area,
    required this.onPreview,
  });

  final AppStore store;
  final OfflineArea area;
  final ValueChanged<OfflineArea> onPreview;

  @override
  Widget build(BuildContext context) {
    final active = area.status == OfflineAreaStatus.downloading;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    area.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Chip(label: Text(area.status.name.toUpperCase())),
              ],
            ),
            Text(
              'Zoom ${area.minZoom}-${area.maxZoom}'
              ' • ${area.completedTiles}/${area.totalTiles} tiles'
              ' • ${formatBytes(area.actualBytes)}',
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: area.progress),
            if (area.lastError != null) ...[
              const SizedBox(height: 8),
              Text(
                area.lastError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                children: [
                  TextButton.icon(
                    onPressed: () => onPreview(area),
                    icon: const Icon(Icons.visibility_outlined),
                    label: const Text('Show on map'),
                  ),
                  if (active)
                    TextButton.icon(
                      onPressed: () => store.cancelDownload(area),
                      icon: const Icon(Icons.pause),
                      label: const Text('Pause'),
                    )
                  else if (area.status != OfflineAreaStatus.complete)
                    TextButton.icon(
                      onPressed: () => store.resumeDownload(area),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Resume'),
                    ),
                  TextButton.icon(
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Delete offline area?'),
                          content: Text(
                            '${formatBytes(area.actualBytes)} will be reclaimed. '
                            'Routes and activities are not removed.',
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
                        await store.deleteOfflineArea(area);
                      }
                    },
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete'),
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

class OfflineAreaEditor extends StatefulWidget {
  const OfflineAreaEditor({super.key, required this.store, this.area});

  final AppStore store;
  final OfflineArea? area;

  @override
  State<OfflineAreaEditor> createState() => _OfflineAreaEditorState();
}

class _OfflineAreaEditorState extends State<OfflineAreaEditor> {
  late final TextEditingController _nameController;
  LatLng? _firstCorner;
  LatLng? _secondCorner;
  RangeValues _zooms = const RangeValues(12, 15);
  var _saving = false;

  @override
  void initState() {
    super.initState();
    final area = widget.area;
    _nameController = TextEditingController(text: area?.name ?? 'Trail map');
    if (area != null) {
      _firstCorner = LatLng(area.bounds.north, area.bounds.west);
      _secondCorner = LatLng(area.bounds.south, area.bounds.east);
      _zooms = RangeValues(area.minZoom.toDouble(), area.maxZoom.toDouble());
    }
  }

  GeoBounds? get _bounds {
    final first = _firstCorner;
    final second = _secondCorner;
    return first == null || second == null
        ? null
        : GeoBounds.fromPoints(first, second);
  }

  TilePlan? get _plan {
    final bounds = _bounds;
    if (bounds == null) return null;
    try {
      return const TilePlanner(
        maxTiles: 1200,
      ).plan(bounds, _zooms.start.round(), _zooms.end.round());
    } on Object {
      return null;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    final downloadsAllowed = widget.store.mapProvider.offlineDownloadsAllowed;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.area == null ? 'Download map area' : 'Edit map area',
        ),
      ),
      body: Column(
        children: [
          if (!downloadsAllowed)
            MaterialBanner(
              content: const Text(
                'The current public map provider is not licensed for offline '
                'bulk downloads. Configure an approved provider, or explicitly '
                'enable the tiny development-only OSM override.',
              ),
              actions: const [SizedBox.shrink()],
            )
          else if (widget.store.mapProvider.isDevelopmentOsmOverride)
            MaterialBanner(
              content: const Text(
                'Development override active. Keep selections tiny. This is not '
                'a production-approved offline map configuration.',
              ),
              actions: const [SizedBox.shrink()],
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Area name',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: TrailMap(
              store: widget.store,
              selection: _bounds,
              initialCenter: widget.area?.bounds.center,
              initialZoom: widget.area?.minZoom.toDouble(),
              showControls: true,
              controlsTop: 8,
              constrainOfflineZoom: false,
              onTap: (point) {
                setState(() {
                  if (_firstCorner == null || _secondCorner != null) {
                    _firstCorner = point;
                    _secondCorner = null;
                  } else {
                    _secondCorner = point;
                  }
                });
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _bounds == null
                      ? 'Tap two opposite corners on the map.'
                      : plan == null
                      ? 'Selection exceeds the 1,200 tile safety limit.'
                      : '${plan.tileCount} tiles • about '
                            '${formatBytes(plan.estimateBytes())}',
                ),
                RangeSlider(
                  min: 8,
                  max: 17,
                  divisions: 9,
                  labels: RangeLabels(
                    '${_zooms.start.round()}',
                    '${_zooms.end.round()}',
                  ),
                  values: _zooms,
                  onChanged: (value) => setState(() => _zooms = value),
                ),
                Text(
                  'Zoom ${_zooms.start.round()}-${_zooms.end.round()}',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed:
                      _saving ||
                          !downloadsAllowed ||
                          _bounds == null ||
                          plan == null
                      ? null
                      : () async {
                          setState(() => _saving = true);
                          final area = widget.area;
                          if (area == null) {
                            await widget.store.createOfflineArea(
                              name: _nameController.text,
                              bounds: _bounds!,
                              minZoom: _zooms.start.round(),
                              maxZoom: _zooms.end.round(),
                            );
                          } else {
                            await widget.store.updateOfflineArea(
                              area: area,
                              name: _nameController.text,
                              bounds: _bounds!,
                              minZoom: _zooms.start.round(),
                              maxZoom: _zooms.end.round(),
                            );
                          }
                          if (context.mounted) Navigator.of(context).pop();
                        },
                  icon: const Icon(Icons.download),
                  label: Text(
                    widget.area == null ? 'Download' : 'Update download',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
