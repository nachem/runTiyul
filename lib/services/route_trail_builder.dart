import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../core/geo/distance.dart';
import '../core/geo/geo_bounds.dart';
import '../core/geo/tile_math.dart';
import 'route_snapper.dart';
import 'trail_extractor.dart';
import 'trail_network.dart';
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
    final tiles = <TileCoordinate>[];
    for (var x = math.min(minX, maxX); x <= math.max(minX, maxX); x++) {
      for (var y = math.min(minY, maxY); y <= math.max(minY, maxY); y++) {
        tiles.add(TileCoordinate(zoom, x, y));
        if (tiles.length >= maxTiles) return tiles;
      }
    }
    return tiles;
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
    final snapped = snapper.snap(route, network);
    return RouteTrailResult(
      snapped: snapped,
      network: network,
      changed: _differs(route, snapped),
    );
  }

  bool _differs(List<LatLng> a, List<LatLng> b) {
    if (a.length != b.length) return true;
    for (var i = 0; i < a.length; i++) {
      if (distance.metersBetween(a[i], b[i]) > 1) return true;
    }
    return false;
  }
}
