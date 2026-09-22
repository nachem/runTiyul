import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trail_runner/core/geo/tile_math.dart';
import 'package:trail_runner/services/trail_network.dart';
import 'package:trail_runner/services/trail_network_cache.dart';

void main() {
  test(
    'NAV-006 caches mapped geometry and restrictions across restart',
    () async {
      final directory = await Directory.systemTemp.createTemp('routing_cache');
      addTearDown(() => directory.delete(recursive: true));
      const tile = TileCoordinate(14, 8192, 8192);
      const trails = [
        TrailPolyline(
          points: [LatLng(0, 0), LatLng(0, 0.002)],
          kind: 'path',
          structure: 'bridge',
          level: 1,
          routable: false,
        ),
      ];
      await TrailNetworkCache(
        directory: directory,
      ).write('source-a', tile, trails);
      final restored = TrailNetworkCache(directory: directory);
      final result = (await restored.read('source-a', tile))!.single;
      expect(result.points, trails.single.points);
      expect(result.routingLevel, '1/bridge');
      expect(result.routable, isFalse);
      expect(await restored.read('source-b', tile), isNull);
    },
  );

  test('cache bounds memory and disk independently', () async {
    final directory = await Directory.systemTemp.createTemp('routing_cache');
    addTearDown(() => directory.delete(recursive: true));
    final cache = TrailNetworkCache(
      directory: directory,
      maxMemoryTiles: 1,
      maxDiskBytes: 0,
    );
    const first = TileCoordinate(14, 1, 1);
    const second = TileCoordinate(14, 1, 2);
    await cache.write('source', first, const []);
    await cache.write('source', second, const []);
    expect(await cache.read('source', first), isNull);
    expect(await cache.read('source', second), isEmpty);
    expect(await directory.list().toList(), isEmpty);
  });
}
