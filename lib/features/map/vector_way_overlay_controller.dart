import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/geo/geo_bounds.dart';
import '../../services/route_trail_builder.dart';
import '../../services/trail_network.dart';

class VectorWayOverlayController extends ChangeNotifier {
  VectorWayOverlayController(
    this.builder, {
    this.debounce = const Duration(milliseconds: 300),
  });

  static const minZoom = 14.0;
  final RouteTrailBuilder builder;
  final Duration debounce;
  bool enabled = false;
  bool loading = false;
  double zoom = 0;
  String? error;
  TrailNetwork network = const TrailNetwork([]);
  GeoBounds? _bounds;
  String _source = '';
  bool _allowNetwork = true;
  String? _requestKey;
  Timer? _timer;
  int _generation = 0;
  bool _disposed = false;
  bool _loadInFlight = false;
  ({GeoBounds bounds, String source, bool allowNetwork, int generation})?
  _pending;

  bool get visible => enabled && zoom >= minZoom;

  String? get status => !enabled
      ? null
      : !visible
      ? 'Vector ways hidden at this zoom'
      : loading
      ? 'Loading vector ways'
      : error ??
            (network.isEmpty
                ? (_allowNetwork
                      ? 'No vector ways here'
                      : 'No cached vector ways here')
                : null);

  void setEnabled(bool value) {
    enabled = value;
    _requestKey = null;
    _schedule();
  }

  void update({
    required GeoBounds bounds,
    required double zoom,
    required String source,
    required bool allowNetwork,
  }) {
    _bounds = bounds;
    this.zoom = zoom;
    _source = source;
    _allowNetwork = allowNetwork;
    _schedule();
  }

  void _schedule() {
    final bounds = _bounds;
    if (!visible || bounds == null || _source.isEmpty) {
      _generation++;
      _timer?.cancel();
      _pending = null;
      _requestKey = null;
      loading = false;
      network = const TrailNetwork([]);
      error = visible && _source.isEmpty ? 'No vector source configured' : null;
      if (!_disposed) notifyListeners();
      return;
    }
    final key =
        '$_source|$_allowNetwork|${builder.tilesForBounds(bounds).map((tile) => tile.key).join(',')}';
    if (key == _requestKey) return;
    _requestKey = key;
    final generation = ++_generation;
    _timer?.cancel();
    loading = true;
    error = null;
    network = const TrailNetwork([]);
    notifyListeners();
    _timer = Timer(debounce, () {
      _pending = (
        bounds: bounds,
        source: _source,
        allowNetwork: _allowNetwork,
        generation: generation,
      );
      if (!_loadInFlight) unawaited(_runPending());
    });
  }

  Future<void> _runPending() async {
    final request = _pending;
    if (request == null || _disposed) return;
    _pending = null;
    _loadInFlight = true;
    try {
      await _load(
        request.bounds,
        request.source,
        request.allowNetwork,
        request.generation,
      );
    } finally {
      _loadInFlight = false;
      if (_pending != null && !_disposed) unawaited(_runPending());
    }
  }

  Future<void> _load(
    GeoBounds bounds,
    String source,
    bool allowNetwork,
    int generation,
  ) async {
    try {
      final loaded = await builder.networkForBounds(
        bounds,
        source,
        allowNetwork: allowNetwork,
        isCancelled: () => _disposed || generation != _generation,
      );
      if (_disposed || generation != _generation) return;
      network = loaded;
    } on Object {
      if (_disposed || generation != _generation) return;
      error = 'Vector ways unavailable';
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    _pending = null;
    super.dispose();
  }
}
