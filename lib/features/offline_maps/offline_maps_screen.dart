import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../app/app_store.dart';
import '../../core/geo/geo_bounds.dart';
import '../../core/geo/tile_math.dart';
import '../../core/units/formatters.dart';
import '../../models/offline_area.dart';
import '../../services/map_provider.dart';
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

String _offlineFormatLabel(OfflineSourceFormat format) => switch (format) {
  OfflineSourceFormat.rasterTiles => 'Raster tiles',
  OfflineSourceFormat.convertedVector => 'Converted vector',
};

String _offlineFormatDetail(OfflineSourceFormat format) => switch (format) {
  OfflineSourceFormat.rasterTiles => 'Raster tiles (PNG)',
  OfflineSourceFormat.convertedVector =>
    'Vector tiles rasterized on device (PNG)',
};

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
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                Chip(
                  avatar: const Icon(Icons.public, size: 16),
                  label: Text(_sourceLabel(area.providerId)),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                Chip(
                  avatar: const Icon(Icons.grid_on, size: 16),
                  label: Text(_offlineFormatLabel(area.sourceFormat)),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
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
                    onPressed: () => _showDetails(context),
                    icon: const Icon(Icons.info_outline),
                    label: const Text('Details'),
                  ),
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

  String _sourceLabel(String providerId) {
    switch (providerId) {
      case 'openstreetmap-standard':
        return 'OpenStreetMap standard';
      default:
        return providerId;
    }
  }

  void _showDetails(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => _OfflineAreaDetailsSheet(
        area: area,
        sourceLabel: _sourceLabel(area.providerId),
        onShowOnMap: () {
          Navigator.of(sheetContext).pop();
          onPreview(area);
        },
      ),
    );
  }
}

class _OfflineAreaDetailsSheet extends StatelessWidget {
  const _OfflineAreaDetailsSheet({
    required this.area,
    required this.sourceLabel,
    required this.onShowOnMap,
  });

  final OfflineArea area;
  final String sourceLabel;
  final VoidCallback onShowOnMap;

  @override
  Widget build(BuildContext context) {
    final bounds = area.bounds;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(area.name, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            _DetailRow(label: 'Status', value: area.status.name.toUpperCase()),
            _DetailRow(label: 'Source', value: sourceLabel),
            _DetailRow(
              label: 'Format',
              value: _offlineFormatDetail(area.sourceFormat),
            ),
            _DetailRow(
              label: 'Zoom range',
              value: '${area.minZoom} - ${area.maxZoom}',
            ),
            _DetailRow(
              label: 'Tiles',
              value: '${area.completedTiles} / ${area.totalTiles}',
            ),
            _DetailRow(
              label: 'Size on disk',
              value: formatBytes(area.actualBytes),
            ),
            _DetailRow(
              label: 'Bounds',
              value:
                  'N ${bounds.north.toStringAsFixed(4)}, '
                  'S ${bounds.south.toStringAsFixed(4)}\n'
                  'E ${bounds.east.toStringAsFixed(4)}, '
                  'W ${bounds.west.toStringAsFixed(4)}',
            ),
            _DetailRow(
              label: 'Created',
              value: _formatDateTime(area.createdAt),
            ),
            _DetailRow(
              label: 'Updated',
              value: _formatDateTime(area.updatedAt),
            ),
            if (area.lastError != null)
              _DetailRow(
                label: 'Last error',
                value: area.lastError!,
                valueColor: Theme.of(context).colorScheme.error,
              ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: onShowOnMap,
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Show on map'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime value) {
    final local = value.toLocal().toString();
    return local.length >= 16 ? local.substring(0, 16) : local;
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: Theme.of(context).textTheme.labelLarge),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: valueColor),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfirmRow extends StatelessWidget {
  const _ConfirmRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(label, style: Theme.of(context).textTheme.labelMedium),
          ),
          Expanded(child: Text(value)),
        ],
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
  int _maxTiles = 1200;
  late String _sourceLayerId;

  static const _tileLimits = [1200, 2500, 5000, 10000];

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
    // Default the download source to the active layer when it can be
    // downloaded, otherwise the configured downloadable provider.
    final active = widget.store.activeMapLayer;
    _sourceLayerId = active.offlineDownloadsAllowed
        ? active.id
        : widget.store.mapProvider.id;
  }

  GeoBounds? get _bounds {
    final first = _firstCorner;
    final second = _secondCorner;
    return first == null || second == null
        ? null
        : GeoBounds.fromPoints(first, second);
  }

  /// The layer the area will be downloaded from (always a downloadable one).
  MapProviderConfig get _sourceLayer => widget.store.baseLayers.firstWhere(
    (layer) => layer.id == _sourceLayerId,
    orElse: () => widget.store.mapProvider,
  );

  /// Base layers that can be viewed but not downloaded (provider licensing).
  List<MapProviderConfig> get _viewOnlyLayers => widget.store.baseLayers
      .where((layer) => !layer.offlineDownloadsAllowed)
      .toList();

  static const _minSelectableZoom = 8.0;

  double get _maxSelectableZoom => widget.store.usesVectorSource ? 14.0 : 17.0;

  RangeValues get _effectiveZooms {
    final max = _maxSelectableZoom;
    final start = _zooms.start.clamp(_minSelectableZoom, max).toDouble();
    final end = _zooms.end.clamp(_minSelectableZoom, max).toDouble();
    return RangeValues(start, end > start ? end : start);
  }

  TilePlan? get _plan {
    final bounds = _bounds;
    if (bounds == null) return null;
    try {
      return TilePlanner(maxTiles: _maxTiles).plan(
        bounds,
        _effectiveZooms.start.round(),
        _effectiveZooms.end.round(),
      );
    } on Object {
      return null;
    }
  }

  /// A rough completion-time band for [tiles]. Converting vector tiles on the
  /// device is CPU-bound and roughly sequential; raster tiles download over the
  /// network with about four workers in parallel.
  (Duration, Duration) _estimatedTime(int tiles) {
    if (widget.store.usesVectorSource) {
      return (
        Duration(milliseconds: tiles * 80),
        Duration(milliseconds: tiles * 180),
      );
    }
    return (
      Duration(milliseconds: tiles * 50),
      Duration(milliseconds: tiles * 110),
    );
  }

  String _formatShort(Duration d) {
    if (d.inSeconds < 60) return '${d.inSeconds}s';
    final minutes = d.inMinutes;
    final seconds = d.inSeconds.remainder(60);
    return seconds == 0 ? '${minutes}m' : '${minutes}m ${seconds}s';
  }

  String _estimateLabel(TilePlan plan) {
    final (low, high) = _estimatedTime(plan.tileCount);
    return '${plan.tileCount} tiles \u2022 ~${formatBytes(plan.estimateBytes())}'
        ' \u2022 ~${_formatShort(low)}\u2013${_formatShort(high)}';
  }

  String _limitLabel(int tiles) =>
      '${(tiles / 1000).toStringAsFixed(tiles % 1000 == 0 ? 0 : 1)}k';

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _editVectorSource() async {
    final controller = TextEditingController(
      text: widget.store.vectorSourceUrl,
    );
    final url = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Free vector map source'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter the URL (or local path) of an OpenMapTiles-schema MBTiles '
              'archive. The app downloads it once, then converts your selected '
              'area to offline tiles on the device.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'MBTiles URL or path',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (url != null) {
      await widget.store.setVectorSourceUrl(url);
      if (mounted) setState(() {});
    }
  }

  Future<void> _confirmDownload() async {
    final plan = _plan;
    if (plan == null) return;
    final (low, high) = _estimatedTime(plan.tileCount);
    final large = plan.tileCount > 3000;
    final name = _nameController.text.trim().isEmpty
        ? 'Offline area'
        : _nameController.text.trim();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Start download?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ConfirmRow('Area', name),
            _ConfirmRow(
              'Zoom',
              '${_effectiveZooms.start.round()}\u2013'
                  '${_effectiveZooms.end.round()}',
            ),
            _ConfirmRow('Tiles', '${plan.tileCount} (cap ${_limitLabel(_maxTiles)})'),
            _ConfirmRow('Storage', '~${formatBytes(plan.estimateBytes())}'),
            _ConfirmRow(
              'Time',
              '~${_formatShort(low)}\u2013${_formatShort(high)}',
            ),
            _ConfirmRow(
              'Source',
              '${_sourceLayer.label}: '
                  '${widget.store.usesVectorSource ? 'converted on device' : 'raster download'}',
            ),
            if (large)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'Large download: this may take a while and use significant '
                  'storage and battery.',
                  style: TextStyle(
                    color: Theme.of(dialogContext).colorScheme.error,
                  ),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.download),
            label: const Text('Start download'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _startDownload();
  }

  Future<void> _startDownload() async {
    setState(() => _saving = true);
    final area = widget.area;
    if (area == null) {
      await widget.store.createOfflineArea(
        name: _nameController.text,
        bounds: _bounds!,
        minZoom: _effectiveZooms.start.round(),
        maxZoom: _effectiveZooms.end.round(),
        maxTiles: _maxTiles,
      );
    } else {
      await widget.store.updateOfflineArea(
        area: area,
        name: _nameController.text,
        bounds: _bounds!,
        minZoom: _effectiveZooms.start.round(),
        maxZoom: _effectiveZooms.end.round(),
        maxTiles: _maxTiles,
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    final downloadsAllowed = widget.store.offlineDownloadsAllowed;
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Download source',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final layer in widget.store.baseLayers)
                      ChoiceChip(
                        label: Text(layer.label),
                        avatar: Icon(
                          layer.offlineDownloadsAllowed
                              ? Icons.download_for_offline_outlined
                              : Icons.visibility_outlined,
                          size: 18,
                        ),
                        selected: _sourceLayerId == layer.id,
                        onSelected: layer.offlineDownloadsAllowed
                            ? (_) =>
                                  setState(() => _sourceLayerId = layer.id)
                            : null,
                      ),
                  ],
                ),
                if (_viewOnlyLayers.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${_viewOnlyLayers.map((layer) => layer.label).join(', ')}'
                      ' can be viewed but not downloaded (the provider does not '
                      'permit offline caching).',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.store.usesVectorSource
                              ? 'Converted on device from the free vector '
                                    'source.'
                              : 'Downloads use the raster provider.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _editVectorSource,
                        icon: const Icon(Icons.tune, size: 18),
                        label: Text(
                          widget.store.usesVectorSource
                              ? 'Change'
                              : 'Set source',
                        ),
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
              selection: _bounds,
              selectionStart: _firstCorner,
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
                if (_bounds == null)
                  const Text('Tap two opposite corners on the map.')
                else if (plan == null)
                  Text(
                    'Selection exceeds the ${_limitLabel(_maxTiles)} tile cap '
                    '\u2014 raise the cap below or shrink the area/zoom.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  )
                else
                  Text(
                    _estimateLabel(plan),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                RangeSlider(
                  min: _minSelectableZoom,
                  max: _maxSelectableZoom,
                  divisions: (_maxSelectableZoom - _minSelectableZoom).round(),
                  labels: RangeLabels(
                    '${_effectiveZooms.start.round()}',
                    '${_effectiveZooms.end.round()}',
                  ),
                  values: _effectiveZooms,
                  onChanged: (value) => setState(() => _zooms = value),
                ),
                Text(
                  widget.store.usesVectorSource
                      ? 'Zoom ${_effectiveZooms.start.round()}-'
                            '${_effectiveZooms.end.round()} (vector max 14)'
                      : 'Zoom ${_effectiveZooms.start.round()}-'
                            '${_effectiveZooms.end.round()}',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      'Max tiles',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SegmentedButton<int>(
                          showSelectedIcon: false,
                          segments: [
                            for (final limit in _tileLimits)
                              ButtonSegment(
                                value: limit,
                                label: Text(_limitLabel(limit)),
                              ),
                          ],
                          selected: {_maxTiles},
                          onSelectionChanged: (selection) =>
                              setState(() => _maxTiles = selection.first),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed:
                      _saving ||
                          !downloadsAllowed ||
                          _bounds == null ||
                          plan == null
                      ? null
                      : _confirmDownload,
                  icon: const Icon(Icons.download),
                  label: Text(
                    widget.area == null
                        ? 'Review & download'
                        : 'Review & update',
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
