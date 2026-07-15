import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trail_runner/services/vector_tile_source.dart';

void main() {
  test('resolves a TileJSON endpoint and fetches tiles', () async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/planet')) {
        return http.Response(
          jsonEncode({
            'tiles': ['https://tiles.example/pt/{z}/{x}/{y}.pbf'],
            'minzoom': 0,
            'maxzoom': 14,
          }),
          200,
        );
      }
      if (request.url.path == '/pt/14/8186/5448.pbf') {
        return http.Response.bytes([1, 2, 3, 4], 200);
      }
      return http.Response('not found', 404);
    });

    final source = await HttpVectorTileSource.open(
      'https://tiles.example/planet',
      client: client,
    );
    expect(source.minZoom, 0);
    expect(source.maxZoom, 14);

    expect(await source.readTile(14, 8186, 5448), [1, 2, 3, 4]);
    // Beyond the source max zoom: no request is made, returns null.
    expect(await source.readTile(15, 0, 0), isNull);
    // A missing tile is null, not an error.
    expect(await source.readTile(14, 0, 0), isNull);

    await source.close();
  });

  test('accepts a direct z/x/y template', () async {
    final client = MockClient((request) async {
      if (request.url.path == '/pt/10/1/2.pbf') {
        return http.Response.bytes([9, 9], 200);
      }
      return http.Response('nope', 404);
    });

    final source = await HttpVectorTileSource.open(
      'https://tiles.example/pt/{z}/{x}/{y}.pbf',
      client: client,
    );
    expect(source.maxZoom, 14);
    expect(await source.readTile(10, 1, 2), [9, 9]);
    await source.close();
  });

  test('looksLikeTileUrl distinguishes tile endpoints from mbtiles', () {
    expect(HttpVectorTileSource.looksLikeTileUrl('https://x/planet'), isTrue);
    expect(
      HttpVectorTileSource.looksLikeTileUrl('https://x/{z}/{x}/{y}.pbf'),
      isTrue,
    );
    expect(
      HttpVectorTileSource.looksLikeTileUrl('https://x/region.mbtiles'),
      isFalse,
    );
    expect(HttpVectorTileSource.looksLikeTileUrl('/local/x.mbtiles'), isFalse);
  });
}
