import 'dart:convert';
import 'dart:io';

import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../core/geo/tile_math.dart';
import 'trail_network.dart';

class TrailNetworkCache {
  TrailNetworkCache({
    this.directory,
    this.maxMemoryTiles = 48,
    this.maxDiskBytes = 64 * 1024 * 1024,
  });

  final Directory? directory;
  final int maxMemoryTiles;
  final int maxDiskBytes;
  final Map<String, List<TrailPolyline>> _memory = {};

  String _key(String source, TileCoordinate tile) =>
      '${const Uuid().v5(Namespace.url.value, source)}-${tile.z}-${tile.x}-${tile.y}';

  void _remember(String key, List<TrailPolyline> trails) {
    _memory.remove(key);
    _memory[key] = trails;
    while (_memory.length > maxMemoryTiles) {
      _memory.remove(_memory.keys.first);
    }
  }

  Future<List<TrailPolyline>?> read(String source, TileCoordinate tile) async {
    final key = _key(source, tile);
    final cached = _memory[key];
    if (cached != null) {
      _remember(key, cached);
      return cached;
    }
    final root = directory;
    if (root == null) return null;
    try {
      final file = File(p.join(root.path, '$key.json.gz'));
      if (!await file.exists()) return null;
      final rows =
          jsonDecode(utf8.decode(gzip.decode(await file.readAsBytes())))
              as List;
      final trails = [
        for (final raw in rows) _decode(raw as Map<String, dynamic>),
      ];
      _remember(key, trails);
      return trails;
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  TrailPolyline _decode(Map<String, dynamic> row) => TrailPolyline(
    points: [
      for (final point in row['points'] as List)
        LatLng((point[0] as num).toDouble(), (point[1] as num).toDouble()),
    ],
    kind: row['kind'] as String,
    name: row['name'] as String?,
    level: row['level'] as int,
    structure: row['structure'] as String,
    routable: row['routable'] as bool,
  );

  Future<void> write(
    String source,
    TileCoordinate tile,
    List<TrailPolyline> trails,
  ) async {
    final key = _key(source, tile);
    _remember(key, trails);
    final root = directory;
    if (root == null) return;
    try {
      await root.create(recursive: true);
      final file = File(p.join(root.path, '$key.json.gz'));
      final temporary = File('${file.path}.${const Uuid().v4()}.part');
      final rows = [
        for (final trail in trails)
          {
            'points': [
              for (final point in trail.points)
                [point.latitude, point.longitude],
            ],
            'kind': trail.kind,
            'name': trail.name,
            'level': trail.level,
            'structure': trail.structure,
            'routable': trail.routable,
          },
      ];
      try {
        await temporary.writeAsBytes(
          gzip.encode(utf8.encode(jsonEncode(rows))),
          flush: true,
        );
        await temporary.rename(file.path);
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
      final files = <(File, FileStat)>[];
      var total = 0;
      await for (final entry in root.list()) {
        if (entry is! File || !entry.path.endsWith('.json.gz')) continue;
        final stat = await entry.stat();
        files.add((entry, stat));
        total += stat.size;
      }
      files.sort(
        (left, right) => left.$2.modified.compareTo(right.$2.modified),
      );
      for (
        var index = 0;
        index < files.length &&
            (total > maxDiskBytes || files.length - index > 256);
        index++
      ) {
        await files[index].$1.delete();
        total -= files[index].$2.size;
      }
    } on FileSystemException {
      return;
    }
  }
}
