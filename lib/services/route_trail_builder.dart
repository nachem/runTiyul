import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../core/geo/distance.dart';
import '../core/geo/geo_bounds.dart';
import '../core/geo/polyline_snap.dart';
import '../core/geo/tile_math.dart';
import 'route_snapper.dart';
import 'trail_extractor.dart';
import 'trail_network.dart';
import 'trail_network_cache.dart';
import 'trail_router.dart';
import 'vector_tile_source.dart';

/// The result of snapping a route onto nearby trails.
class RouteTrailResult {
  const RouteTrailResult({
    required this.snapped,
    required this.network,
    required this.changed,
    this.matched = true,
  });

  /// The route after snapping (equal to the input when nothing was snapped).
  final List<LatLng> snapped;

  /// The trail network built for the route's corridor (usable for junctions).
  final TrailNetwork network;

  /// Whether snapping changed the route.
  final bool changed;
  final bool matched;
}

class _MatchState {
  const _MatchState(
    this.anchor,
    this.cost, {
    this.previous,
    this.leg = const [],
  });

  final TrailAnchor anchor;
  final double cost;
  final _MatchState? previous;
  final List<LatLng> leg;
}

/// Downloads the minimal vector data covering a route, extracts the trail
/// network around it, and snaps the route onto nearby real trails.
///
/// Only the tiles the route passes through (plus a one-tile buffer) are
/// fetched, so "saving a trail event" pulls a small amount of data rather than
/// a whole offline area.
class RouteTrailBuilder {
  RouteTrailBuilder({
    this.zoom = 14,
    this.extractor = const TrailExtractor(),
    this.snapper = const RouteSnapper(),
    this.distance = const GeoDistance(),
    TrailNetworkCache? cache,
    Future<VectorTileSource> Function(String source)? openSource,
  }) : cache = cache ?? TrailNetworkCache(),
       _openSource = openSource ?? _defaultOpenSource;

  final int zoom;
  final TrailExtractor extractor;
  final RouteSnapper snapper;
  final GeoDistance distance;
  final TrailNetworkCache cache;
  final Future<VectorTileSource> Function(String source) _openSource;

  static Future<VectorTileSource> _defaultOpenSource(String source) async {
    if (HttpVectorTileSource.looksLikeTileUrl(source)) {
      return HttpVectorTileSource.open(source);
    }
    final file = await VectorSourceStore.ensureLocal(source);
    return MbtilesVectorTileSource.openFile(file);
  }

  /// The tiles covering [route] at [zoom], including a [buffer]-tile ring, so a
  /// trail slightly off the drawn line is still captured.
  List<TileCoordinate> tilesForRoute(List<LatLng> route, {int buffer = 1}) {
    final tiles = <TileCoordinate>{};
    final n = 1 << zoom;

    void addAround(LatLng point) {
      final (tx, ty) = _tileOf(point);
      for (var dx = -buffer; dx <= buffer; dx++) {
        for (var dy = -buffer; dy <= buffer; dy++) {
          final x = tx + dx;
          final y = ty + dy;
          if (x < 0 || y < 0 || x >= n || y >= n) continue;
          tiles.add(TileCoordinate(zoom, x, y));
        }
      }
    }

    for (var i = 0; i < route.length; i++) {
      addAround(route[i]);
      if (i > 0) {
        final a = route[i - 1];
        final b = route[i];
        final steps = (distance.metersBetween(a, b) / 500).ceil();
        for (var s = 1; s < steps; s++) {
          final f = s / steps;
          addAround(
            LatLng(
              a.latitude + (b.latitude - a.latitude) * f,
              a.longitude + (b.longitude - a.longitude) * f,
            ),
          );
        }
      }
    }
    return tiles.toList(growable: false);
  }

  /// The z[zoom] tiles covering [bounds] (inclusive), capped at [maxTiles] to
  /// bound network and CPU when a large area is in view.
  List<TileCoordinate> tilesForBounds(GeoBounds bounds, {int maxTiles = 24}) {
    final (minX, minY) = _tileOf(LatLng(bounds.north, bounds.west));
    final (maxX, maxY) = _tileOf(LatLng(bounds.south, bounds.east));
    final left = math.min(minX, maxX);
    final right = math.max(minX, maxX);
    final top = math.min(minY, maxY);
    final bottom = math.max(minY, maxY);
    final tileCount = (right - left + 1) * (bottom - top + 1);
    final tiles = <TileCoordinate>[];
    if (tileCount <= maxTiles) {
      for (var x = left; x <= right; x++) {
        for (var y = top; y <= bottom; y++) {
          tiles.add(TileCoordinate(zoom, x, y));
        }
      }
      return tiles;
    }

    final (centerX, centerY) = _tileOf(bounds.center);
    for (var radius = 0; tiles.length < maxTiles; radius++) {
      for (var x = centerX - radius; x <= centerX + radius; x++) {
        for (var y = centerY - radius; y <= centerY + radius; y++) {
          if (math.max((x - centerX).abs(), (y - centerY).abs()) != radius ||
              x < left ||
              x > right ||
              y < top ||
              y > bottom) {
            continue;
          }
          tiles.add(TileCoordinate(zoom, x, y));
          if (tiles.length >= maxTiles) return tiles;
        }
      }
    }
    return tiles;
  }

  /// The z[zoom] tiles immediately surrounding [point]. Unlike viewport
  /// loading, this stays bounded even when the map is zoomed far out.
  List<TileCoordinate> tilesNearPoint(LatLng point, {int radius = 1}) {
    final (centerX, centerY) = _tileOf(point);
    final n = 1 << zoom;
    final tiles = <TileCoordinate>[];
    for (var x = centerX - radius; x <= centerX + radius; x++) {
      for (var y = centerY - radius; y <= centerY + radius; y++) {
        if (x < 0 || y < 0 || x >= n || y >= n) continue;
        tiles.add(TileCoordinate(zoom, x, y));
      }
    }
    return tiles;
  }

  /// Whether the bounded neighborhoods used by interactive route editing can
  /// overlap. When they cannot, loading only the distant endpoint would create
  /// disconnected graphs and could never produce a trail-following leg.
  bool canLoadInteractiveLeg(LatLng from, LatLng to) {
    final fromTiles = tilesNearPoint(from).toSet();
    return tilesNearPoint(to).any(fromTiles.contains);
  }

  (int, int) _tileOf(LatLng point) {
    final n = 1 << zoom;
    final x = ((point.longitude + 180) / 360 * n).floor().clamp(0, n - 1);
    final latRad = point.latitude * math.pi / 180;
    final y =
        ((1 - math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) /
                2 *
                n)
            .floor()
            .clamp(0, n - 1);
    return (x, y);
  }

  /// Builds the trail network for [route] by reading the covering tiles from
  /// the vector source at [sourceUrl].
  Future<TrailNetwork> buildNetwork(
    List<LatLng> route,
    String sourceUrl, {
    bool allowNetwork = true,
  }) async {
    if (route.length < 2 || sourceUrl.isEmpty) return const TrailNetwork([]);
    final tiles = tilesForRoute(route);
    if (tiles.length > 256) {
      throw StateError(
        'Route exceeds the local routing-data limit. Split it into shorter routes.',
      );
    }
    return _readNetwork(tiles, sourceUrl, allowNetwork: allowNetwork);
  }

  /// Builds the trail network covering [bounds] by reading its covering tiles
  /// from the vector source at [sourceUrl]. Used to power tap-to-follow route
  /// building over the currently-viewed map area.
  Future<TrailNetwork> networkForBounds(
    GeoBounds bounds,
    String sourceUrl, {
    bool allowNetwork = true,
    bool Function()? isCancelled,
  }) => _readNetwork(
    tilesForBounds(bounds),
    sourceUrl,
    allowNetwork: allowNetwork,
    isCancelled: isCancelled,
  );

  /// Builds a small trail network around [point]. Route editing uses this as
  /// an on-demand fallback when a tap falls outside the viewport network.
  Future<TrailNetwork> networkNearPoint(
    LatLng point,
    String sourceUrl, {
    bool allowNetwork = true,
  }) => _readNetwork(
    tilesNearPoint(point),
    sourceUrl,
    allowNetwork: allowNetwork,
  );

  Future<TrailNetwork> _readNetwork(
    List<TileCoordinate> tiles,
    String sourceUrl, {
    required bool allowNetwork,
    bool Function()? isCancelled,
  }) async {
    if (sourceUrl.isEmpty) return const TrailNetwork([]);
    VectorTileSource? source;
    final classes = extractor.trailClasses.toList()..sort();
    final cacheSource = 'routing-v2|${classes.join(',')}|$sourceUrl';
    final uri = Uri.tryParse(sourceUrl);
    final remote = uri?.scheme == 'http' || uri?.scheme == 'https';
    try {
      final trails = <TrailPolyline>[];
      for (final tile in tiles) {
        if (isCancelled?.call() == true) break;
        final cached = await cache.read(cacheSource, tile);
        if (cached != null) {
          trails.addAll(cached);
          continue;
        }
        if ((!allowNetwork && remote) || isCancelled?.call() == true) continue;
        source ??= await _openSource(sourceUrl);
        if (tile.z < source.minZoom || tile.z > source.maxZoom) continue;
        final bytes = await source.readTile(tile.z, tile.x, tile.y);
        final extracted = bytes == null || bytes.isEmpty
            ? <TrailPolyline>[]
            : extractor.extractFromBytes(bytes, tile.z, tile.x, tile.y);
        await cache.write(cacheSource, tile, extracted);
        trails.addAll(extracted);
      }
      return const TrailNetwork([]).merge(TrailNetwork(trails));
    } finally {
      await source?.close();
    }
  }

  /// Builds the network and snaps [route] onto it. Returns the original route
  /// unchanged when no trails are found nearby.
  Future<RouteTrailResult> snapToTrails(
    List<LatLng> route,
    String sourceUrl, {
    bool allowNetwork = true,
  }) async {
    final network = await buildNetwork(
      route,
      sourceUrl,
      allowNetwork: allowNetwork,
    );
    if (network.isEmpty) {
      return RouteTrailResult(
        snapped: route,
        network: network,
        changed: false,
        matched: false,
      );
    }
    final refined = matchOnNetwork(route, network);
    return RouteTrailResult(
      snapped: refined ?? route,
      network: network,
      changed: refined != null && _differs(route, refined),
      matched: refined != null,
    );
  }

  /// RTE-011: every observation must have a connected, nearby mapped match.
  /// Failure preserves the complete input, never a partially snapped line.
  List<LatLng> refineOntoNetwork(List<LatLng> route, TrailNetwork network) =>
      matchOnNetwork(route, network) ?? route;

  List<LatLng>? matchOnNetwork(List<LatLng> route, TrailNetwork network) {
    if (route.length < 2 || network.isEmpty) return null;
    final router = TrailRouter(network);
    final observations = <int>[0];
    var accumulated = 0.0;
    for (var index = 1; index < route.length; index++) {
      accumulated += distance.metersBetween(route[index - 1], route[index]);
      if (accumulated >= 20 || index == route.length - 1) {
        observations.add(index);
        accumulated = 0;
      }
    }
    var states = [
      for (final anchor in router.snapCandidates(route.first))
        _MatchState(anchor, anchor.distanceMeters),
    ];
    for (
      var observation = 1;
      observation < observations.length;
      observation++
    ) {
      if (states.isEmpty) return null;
      final input = route.sublist(
        observations[observation - 1],
        observations[observation] + 1,
      );
      final inputLength = distance.pathLengthMeters(input);
      final nextStates = <_MatchState>[];
      for (final anchor in router.snapCandidates(input.last)) {
        _MatchState? best;
        for (final previous in states) {
          final leg = router.buildConnectedLeg(previous.anchor, anchor);
          if (leg == null || !_withinMatchingCorridor(leg, input)) continue;
          final length = distance.pathLengthMeters(leg);
          if (length > inputLength * 3 + 40) continue;
          final cost =
              previous.cost +
              anchor.distanceMeters +
              (length - inputLength).abs();
          if (best == null || cost < best.cost) {
            best = _MatchState(anchor, cost, previous: previous, leg: leg);
          }
        }
        if (best != null) nextStates.add(best);
      }
      states = nextStates;
    }
    if (states.isEmpty) return null;
    states.sort((left, right) => left.cost.compareTo(right.cost));
    final legs = <List<LatLng>>[];
    for (
      _MatchState? current = states.first;
      current?.previous != null;
      current = current.previous
    ) {
      legs.add(current!.leg);
    }
    final result = <LatLng>[];
    for (final leg in legs.reversed) {
      for (final point in leg) {
        if (result.isEmpty ||
            distance.metersBetween(result.last, point) > 0.01) {
          result.add(point);
        }
      }
    }
    return result.length < 2 ? null : result;
  }

  bool _withinMatchingCorridor(List<LatLng> leg, List<LatLng> input) {
    const maxDeviationMeters = 40.0;
    for (final point in input) {
      if ((nearestOnPolyline(point, leg)?.distanceMeters ?? double.infinity) >
          maxDeviationMeters) {
        return false;
      }
    }
    for (var index = 1; index < leg.length; index++) {
      final from = leg[index - 1];
      final to = leg[index];
      final steps = math.max(1, (distance.metersBetween(from, to) / 20).ceil());
      for (var step = 0; step <= steps; step++) {
        final fraction = step / steps;
        final point = LatLng(
          from.latitude + (to.latitude - from.latitude) * fraction,
          from.longitude + (to.longitude - from.longitude) * fraction,
        );
        if ((nearestOnPolyline(point, input)?.distanceMeters ??
                double.infinity) >
            maxDeviationMeters) {
          return false;
        }
      }
    }
    return true;
  }

  bool _differs(List<LatLng> a, List<LatLng> b) {
    if (a.length != b.length) return true;
    for (var i = 0; i < a.length; i++) {
      if (distance.metersBetween(a[i], b[i]) > 1) return true;
    }
    return false;
  }
}
