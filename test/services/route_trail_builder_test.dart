import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trail_runner/core/geo/geo_bounds.dart';
import 'package:trail_runner/core/geo/tile_math.dart';
import 'package:trail_runner/services/route_trail_builder.dart';
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
}
