import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Reads Mapbox Vector Tiles (MVT) by `z/x/y` from a local source. Injectable so
/// the on-device conversion workflow can be unit-tested without a real archive
/// or network access.
abstract class VectorTileSource {
  /// The minimum zoom level the source contains.
  int get minZoom;

  /// The maximum zoom level the source contains.
  int get maxZoom;

  /// Returns the decompressed MVT bytes for a tile, or `null` when the source
  /// has no tile at that coordinate (for example open sea with no features).
  Future<List<int>?> readTile(int z, int x, int y);

  Future<void> close();
}

/// A [VectorTileSource] backed by a local MBTiles (SQLite) archive.
///
/// MBTiles stores tiles in the TMS scheme (the y axis is flipped relative to
/// the XYZ scheme used elsewhere in the app) and usually gzip-compresses the
/// vector payload. Both are handled here so callers always receive raw MVT
/// bytes addressed by XYZ coordinates.
class MbtilesVectorTileSource implements VectorTileSource {
  MbtilesVectorTileSource._(this._db, this.minZoom, this.maxZoom);

  final Database _db;

  @override
  final int minZoom;

  @override
  final int maxZoom;

  /// Opens the MBTiles archive at [file] read-only. [factory] defaults to the
  /// ambient sqflite [databaseFactory] so tests can inject an FFI factory.
  static Future<MbtilesVectorTileSource> openFile(
    File file, {
    DatabaseFactory? factory,
  }) async {
    if (!await file.exists()) {
      throw StateError('MBTiles file not found: ${file.path}');
    }
    final resolved = factory ?? databaseFactory;
    final db = await resolved.openDatabase(
      file.path,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    final bounds = await _readZoomBounds(db);
    return MbtilesVectorTileSource._(db, bounds.$1, bounds.$2);
  }

  static Future<(int, int)> _readZoomBounds(Database db) async {
    int? minZoom;
    int? maxZoom;
    try {
      final rows = await db.query(
        'metadata',
        columns: ['name', 'value'],
        where: 'name IN (?, ?)',
        whereArgs: ['minzoom', 'maxzoom'],
      );
      for (final row in rows) {
        final value = int.tryParse('${row['value']}');
        if (row['name'] == 'minzoom') minZoom = value;
        if (row['name'] == 'maxzoom') maxZoom = value;
      }
    } on Object {
      // The metadata table may be absent; fall back to the tiles table.
    }
    if (minZoom == null || maxZoom == null) {
      final aggregate = await db.rawQuery(
        'SELECT MIN(zoom_level) AS min_z, MAX(zoom_level) AS max_z FROM tiles',
      );
      if (aggregate.isNotEmpty) {
        minZoom ??= (aggregate.first['min_z'] as num?)?.toInt();
        maxZoom ??= (aggregate.first['max_z'] as num?)?.toInt();
      }
    }
    return (minZoom ?? 0, maxZoom ?? 22);
  }

  @override
  Future<List<int>?> readTile(int z, int x, int y) async {
    final flippedY = ((1 << z) - 1) - y;
    final rows = await _db.query(
      'tiles',
      columns: ['tile_data'],
      where: 'zoom_level = ? AND tile_column = ? AND tile_row = ?',
      whereArgs: [z, x, flippedY],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final data = rows.first['tile_data'];
    if (data is! List<int> || data.isEmpty) return null;
    return _decompress(data);
  }

  List<int> _decompress(List<int> data) {
    if (data.length >= 2 && data[0] == 0x1f && data[1] == 0x8b) {
      return gzip.decode(data);
    }
    return data;
  }

  @override
  Future<void> close() => _db.close();
}

/// Ensures the vector MBTiles referenced by a configured source exists on the
/// device. When the source is an `http(s)` URL the archive is downloaded once
/// into application support storage; a local path is returned as-is. This keeps
/// the whole pipeline — download, convert, render — on the device.
class VectorSourceStore {
  const VectorSourceStore._();

  static Future<File> ensureLocal(String source, {http.Client? client}) async {
    final uri = Uri.tryParse(source);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return File(source);
    }
    final support = await getApplicationSupportDirectory();
    final directory = Directory(p.join(support.path, 'vector_sources'));
    await directory.create(recursive: true);
    final file = File(p.join(directory.path, _fileName(uri)));
    if (await file.exists() && await file.length() > 0) {
      return file;
    }
    final httpClient = client ?? http.Client();
    try {
      final response = await httpClient.send(http.Request('GET', uri));
      if (response.statusCode != 200) {
        throw StateError(
          'Vector source download failed (HTTP ${response.statusCode}).',
        );
      }
      final temporary = File('${file.path}.part');
      final sink = temporary.openWrite();
      try {
        await response.stream.pipe(sink);
      } finally {
        await sink.close();
      }
      await temporary.rename(file.path);
      return file;
    } finally {
      if (client == null) httpClient.close();
    }
  }

  static String _fileName(Uri uri) {
    final last = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : 'source';
    final safe = last.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
    return safe.endsWith('.mbtiles') ? safe : '$safe.mbtiles';
  }
}

/// A [VectorTileSource] that fetches MVT tiles per `z/x/y` from an HTTP vector
/// tile endpoint such as OpenFreeMap. The endpoint may be a direct
/// `{z}/{x}/{y}` template or a TileJSON URL that is resolved to one, so exactly
/// the tiles for the selected area are downloaded and converted on the device.
class HttpVectorTileSource implements VectorTileSource {
  HttpVectorTileSource._(
    this._client,
    this._ownsClient,
    this._template,
    this.minZoom,
    this.maxZoom,
  );

  final http.Client _client;
  final bool _ownsClient;
  final String _template;

  @override
  final int minZoom;

  @override
  final int maxZoom;

  /// True when [source] should be treated as a live vector tile endpoint (a
  /// `{z}/{x}/{y}` template or an http(s) URL that is not an `.mbtiles` file).
  static bool looksLikeTileUrl(String source) {
    final lower = source.toLowerCase();
    if (source.contains('{z}')) return true;
    final isRemote =
        lower.startsWith('http://') || lower.startsWith('https://');
    return isRemote && !lower.endsWith('.mbtiles');
  }

  /// Opens [source] as a vector tile endpoint. A direct template is used as-is;
  /// otherwise [source] is fetched as TileJSON and its tile template and zoom
  /// range are read from it.
  static Future<HttpVectorTileSource> open(
    String source, {
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();
    final ownsClient = client == null;
    try {
      if (source.contains('{z}')) {
        return HttpVectorTileSource._(httpClient, ownsClient, source, 0, 14);
      }
      final response = await httpClient.get(Uri.parse(source));
      if (response.statusCode != 200) {
        throw StateError(
          'Vector TileJSON request failed (HTTP ${response.statusCode}).',
        );
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final tiles =
          (json['tiles'] as List?)?.cast<String>() ?? const <String>[];
      if (tiles.isEmpty) {
        throw StateError('Vector TileJSON has no tile template.');
      }
      final minZoom = (json['minzoom'] as num?)?.toInt() ?? 0;
      final maxZoom = (json['maxzoom'] as num?)?.toInt() ?? 14;
      return HttpVectorTileSource._(
        httpClient,
        ownsClient,
        tiles.first,
        minZoom,
        maxZoom,
      );
    } on Object {
      if (ownsClient) httpClient.close();
      rethrow;
    }
  }

  @override
  Future<List<int>?> readTile(int z, int x, int y) async {
    if (z < minZoom || z > maxZoom) return null;
    final url = _template
        .replaceAll('{z}', '$z')
        .replaceAll('{x}', '$x')
        .replaceAll('{y}', '$y');
    final response = await _client.get(Uri.parse(url));
    if (response.statusCode != 200) return null;
    final bytes = response.bodyBytes;
    if (bytes.isEmpty) return null;
    if (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
      return gzip.decode(bytes);
    }
    return bytes;
  }

  @override
  Future<void> close() async {
    if (_ownsClient) _client.close();
  }
}
