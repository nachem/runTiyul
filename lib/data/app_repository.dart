import 'package:sqflite/sqflite.dart';

import '../core/geo/geo_bounds.dart';
import '../models/offline_area.dart';
import '../models/run_activity.dart';
import '../models/trail_route.dart';
import 'app_database.dart';

class AppRepository {
  const AppRepository(this._appDatabase);

  final AppDatabase _appDatabase;

  Future<List<TrailRoute>> loadRoutes() async {
    final db = await _appDatabase.database;
    final rows = await db.query('routes', orderBy: 'updated_at DESC');
    final result = <TrailRoute>[];
    for (final row in rows) {
      final points = await db.query(
        'route_points',
        where: 'route_id = ?',
        whereArgs: [row['id']],
        orderBy: 'sequence',
      );
      result.add(_routeFromRows(row, points));
    }
    return result;
  }

  Future<void> saveRoute(TrailRoute route) async {
    final db = await _appDatabase.database;
    await db.transaction((txn) async {
      await txn.insert(
        'routes',
        _routeMap(route),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.delete(
        'route_points',
        where: 'route_id = ?',
        whereArgs: [route.id],
      );
      for (var i = 0; i < route.points.length; i++) {
        final point = route.points[i];
        await txn.insert('route_points', {
          'route_id': route.id,
          'sequence': i,
          'latitude': point.latitude,
          'longitude': point.longitude,
          'elevation': point.elevation,
          'recorded_at': point.recordedAt?.toUtc().toIso8601String(),
        });
      }
    });
  }

  Future<void> deleteRoute(String id) async {
    final db = await _appDatabase.database;
    await db.delete('routes', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<RunActivity>> loadActivities() async {
    final db = await _appDatabase.database;
    final rows = await db.query('activities', orderBy: 'started_at DESC');
    final result = <RunActivity>[];
    for (final row in rows) {
      final samples = await db.query(
        'activity_samples',
        where: 'activity_id = ?',
        whereArgs: [row['id']],
        orderBy: 'sequence',
      );
      result.add(_activityFromRows(row, samples));
    }
    return result;
  }

  Future<void> createActivity(RunActivity activity) async {
    final db = await _appDatabase.database;
    await db.insert('activities', _activityMap(activity));
  }

  Future<void> appendActivitySample(
    RunActivity activity,
    ActivitySample sample,
  ) async {
    final db = await _appDatabase.database;
    await db.transaction((txn) async {
      await txn.insert('activity_samples', {
        'activity_id': activity.id,
        'sequence': activity.samples.length - 1,
        'latitude': sample.latitude,
        'longitude': sample.longitude,
        'recorded_at': sample.recordedAt.toUtc().toIso8601String(),
        'accuracy': sample.accuracy,
        'altitude': sample.altitude,
        'speed': sample.speed,
        'heading': sample.heading,
      });
      await txn.update(
        'activities',
        _activityMap(activity),
        where: 'id = ?',
        whereArgs: [activity.id],
      );
    });
  }

  Future<void> updateActivity(RunActivity activity) async {
    final db = await _appDatabase.database;
    await db.update(
      'activities',
      _activityMap(activity),
      where: 'id = ?',
      whereArgs: [activity.id],
    );
  }

  Future<void> deleteActivity(String id) async {
    final db = await _appDatabase.database;
    await db.delete('activities', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<OfflineArea>> loadOfflineAreas() async {
    final db = await _appDatabase.database;
    final rows = await db.query('offline_areas', orderBy: 'updated_at DESC');
    return rows.map(_areaFromRow).toList();
  }

  Future<void> saveOfflineArea(OfflineArea area) async {
    final db = await _appDatabase.database;
    await db.transaction((txn) => _upsertOfflineArea(txn, area));
  }

  Future<List<String>> replaceOfflineAreaPlan(
    OfflineArea area,
    Set<String> retainedTileKeys,
  ) async {
    final db = await _appDatabase.database;
    return db.transaction((txn) async {
      final references = await txn.rawQuery(
        '''
        SELECT tiles.tile_key, tiles.relative_path
        FROM tiles
        JOIN offline_area_tiles refs ON refs.tile_key = tiles.tile_key
        WHERE refs.area_id = ?
        ''',
        [area.id],
      );
      final orphanPaths = <String>[];
      for (final reference in references) {
        final tileKey = reference['tile_key']! as String;
        if (retainedTileKeys.contains(tileKey)) continue;

        final countRows = await txn.rawQuery(
          'SELECT COUNT(*) AS count FROM offline_area_tiles WHERE tile_key = ?',
          [tileKey],
        );
        final referenceCount = countRows.single['count']! as int;
        await txn.delete(
          'offline_area_tiles',
          where: 'area_id = ? AND tile_key = ?',
          whereArgs: [area.id, tileKey],
        );
        if (referenceCount == 1) {
          orphanPaths.add(reference['relative_path']! as String);
          await txn.delete(
            'tiles',
            where: 'tile_key = ?',
            whereArgs: [tileKey],
          );
        }
      }
      await _upsertOfflineArea(txn, area);
      return orphanPaths;
    });
  }

  Future<void> _upsertOfflineArea(
    DatabaseExecutor executor,
    OfflineArea area,
  ) async {
    final values = _areaMap(area);
    final updated = await executor.update(
      'offline_areas',
      values,
      where: 'id = ?',
      whereArgs: [area.id],
    );
    if (updated == 0) await executor.insert('offline_areas', values);
  }

  Future<void> attachTile({
    required String areaId,
    required String tileKey,
    required String providerId,
    required int zoom,
    required int x,
    required int y,
    required String relativePath,
    required int byteCount,
  }) async {
    final db = await _appDatabase.database;
    await db.transaction((txn) async {
      await txn.insert('tiles', {
        'tile_key': tileKey,
        'provider_id': providerId,
        'zoom': zoom,
        'x': x,
        'y': y,
        'relative_path': relativePath,
        'byte_count': byteCount,
        'downloaded_at': DateTime.now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await txn.insert('offline_area_tiles', {
        'area_id': areaId,
        'tile_key': tileKey,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    });
  }

  Future<List<Map<String, Object?>>> unsharedTiles(String areaId) async {
    final db = await _appDatabase.database;
    return db.rawQuery(
      '''
      SELECT tiles.* FROM tiles
      JOIN offline_area_tiles refs ON refs.tile_key = tiles.tile_key
      WHERE refs.area_id = ?
      AND (SELECT COUNT(*) FROM offline_area_tiles other
           WHERE other.tile_key = tiles.tile_key) = 1
      ''',
      [areaId],
    );
  }

  Future<void> deleteOfflineArea(String areaId) async {
    final db = await _appDatabase.database;
    await db.transaction((txn) async {
      final orphanRows = await txn.rawQuery(
        '''
        SELECT tiles.tile_key FROM tiles
        JOIN offline_area_tiles refs ON refs.tile_key = tiles.tile_key
        WHERE refs.area_id = ?
        AND (SELECT COUNT(*) FROM offline_area_tiles other
             WHERE other.tile_key = tiles.tile_key) = 1
        ''',
        [areaId],
      );
      await txn.delete(
        'offline_area_tiles',
        where: 'area_id = ?',
        whereArgs: [areaId],
      );
      for (final row in orphanRows) {
        await txn.delete(
          'tiles',
          where: 'tile_key = ?',
          whereArgs: [row['tile_key']],
        );
      }

      await txn.delete('offline_areas', where: 'id = ?', whereArgs: [areaId]);
    });
  }

  Future<String?> loadSetting(String key) async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['value']! as String;
  }

  Future<void> saveSetting(String key, String value) async {
    final db = await _appDatabase.database;
    await db.insert('app_settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Map<String, Object?> _routeMap(TrailRoute route) => {
    'id': route.id,
    'name': route.name,
    'source': route.source.name,
    'created_at': route.createdAt.toUtc().toIso8601String(),
    'updated_at': route.updatedAt.toUtc().toIso8601String(),
    'distance_m': route.distanceMeters,
  };

  TrailRoute _routeFromRows(
    Map<String, Object?> row,
    List<Map<String, Object?>> points,
  ) {
    return TrailRoute(
      id: row['id']! as String,
      name: row['name']! as String,
      source: RouteSource.values.byName(row['source']! as String),
      createdAt: DateTime.parse(row['created_at']! as String),
      updatedAt: DateTime.parse(row['updated_at']! as String),
      distanceMeters: (row['distance_m']! as num).toDouble(),
      points: points
          .map(
            (point) => RoutePoint(
              latitude: (point['latitude']! as num).toDouble(),
              longitude: (point['longitude']! as num).toDouble(),
              elevation: (point['elevation'] as num?)?.toDouble(),
              recordedAt: point['recorded_at'] == null
                  ? null
                  : DateTime.parse(point['recorded_at']! as String),
            ),
          )
          .toList(),
    );
  }

  Map<String, Object?> _activityMap(RunActivity activity) => {
    'id': activity.id,
    'route_id': activity.routeId,
    'status': activity.status.name,
    'started_at': activity.startedAt.toUtc().toIso8601String(),
    'ended_at': activity.endedAt?.toUtc().toIso8601String(),
    'elapsed_ms': activity.elapsed.inMilliseconds,
    'distance_m': activity.distanceMeters,
    'elevation_gain_m': activity.elevationGainMeters,
  };

  RunActivity _activityFromRows(
    Map<String, Object?> row,
    List<Map<String, Object?>> samples,
  ) {
    return RunActivity(
      id: row['id']! as String,
      routeId: row['route_id'] as String?,
      status: ActivityStatus.values.byName(row['status']! as String),
      startedAt: DateTime.parse(row['started_at']! as String),
      endedAt: row['ended_at'] == null
          ? null
          : DateTime.parse(row['ended_at']! as String),
      elapsed: Duration(milliseconds: row['elapsed_ms']! as int),
      distanceMeters: (row['distance_m']! as num).toDouble(),
      elevationGainMeters: (row['elevation_gain_m']! as num).toDouble(),
      samples: samples
          .map(
            (sample) => ActivitySample(
              latitude: (sample['latitude']! as num).toDouble(),
              longitude: (sample['longitude']! as num).toDouble(),
              recordedAt: DateTime.parse(sample['recorded_at']! as String),
              accuracy: (sample['accuracy']! as num).toDouble(),
              altitude: (sample['altitude'] as num?)?.toDouble(),
              speed: (sample['speed'] as num?)?.toDouble(),
              heading: (sample['heading'] as num?)?.toDouble(),
            ),
          )
          .toList(),
    );
  }

  Map<String, Object?> _areaMap(OfflineArea area) => {
    'id': area.id,
    'name': area.name,
    'north': area.bounds.north,
    'south': area.bounds.south,
    'east': area.bounds.east,
    'west': area.bounds.west,
    'min_zoom': area.minZoom,
    'max_zoom': area.maxZoom,
    'provider_id': area.providerId,
    'status': area.status.name,
    'total_tiles': area.totalTiles,
    'completed_tiles': area.completedTiles,
    'actual_bytes': area.actualBytes,
    'created_at': area.createdAt.toUtc().toIso8601String(),
    'updated_at': area.updatedAt.toUtc().toIso8601String(),
    'last_error': area.lastError,
    'source_format': area.sourceFormat.name,
  };

  OfflineArea _areaFromRow(Map<String, Object?> row) {
    return OfflineArea(
      id: row['id']! as String,
      name: row['name']! as String,
      bounds: GeoBounds(
        north: (row['north']! as num).toDouble(),
        south: (row['south']! as num).toDouble(),
        east: (row['east']! as num).toDouble(),
        west: (row['west']! as num).toDouble(),
      ),
      minZoom: row['min_zoom']! as int,
      maxZoom: row['max_zoom']! as int,
      providerId: row['provider_id']! as String,
      status: OfflineAreaStatus.values.byName(row['status']! as String),
      totalTiles: row['total_tiles']! as int,
      completedTiles: row['completed_tiles']! as int,
      actualBytes: row['actual_bytes']! as int,
      createdAt: DateTime.parse(row['created_at']! as String),
      updatedAt: DateTime.parse(row['updated_at']! as String),
      lastError: row['last_error'] as String?,
      sourceFormat: _sourceFormat(row['source_format'] as String?),
    );
  }

  OfflineSourceFormat _sourceFormat(String? name) {
    if (name == null) return OfflineSourceFormat.rasterTiles;
    try {
      return OfflineSourceFormat.values.byName(name);
    } on ArgumentError {
      return OfflineSourceFormat.rasterTiles;
    }
  }
}
