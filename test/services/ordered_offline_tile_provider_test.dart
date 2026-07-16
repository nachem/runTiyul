import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trail_runner/core/geo/geo_bounds.dart';
import 'package:trail_runner/core/geo/tile_math.dart';
import 'package:trail_runner/models/offline_area.dart';
import 'package:trail_runner/services/tile_store.dart';

const _bounds = GeoBounds(north: 0.06, south: 0.05, east: 0.06, west: 0.05);

OfflineArea _area({
  required String id,
  required OfflineSourceFormat format,
  GeoBounds bounds = _bounds,
  int minZoom = 12,
  int maxZoom = 12,
}) => OfflineArea(
  id: id,
  name: id,
  bounds: bounds,
  minZoom: minZoom,
  maxZoom: maxZoom,
  providerId: 'p',
  status: OfflineAreaStatus.complete,
  totalTiles: 1,
  completedTiles: 1,
  actualBytes: 1,
  createdAt: DateTime.utc(2026, 7, 16),
  updatedAt: DateTime.utc(2026, 7, 16),
  sourceFormat: format,
);

Future<void> _write(File file, List<int> bytes) async {
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('offlineTileNamespace separates formats but keeps the provider', () {
    final vec = offlineTileNamespace('p', OfflineSourceFormat.convertedVector);
    final ras = offlineTileNamespace('p', OfflineSourceFormat.rasterTiles);
    expect(vec, isNot(ras));
    expect(vec, startsWith('p'));
    expect(ras, startsWith('p'));
  });

  test('tileIntersectsBounds matches only overlapping tiles', () {
    final plan = const TilePlanner().plan(_bounds, 12, 12);
    final inside = plan.coordinates.first;
    expect(
      tileIntersectsBounds(_bounds, inside.z, inside.x, inside.y),
      isTrue,
    );
    // A far-away tile does not intersect the small area.
    expect(tileIntersectsBounds(_bounds, 12, inside.x + 100, inside.y), isFalse);
  });

  group('OrderedOfflineTileProvider', () {
    late Directory dir;
    late TileStore store;
    late TileCoordinate coord;
    late String vecNs;
    late String rasNs;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('ordered_tiles');
      store = await TileStore.at(dir);
      coord = const TilePlanner().plan(_bounds, 12, 12).coordinates.first;
      vecNs = offlineTileNamespace('p', OfflineSourceFormat.convertedVector);
      rasNs = offlineTileNamespace('p', OfflineSourceFormat.rasterTiles);
      await _write(store.fileFor(vecNs, coord.z, coord.x, coord.y), [1]);
      await _write(store.fileFor(rasNs, coord.z, coord.x, coord.y), [2]);
    });

    tearDown(() async => dir.delete(recursive: true));

    ImageProvider imageFor(List<OfflineArea> areas) {
      final provider = OrderedOfflineTileProvider(store: store, areas: areas);
      return provider.getImage(
        TileCoordinates(coord.x, coord.y, coord.z),
        TileLayer(urlTemplate: 'https://example/{z}/{x}/{y}.png'),
      );
    }

    test('returns the top area tile where areas overlap', () {
      final vector = _area(id: 'v', format: OfflineSourceFormat.convertedVector);
      final raster = _area(id: 'r', format: OfflineSourceFormat.rasterTiles);

      final topVector = imageFor([vector, raster]);
      expect(topVector, isA<FileImage>());
      expect((topVector as FileImage).file.path, contains(vecNs));

      // Reordering so the raster area is on top flips which tile is drawn.
      final topRaster = imageFor([raster, vector]);
      expect((topRaster as FileImage).file.path, contains(rasNs));
    });

    test('skips a top area that does not cover the tile', () {
      // The vector area is on top but far away; the raster area covers here.
      final farVector = _area(
        id: 'v',
        format: OfflineSourceFormat.convertedVector,
        bounds: const GeoBounds(north: 10.0, south: 9.9, east: 10.0, west: 9.9),
      );
      final raster = _area(id: 'r', format: OfflineSourceFormat.rasterTiles);
      final image = imageFor([farVector, raster]);
      expect((image as FileImage).file.path, contains(rasNs));
    });

    test('returns a transparent tile when no area covers it', () {
      final vector = _area(id: 'v', format: OfflineSourceFormat.convertedVector);
      final provider = OrderedOfflineTileProvider(
        store: store,
        areas: [vector],
      );
      final image = provider.getImage(
        TileCoordinates(coord.x + 500, coord.y + 500, coord.z),
        TileLayer(urlTemplate: 'https://example/{z}/{x}/{y}.png'),
      );
      expect(image, isA<MemoryImage>());
    });
  });
}
