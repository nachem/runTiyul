import 'dart:async';

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
          if (store.offlineAreas.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Row(
                children: [
                  Icon(
                    Icons.swap_vert,
                    size: 16,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Drag to reorder. The top map is drawn over lower maps '
                      'where they overlap.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
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
                : ReorderableListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    itemCount: store.offlineAreas.length,
                    onReorderItem: (oldIndex, newIndex) =>
                        store.reorderOfflineAreas(oldIndex, newIndex),
                    itemBuilder: (context, index) {
                      final area = store.offlineAreas[index];
                      return _AreaCard(
                        key: ValueKey(area.id),
                        store: store,
                        area: area,
                        onPreview: onPreview,
                        dragHandle: ReorderableDragStartListener(
                          index: index,
                          child: const Icon(Icons.drag_handle),
                        ),
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
  OfflineSourceFormat.convertedVector => 'Topographic vector',
};

String _offlineFormatDetail(OfflineSourceFormat format) => switch (format) {
  OfflineSourceFormat.rasterTiles => 'Raster tiles (PNG)',
  OfflineSourceFormat.convertedVector =>
    'Vector tiles with baked contours + hillshade (PNG)',
};

class _AreaCard extends StatelessWidget {
  const _AreaCard({
    required this.store,
    required this.area,
    required this.onPreview,
    this.dragHandle,
    super.key,
  });

  final AppStore store;
  final OfflineArea area;
  final ValueChanged<OfflineArea> onPreview;

  /// A drag affordance shown in the card header when the list is reorderable.
  final Widget? dragHandle;

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
                if (dragHandle != null) ...[
                  const SizedBox(width: 4),
                  dragHandle!,
                ],
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
    final configured = store.mapProviderById(providerId);
    if (configured != null) return configured.label;
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

/// The two user-facing offline source modes. Unavailable modes stay visible so
/// the release developer unlock can be discovered deliberately without making
/// view-only providers appear downloadable.
class OfflineDownloadSourcePicker extends StatelessWidget {
  const OfflineDownloadSourcePicker({
    super.key,
    required this.vectorAvailable,
    required this.activeMapLayer,
    required this.currentMapDownloadAllowed,
    required this.selectedFormat,
    required this.onSelected,
    this.onLockedCurrentMapTap,
  });

  final bool vectorAvailable;
  final MapProviderConfig activeMapLayer;
  final bool currentMapDownloadAllowed;
  final OfflineSourceFormat selectedFormat;
  final ValueChanged<OfflineSourceFormat> onSelected;
  final VoidCallback? onLockedCurrentMapTap;

  @override
  Widget build(BuildContext context) {
    final devSuffix = activeMapLayer.isDevelopmentOsmOverride
        ? ' \u00b7 DEV'
        : '';
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        ChoiceChip(
          key: const ValueKey('download-source-vector'),
          avatar: const Icon(Icons.layers_outlined, size: 18),
          label: const Text('MBTiles / vector'),
          selected: selectedFormat == OfflineSourceFormat.convertedVector,
          onSelected: vectorAvailable
              ? (_) => onSelected(OfflineSourceFormat.convertedVector)
              : null,
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: currentMapDownloadAllowed ? null : onLockedCurrentMapTap,
          child: ChoiceChip(
            key: const ValueKey('download-source-current-map'),
            avatar: const Icon(Icons.map_outlined, size: 18),
            label: Text('Current map: ${activeMapLayer.label}$devSuffix'),
            selected: selectedFormat == OfflineSourceFormat.rasterTiles,
            onSelected: currentMapDownloadAllowed
                ? (_) => onSelected(OfflineSourceFormat.rasterTiles)
                : null,
          ),
        ),
      ],
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
  late OfflineSourceFormat _selectedFormat;
  int _publicRasterUnlockTaps = 0;
  Timer? _publicRasterUnlockResetTimer;

  static const _tileLimits = [1200, 2500, 5000, 10000];

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_handleStoreChanged);
    final area = widget.area;
    _nameController = TextEditingController(text: area?.name ?? 'Trail map');
    if (area != null) {
      _firstCorner = LatLng(area.bounds.north, area.bounds.west);
      _secondCorner = LatLng(area.bounds.south, area.bounds.east);
      _zooms = RangeValues(area.minZoom.toDouble(), area.maxZoom.toDouble());
    }
    // Default to the area's existing format when editing, otherwise on-device
    // vector conversion when a vector source is configured.
    final preferred =
        area?.sourceFormat ??
        (widget.store.usesVectorSource
            ? OfflineSourceFormat.convertedVector
            : OfflineSourceFormat.rasterTiles);
    _selectedFormat = preferred;
    if (_selectedFormat == OfflineSourceFormat.convertedVector &&
        !widget.store.usesVectorSource) {
      _selectedFormat = OfflineSourceFormat.rasterTiles;
    } else if (_selectedFormat == OfflineSourceFormat.rasterTiles &&
        _currentRasterProvider == null &&
        widget.store.usesVectorSource) {
      _selectedFormat = OfflineSourceFormat.convertedVector;
    }
  }

  void _handleStoreChanged() {
    if (!mounted) return;
    setState(() {
      if (_selectedFormat == OfflineSourceFormat.rasterTiles &&
          _currentRasterProvider == null &&
          widget.store.usesVectorSource) {
        _selectedFormat = OfflineSourceFormat.convertedVector;
      }
    });
  }

  /// True when the selected format converts free vector tiles on the device.
  bool get _usesVector =>
      _selectedFormat == OfflineSourceFormat.convertedVector;

  MapProviderConfig? get _currentRasterProvider {
    final active = widget.store.activeMapLayer;
    for (final provider in widget.store.rasterDownloadProviders) {
      if (provider.id == active.id) return provider;
    }
    return null;
  }

  bool get _isDevRaster =>
      !_usesVector &&
      (_currentRasterProvider?.isDevelopmentOsmOverride ?? false);

  Future<void> _handleLockedCurrentMapTap() async {
    final active = widget.store.activeMapLayer;
    if (!active.isPublicDevelopmentRaster) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${active.label} is view-only and its provider does not allow '
            'offline caching. Select Streets/CyclOSM or use MBTiles / vector.',
          ),
        ),
      );
      return;
    }
    if (!widget.store.publicRasterDevUnlockAvailable) return;

    _publicRasterUnlockResetTimer?.cancel();
    _publicRasterUnlockTaps++;
    _publicRasterUnlockResetTimer = Timer(const Duration(seconds: 4), () {
      _publicRasterUnlockTaps = 0;
    });
    final remaining = 7 - _publicRasterUnlockTaps;
    if (remaining > 0) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            duration: const Duration(milliseconds: 650),
            content: Text(
              'Developer raster unlock: $remaining more '
              'tap${remaining == 1 ? '' : 's'}.',
            ),
          ),
        );
      return;
    }

    _publicRasterUnlockResetTimer?.cancel();
    _publicRasterUnlockTaps = 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enable developer raster downloads?'),
        content: const Text(
          'Public OpenStreetMap and CyclOSM tile services are not production '
          'offline-download backends. Enable this only for small development '
          'tests. The developer unlock will remain enabled on this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Enable DEV downloads'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final enabled = await widget.store.enablePublicRasterDevDownloads();
    if (!mounted || !enabled) return;
    setState(() => _selectedFormat = OfflineSourceFormat.rasterTiles);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Developer raster downloads enabled on this device.'),
      ),
    );
  }

  GeoBounds? get _bounds {
    final first = _firstCorner;
    final second = _secondCorner;
    return first == null || second == null
        ? null
        : GeoBounds.fromPoints(first, second);
  }

  static const _minSelectableZoom = 8.0;

  double get _maxSelectableZoom => _usesVector ? 16.0 : 17.0;

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
    if (_usesVector) {
      return (
        Duration(milliseconds: tiles * 120),
        Duration(milliseconds: tiles * 300),
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

  String get _downloadTitle => _usesVector
      ? 'Topographic vector map \u2014 converted on device'
      : '${widget.store.activeMapLayer.label} raster';

  String get _downloadSubtitle {
    if (_usesVector) {
      return 'Vector data is rendered on device with contours and hillshade '
          'baked into each offline tile. Raw height data is not retained.';
    }
    if (_currentRasterProvider == null) {
      return 'The current map layer cannot be downloaded. Select Streets or '
          'CyclOSM with the map-layer button, or use MBTiles / vector.';
    }
    if (_currentRasterProvider!.id == 'cyclosm') {
      return 'CyclOSM tiles already include provider-rendered topography; no '
          'separate height data is downloaded.';
    }
    return 'Per-tile raster download with no separate height data.';
  }

  @override
  void dispose() {
    _publicRasterUnlockResetTimer?.cancel();
    widget.store.removeListener(_handleStoreChanged);
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
      if (mounted) {
        setState(() {
          if (!widget.store.usesVectorSource &&
              _selectedFormat == OfflineSourceFormat.convertedVector) {
            _selectedFormat = OfflineSourceFormat.rasterTiles;
          }
        });
      }
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
            _ConfirmRow(
              'Tiles',
              '${plan.tileCount} (cap ${_limitLabel(_maxTiles)})',
            ),
            _ConfirmRow('Storage', '~${formatBytes(plan.estimateBytes())}'),
            _ConfirmRow(
              'Time',
              '~${_formatShort(low)}\u2013${_formatShort(high)}',
            ),
            _ConfirmRow('Source', _downloadTitle),
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
    final rasterProvider = _currentRasterProvider;
    if (!_usesVector && rasterProvider == null) {
      if (mounted) setState(() => _saving = false);
      return;
    }
    final area = widget.area;
    if (area == null) {
      await widget.store.createOfflineArea(
        name: _nameController.text,
        bounds: _bounds!,
        minZoom: _effectiveZooms.start.round(),
        maxZoom: _effectiveZooms.end.round(),
        maxTiles: _maxTiles,
        format: _selectedFormat,
        providerId: _usesVector
            ? widget.store.mapProvider.id
            : rasterProvider!.id,
      );
    } else {
      await widget.store.updateOfflineArea(
        area: area,
        name: _nameController.text,
        bounds: _bounds!,
        minZoom: _effectiveZooms.start.round(),
        maxZoom: _effectiveZooms.end.round(),
        maxTiles: _maxTiles,
        format: _selectedFormat,
        providerId: _usesVector
            ? widget.store.mapProvider.id
            : rasterProvider!.id,
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    final downloadsAllowed = _usesVector
        ? widget.store.usesVectorSource
        : _currentRasterProvider != null;
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
            ),
          // The map is the primary surface for picking the two corners, so it
          // takes the majority of the screen.
          Expanded(
            flex: 3,
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
          // All settings live in one compact, scrollable panel beneath the map
          // so they never crowd it out on small screens. The primary action is
          // pinned to the bottom of the panel so it is always reachable.
          Expanded(
            flex: 2,
            child: Material(
              elevation: 8,
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Download source',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const SizedBox(height: 6),
                          OfflineDownloadSourcePicker(
                            vectorAvailable: widget.store.usesVectorSource,
                            activeMapLayer: widget.store.activeMapLayer,
                            currentMapDownloadAllowed:
                                _currentRasterProvider != null,
                            selectedFormat: _selectedFormat,
                            onSelected: (format) =>
                                setState(() => _selectedFormat = format),
                            onLockedCurrentMapTap: _handleLockedCurrentMapTap,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _downloadSubtitle,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (_isDevRaster)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'DEV only: keep public-raster downloads small; '
                                'not licensed for production offline use.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    widget.store.usesVectorSource
                                        ? 'Vector source: '
                                              '${widget.store.vectorSourceUrl}'
                                        : 'No vector/MBTiles source set.',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
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
                          const Divider(height: 24),
                          if (_bounds == null)
                            const Text('Tap two opposite corners on the map.')
                          else if (plan == null)
                            Text(
                              'Selection exceeds the '
                              '${_limitLabel(_maxTiles)} tile cap \u2014 raise '
                              'the cap below or shrink the area/zoom.',
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
                            divisions: (_maxSelectableZoom - _minSelectableZoom)
                                .round(),
                            labels: RangeLabels(
                              '${_effectiveZooms.start.round()}',
                              '${_effectiveZooms.end.round()}',
                            ),
                            values: _effectiveZooms,
                            onChanged: (value) =>
                                setState(() => _zooms = value),
                          ),
                          Text(
                            _usesVector
                                ? 'Zoom ${_effectiveZooms.start.round()}-'
                                      '${_effectiveZooms.end.round()} '
                                      '(vector z14 source, sharpened)'
                                : 'Zoom ${_effectiveZooms.start.round()}-'
                                      '${_effectiveZooms.end.round()}',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
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
                                    onSelectionChanged: (selection) => setState(
                                      () => _maxTiles = selection.first,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              labelText: 'Area name',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: SafeArea(
                      top: false,
                      child: FilledButton.icon(
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
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
