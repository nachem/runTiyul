import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../core/geo/distance.dart';
import '../core/geo/geo_bounds.dart';
import '../core/geo/tile_math.dart';
import 'route_snapper.dart';
import 'trail_extractor.dart';
import 'trail_network.dart';
import 'trail_router.dart';
import 'vector_tile_source.dart';

/// The result of snapping a route onto nearby trails.
class RouteTrailResult {
  const RouteTrailResult({
    required this.snapped,
    required this.network,
    required this.changed,
  });

  /// The route after snapping (equal to the input when nothing was snapped).
  final List<LatLng> snapped;

  /// The trail network built for the route's corridor (usable for junctions).
  final TrailNetwork network;

  /// Whether snapping changed the route.
  final bool changed;
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
    Future<VectorTileSource> Function(String source)? openSource,
  }) : _openSource = openSource ?? _defaultOpenSource;

  final int zoom;
  final TrailExtractor extractor;
  final RouteSnapper snapper;
  final GeoDistance distance;
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
    String sourceUrl,
  ) async {
    if (route.length < 2 || sourceUrl.isEmpty) return const TrailNetwork([]);
    final source = await _openSource(sourceUrl);
    try {
      final trails = <TrailPolyline>[];
      for (final tile in tilesForRoute(route)) {
        if (tile.z < source.minZoom || tile.z > source.maxZoom) continue;
        final bytes = await source.readTile(tile.z, tile.x, tile.y);
        if (bytes == null || bytes.isEmpty) continue;
        trails.addAll(
          extractor.extractFromBytes(bytes, tile.z, tile.x, tile.y),
        );
      }
      return TrailNetwork(trails);
    } finally {
      await source.close();
    }
  }

  /// Builds the trail network covering [bounds] by reading its covering tiles
  /// from the vector source at [sourceUrl]. Used to power tap-to-follow route
  /// building over the currently-viewed map area.
  Future<TrailNetwork> networkForBounds(
    GeoBounds bounds,
    String sourceUrl,
  ) async {
    if (sourceUrl.isEmpty) return const TrailNetwork([]);
    final source = await _openSource(sourceUrl);
    try {
      final trails = <TrailPolyline>[];
      for (final tile in tilesForBounds(bounds)) {
        if (tile.z < source.minZoom || tile.z > source.maxZoom) continue;
        final bytes = await source.readTile(tile.z, tile.x, tile.y);
        if (bytes == null || bytes.isEmpty) continue;
        trails.addAll(
          extractor.extractFromBytes(bytes, tile.z, tile.x, tile.y),
        );
      }
      return TrailNetwork(trails);
    } finally {
      await source.close();
    }
  }

  /// Builds a small trail network around [point]. Route editing uses this as
  /// an on-demand fallback when a tap falls outside the viewport network.
  Future<TrailNetwork> networkNearPoint(LatLng point, String sourceUrl) async {
    if (sourceUrl.isEmpty) return const TrailNetwork([]);
    final source = await _openSource(sourceUrl);
    try {
      final trails = <TrailPolyline>[];
      for (final tile in tilesNearPoint(point)) {
        if (tile.z < source.minZoom || tile.z > source.maxZoom) continue;
        final bytes = await source.readTile(tile.z, tile.x, tile.y);
        if (bytes == null || bytes.isEmpty) continue;
        trails.addAll(
          extractor.extractFromBytes(bytes, tile.z, tile.x, tile.y),
        );
      }
      return TrailNetwork(trails);
    } finally {
      await source.close();
    }
  }

  /// Builds the network and snaps [route] onto it. Returns the original route
  /// unchanged when no trails are found nearby.
  Future<RouteTrailResult> snapToTrails(
    List<LatLng> route,
    String sourceUrl,
  ) async {
    final network = await buildNetwork(route, sourceUrl);
    if (network.isEmpty) {
      return RouteTrailResult(snapped: route, network: network, changed: false);
    }
    // First pass: pull each point onto the nearest way with hysteresis.
    final snapped = snapper.snap(route, network);
    // Second pass: rebuild the stitched line as a path that follows the
    // connected trail/road graph end-to-end, so the saved route stays entirely
    // on real ways and any gap where it left the network is bridged.
    final refined = refineOntoNetwork(snapped, network);
    return RouteTrailResult(
      snapped: refined,
      network: network,
      changed: _differs(route, refined),
    );
  }

  /// Rebuilds [route] as a path that follows the connected trail/road graph in
  /// [network] end-to-end. Each point is snapped onto a way — preferring the
  /// previous point's category (trail vs road) so the path stays on one kind of
  /// way — and consecutive anchors are joined along the network, which bridges
  /// any stretch that left it by routing between the nearest on-network points.
  /// Returns [route] unchanged when the network cannot support a path.
  List<LatLng> refineOntoNetwork(List<LatLng> route, TrailNetwork network) {
    if (route.length < 2 || network.isEmpty) return route;
    final router = TrailRouter(network);
    if (router.isEmpty) return route;
    final anchors = <TrailAnchor>[];
    WayCategory? previous;
    for (final point in route) {
      final anchor = router.snap(point, preferCategory: previous);
      if (anchor == null) continue; // Off-network: bridged by the graph route.
      anchors.add(anchor);
      previous = anchor.category;
    }
    if (anchors.length < 2) return route;
    final routed = router.buildRoute(anchors);
    return routed.length < 2 ? route : routed;
  }

  bool _differs(List<LatLng> a, List<LatLng> b) {
    if (a.length != b.length) return true;
    for (var i = 0; i < a.length; i++) {
      if (distance.metersBetween(a[i], b[i]) > 1) return true;
    }
    return false;
  }
}
