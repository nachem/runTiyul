import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:trail_runner/data/app_database.dart';
import 'package:trail_runner/data/app_repository.dart';
import 'package:trail_runner/models/offline_area.dart';

void main() {
  test(
    'migrates a v1 offline_areas table and defaults source_format',
    () async {
      sqfliteFfiInit();
      final dir = await Directory.systemTemp.createTemp('trail_migrate');
      final path = p.join(dir.path, 'trail_runner.db');

      // Create a version-1 database with the pre-source_format offline_areas
      // schema and a legacy row.
      final v1 = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute('''
            CREATE TABLE offline_areas (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              north REAL NOT NULL,
              south REAL NOT NULL,
              east REAL NOT NULL,
              west REAL NOT NULL,
              min_zoom INTEGER NOT NULL,
              max_zoom INTEGER NOT NULL,
              provider_id TEXT NOT NULL,
              status TEXT NOT NULL,
              total_tiles INTEGER NOT NULL,
              completed_tiles INTEGER NOT NULL,
              actual_bytes INTEGER NOT NULL,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              last_error TEXT
            )
          ''');
          },
        ),
      );
      await v1.insert('offline_areas', {
        'id': 'legacy-area',
        'name': 'Legacy',
        'north': 31.8,
        'south': 31.7,
        'east': 35.3,
        'west': 35.2,
        'min_zoom': 12,
        'max_zoom': 13,
        'provider_id': 'openstreetmap-standard',
        'status': 'complete',
        'total_tiles': 4,
        'completed_tiles': 4,
        'actual_bytes': 2048,
        'created_at': DateTime.utc(2026, 7, 14).toIso8601String(),
        'updated_at': DateTime.utc(2026, 7, 14).toIso8601String(),
        'last_error': null,
      });
      await v1.close();

      // Reopen through AppDatabase (version 2) to trigger the migration.
      final database = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: path,
      );
      final repository = AppRepository(database);
      addTearDown(() async {
        await database.close();
        await dir.delete(recursive: true);
      });

      final areas = await repository.loadOfflineAreas();
      expect(areas, hasLength(1));
      expect(areas.single.id, 'legacy-area');
      expect(areas.single.sourceFormat, OfflineSourceFormat.rasterTiles);

      // A rewrite persists the format column going forward.
      await repository.saveOfflineArea(areas.single);
      final reloaded = await repository.loadOfflineAreas();
      expect(reloaded.single.sourceFormat, OfflineSourceFormat.rasterTiles);
    },
  );
}
