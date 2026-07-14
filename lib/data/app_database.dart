import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase({DatabaseFactory? factory, String? databasePath})
    : _factory = factory ?? databaseFactory,
      _path = databasePath;

  final DatabaseFactory _factory;
  final String? _path;
  Database? _database;

  Future<Database> get database async {
    final current = _database;
    if (current != null) return current;
    final path = _path ?? p.join(await getDatabasesPath(), 'trail_runner.db');
    final opened = await _factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: _createSchema,
      ),
    );
    _database = opened;
    return opened;
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  static Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE routes (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        source TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        distance_m REAL NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE route_points (
        route_id TEXT NOT NULL REFERENCES routes(id) ON DELETE CASCADE,
        sequence INTEGER NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        elevation REAL,
        recorded_at TEXT,
        PRIMARY KEY(route_id, sequence)
      )
    ''');
    await db.execute('''
      CREATE TABLE activities (
        id TEXT PRIMARY KEY,
        route_id TEXT REFERENCES routes(id) ON DELETE SET NULL,
        status TEXT NOT NULL,
        started_at TEXT NOT NULL,
        ended_at TEXT,
        elapsed_ms INTEGER NOT NULL,
        distance_m REAL NOT NULL,
        elevation_gain_m REAL NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE activity_samples (
        activity_id TEXT NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
        sequence INTEGER NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        recorded_at TEXT NOT NULL,
        accuracy REAL NOT NULL,
        altitude REAL,
        speed REAL,
        heading REAL,
        PRIMARY KEY(activity_id, sequence)
      )
    ''');
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
    await db.execute('''
      CREATE TABLE tiles (
        tile_key TEXT PRIMARY KEY,
        provider_id TEXT NOT NULL,
        zoom INTEGER NOT NULL,
        x INTEGER NOT NULL,
        y INTEGER NOT NULL,
        relative_path TEXT NOT NULL,
        byte_count INTEGER NOT NULL,
        downloaded_at TEXT NOT NULL,
        UNIQUE(provider_id, zoom, x, y)
      )
    ''');
    await db.execute('''
      CREATE TABLE offline_area_tiles (
        area_id TEXT NOT NULL REFERENCES offline_areas(id) ON DELETE CASCADE,
        tile_key TEXT NOT NULL REFERENCES tiles(tile_key) ON DELETE CASCADE,
        PRIMARY KEY(area_id, tile_key)
      )
    ''');
    await db.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }
}
