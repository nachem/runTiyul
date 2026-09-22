import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trail_runner/core/geo/geo_bounds.dart';
import 'package:trail_runner/core/geo/tile_math.dart';
import 'package:trail_runner/services/route_trail_builder.dart';
import 'package:trail_runner/services/trail_network.dart';
import 'package:trail_runner/services/vector_tile_source.dart';

class _EmptySource implements VectorTileSource {
  @override
  int get minZoom => 0;
  @override
  int get maxZoom => 14;
  int reads = 0;
  bool closed = false;

  @override
  Future<List<int>?> readTile(int z, int x, int y) async {
    reads++;
    return null;
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

void main() {
  const route = [LatLng(0, 0), LatLng(0, 0.02)];

  test('tilesForRoute covers the route endpoints at z14', () {
    final tiles = RouteTrailBuilder().tilesForRoute(route, buffer: 0);
    expect(tiles, contains(const TileCoordinate(14, 8192, 8192)));
  });

  test('buildNetwork returns empty when the source has no tiles', () async {
    final source = _EmptySource();
    final builder = RouteTrailBuilder(openSource: (_) async => source);

    final network = await builder.buildNetwork(route, 'https://example/planet');

    expect(network.isEmpty, isTrue);
    expect(source.reads, greaterThan(0));
    expect(source.closed, isTrue);
  });

  test(
    'snapToTrails returns the original route when no trails are found',
    () async {
      final builder = RouteTrailBuilder(
        openSource: (_) async => _EmptySource(),
      );

      final result = await builder.snapToTrails(
        route,
        'https://example/planet',
      );

      expect(result.changed, isFalse);
      expect(result.snapped, same(route));
    },
  );

  test('tilesForBounds covers a small viewport at z14', () {
    final tiles = RouteTrailBuilder().tilesForBounds(
      const GeoBounds(north: 0.01, south: 0, east: 0.01, west: 0),
    );
    expect(tiles, contains(const TileCoordinate(14, 8192, 8192)));
    expect(tiles.every((tile) => tile.z == 14), isTrue);
  });

  test('tilesForBounds caps a zoomed-out viewport around its center', () {
    final tiles = RouteTrailBuilder().tilesForBounds(
      const GeoBounds(north: 10, south: -10, east: 10, west: -10),
    );

    expect(tiles, hasLength(24));
    expect(tiles, contains(const TileCoordinate(14, 8192, 8192)));
    expect(tiles.every((tile) => (tile.x - 8192).abs() <= 3), isTrue);
    expect(tiles.every((tile) => (tile.y - 8192).abs() <= 3), isTrue);
  });

  test('tilesNearPoint stays local when the viewport is zoomed out', () {
    final builder = RouteTrailBuilder();
    final tiles = builder.tilesNearPoint(const LatLng(0, 0));

    expect(tiles, hasLength(9));
    expect(tiles, contains(const TileCoordinate(14, 8192, 8192)));
    expect(tiles.every((tile) => (tile.x - 8192).abs() <= 1), isTrue);
    expect(tiles.every((tile) => (tile.y - 8192).abs() <= 1), isTrue);
  });

  test('interactive leg loading rejects non-overlapping far neighborhoods', () {
    final builder = RouteTrailBuilder();

    expect(
      builder.canLoadInteractiveLeg(const LatLng(0, 0), const LatLng(0, 0.01)),
      isTrue,
    );
    expect(
      builder.canLoadInteractiveLeg(const LatLng(0, 0), const LatLng(10, 10)),
      isFalse,
    );
  });

  test('networkForBounds reads covering tiles and closes the source', () async {
    final source = _EmptySource();
    final builder = RouteTrailBuilder(openSource: (_) async => source);

    final network = await builder.networkForBounds(
      const GeoBounds(north: 0.01, south: 0, east: 0.01, west: 0),
      'https://example/planet',
    );

    expect(network.isEmpty, isTrue);
    expect(source.reads, greaterThan(0));
    expect(source.closed, isTrue);
  });

  test('networkNearPoint reads only a bounded local neighborhood', () async {
    final source = _EmptySource();
    final builder = RouteTrailBuilder(openSource: (_) async => source);

    final network = await builder.networkNearPoint(
      const LatLng(0, 0),
      'https://example/planet',
    );

    expect(network.isEmpty, isTrue);
    expect(source.reads, 9);
    expect(source.closed, isTrue);
  });

  test('MAP-013 Offline mode never opens a remote vector source', () async {
    var opens = 0;
    final builder = RouteTrailBuilder(
      openSource: (_) async {
        opens++;
        return _EmptySource();
      },
    );
    final result = await builder.networkNearPoint(
      const LatLng(0, 0),
      'https://example/planet',
      allowNetwork: false,
    );
    expect(result.isEmpty, isTrue);
    expect(opens, 0);
    await builder.networkNearPoint(
      const LatLng(0, 0),
      'https://example/planet',
    );
    await builder.networkNearPoint(
      const LatLng(0, 0),
      'https://example/planet',
      allowNetwork: false,
    );
    expect(opens, 1);
  });

  test('RTE-011 does not drop an unmatchable point from the input', () {
    // Two collinear trails that meet at a shared junction at lon 0.002.
    final network = TrailNetwork(const [
      TrailPolyline(points: [LatLng(0, 0), LatLng(0, 0.002)], kind: 'path'),
      TrailPolyline(points: [LatLng(0, 0.002), LatLng(0, 0.004)], kind: 'path'),
    ]);
    final builder = RouteTrailBuilder();

    // The middle point is ~55 m north of the line (off any way); the ends are
    // on it. The refined route should bridge across, staying on the network.
    const original = [LatLng(0, 0), LatLng(0.0005, 0.002), LatLng(0, 0.004)];
    expect(builder.matchOnNetwork(original, network), isNull);
    expect(builder.refineOntoNetwork(original, network), same(original));
  });

  test(
    'matching chooses a connected nearby way over a disconnected nearest fragment',
    () {
      const network = TrailNetwork([
        TrailPolyline(points: [LatLng(0, 0), LatLng(0, 0.001)], kind: 'path'),
        TrailPolyline(
          points: [LatLng(0.0001, 0), LatLng(0.0001, 0.003)],
          kind: 'minor',
        ),
      ]);
      final result = RouteTrailBuilder().matchOnNetwork(const [
        LatLng(0, 0),
        LatLng(0, 0.001),
        LatLng(0.0001, 0.002),
        LatLng(0.0001, 0.003),
      ], network);
      expect(result, isNotNull);
      expect(
        result!.every((point) => (point.latitude - 0.0001).abs() < 1e-8),
        isTrue,
      );
    },
  );

  test('matching cannot silently trim an off-network route endpoint', () {
    const network = TrailNetwork([
      TrailPolyline(points: [LatLng(0, 0), LatLng(0, 0.003)], kind: 'path'),
    ]);
    expect(
      RouteTrailBuilder().matchOnNetwork(const [
        LatLng(0, 0),
        LatLng(0, 0.002),
        LatLng(0.002, 0.003),
      ], network),
      isNull,
    );
  });

  test('matching rejects a distant detour even when it is connected', () {
    const network = TrailNetwork([
      TrailPolyline(
        points: [
          LatLng(0, 0),
          LatLng(0.005, 0),
          LatLng(0.005, 0.002),
          LatLng(0, 0.002),
        ],
        kind: 'path',
      ),
    ]);
    expect(
      RouteTrailBuilder().matchOnNetwork(const [
        LatLng(0, 0),
        LatLng(0, 0.002),
      ], network),
      isNull,
    );
  });

  test('refineOntoNetwork never bridges disconnected ways off trail', () {
    final network = TrailNetwork(const [
      TrailPolyline(points: [LatLng(0, 0), LatLng(0, 0.002)], kind: 'path'),
      TrailPolyline(
        points: [LatLng(0.002, 0.003), LatLng(0.002, 0.005)],
        kind: 'path',
      ),
    ]);
    const original = [LatLng(0, 0.001), LatLng(0.002, 0.004)];

    expect(RouteTrailBuilder().refineOntoNetwork(original, network), original);
  });
}
