import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:trail_runner/services/vector_tile_source.dart';

void main() {
  late Directory dir;
  late File mbtiles;

  setUp(() async {
    sqfliteFfiInit();
    dir = await Directory.systemTemp.createTemp('mbtiles_src');
    mbtiles = File('${dir.path}/test.mbtiles');
    final db = await databaseFactoryFfi.openDatabase(mbtiles.path);
    await db.execute('CREATE TABLE metadata (name TEXT, value TEXT)');
    await db.execute(
      'CREATE TABLE tiles (zoom_level INTEGER, tile_column INTEGER, '
      'tile_row INTEGER, tile_data BLOB)',
    );
    await db.insert('metadata', {'name': 'minzoom', 'value': '5'});
    await db.insert('metadata', {'name': 'maxzoom', 'value': '14'});
    // Store the payload gzip-compressed at z=12, x=100, XYZ y=200. MBTiles uses
    // TMS, so the stored row is (1 << 12) - 1 - 200 = 3895.
    final payload = List<int>.generate(32, (index) => index);
    await db.insert('tiles', {
      'zoom_level': 12,
      'tile_column': 100,
      'tile_row': (1 << 12) - 1 - 200,
      'tile_data': gzip.encode(payload),
    });
    await db.close();
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test('reads zoom bounds from metadata', () async {
    final source = await MbtilesVectorTileSource.openFile(
      mbtiles,
      factory: databaseFactoryFfi,
    );
    expect(source.minZoom, 5);
    expect(source.maxZoom, 14);
    await source.close();
  });

  test('reads and gunzips a tile using the TMS y flip', () async {
    final source = await MbtilesVectorTileSource.openFile(
      mbtiles,
      factory: databaseFactoryFfi,
    );
    final data = await source.readTile(12, 100, 200);
    expect(data, List<int>.generate(32, (index) => index));
    await source.close();
  });

  test('returns null for a missing tile', () async {
    final source = await MbtilesVectorTileSource.openFile(
      mbtiles,
      factory: databaseFactoryFfi,
    );
    expect(await source.readTile(12, 999, 999), isNull);
    await source.close();
  });
}
