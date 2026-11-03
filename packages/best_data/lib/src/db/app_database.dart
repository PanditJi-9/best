import 'package:sqflite_common/sqlite_api.dart';

/// Owns the schema and nothing else.
///
/// The factory is injected so the same schema runs on a phone (`sqflite`) and
/// in a plain Dart test (`sqflite_common_ffi`). This package never imports
/// Flutter, which keeps every storage rule testable on CI without a device.
class AppDatabase {
  AppDatabase._(this.db);

  static const int schemaVersion = 5;
  static const String fileName = 'best.db';

  final Database db;

  static Future<AppDatabase> open({
    required DatabaseFactory factory,
    required String path,
  }) async {
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await _create(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await _createDownloads(db);
          }
          if (oldVersion < 3) {
            await _addDownloadBytes(db);
          }
          if (oldVersion < 4) {
            await _addShelfColumns(db);
            await _createActivity(db);
          }
          if (oldVersion < 5) {
            await _addUnitMemo(db);
          }
        },
      ),
    );
    return AppDatabase._(db);
  }

  static Future<void> _create(Database db) async {
    await db.execute('''
      CREATE TABLE media (
        id TEXT PRIMARY KEY,
        source_id TEXT NOT NULL,
        url TEXT NOT NULL,
        title TEXT NOT NULL,
        native_title TEXT,
        cover_url TEXT,
        synopsis TEXT,
        author TEXT,
        kind TEXT NOT NULL,
        status TEXT NOT NULL,
        year INTEGER,
        genres TEXT NOT NULL DEFAULT '[]',
        in_library INTEGER NOT NULL DEFAULT 0,
        favorite INTEGER NOT NULL DEFAULT 0,
        state TEXT NOT NULL DEFAULT 'none',
        tags TEXT NOT NULL DEFAULT '[]',
        added_at INTEGER NOT NULL DEFAULT 0,
        last_opened_at INTEGER NOT NULL DEFAULT 0,
        UNIQUE (source_id, url)
      )
    ''');

    await db.execute('''
      CREATE TABLE unit (
        id TEXT PRIMARY KEY,
        media_id TEXT NOT NULL REFERENCES media(id) ON DELETE CASCADE,
        url TEXT NOT NULL,
        kind TEXT NOT NULL,
        number REAL NOT NULL,
        title TEXT NOT NULL,
        published_at INTEGER NOT NULL DEFAULT 0,
        page_count INTEGER NOT NULL DEFAULT 0,
        memo TEXT NOT NULL DEFAULT '',
        UNIQUE (media_id, url)
      )
    ''');

    await db.execute('''
      CREATE TABLE progress (
        unit_id TEXT PRIMARY KEY REFERENCES unit(id) ON DELETE CASCADE,
        position INTEGER NOT NULL DEFAULT 0,
        total INTEGER NOT NULL DEFAULT 0,
        completed INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL
      )
    ''');

    await _createDownloads(db);
    await _createActivity(db);

    await db.execute('CREATE INDEX media_library ON media (in_library, title)');
    await db.execute('CREATE INDEX unit_media ON unit (media_id, number)');
    await db
        .execute('CREATE INDEX progress_recent ON progress (updated_at DESC)');
  }

  /// extensions-lib `memo` travels with a chapter so sources that keep their
  /// manga path there can build a page list from a stored chapter.
  ///
  /// Guarded because a partial or hand-made database may not have a `unit`
  /// table at all; a migration must not turn that into an open failure.
  static Future<void> _addUnitMemo(Database db) async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'unit'",
    );
    if (tables.isEmpty) return;
    final columns = await db.rawQuery('PRAGMA table_info(unit)');
    if (columns.any((row) => row['name'] == 'memo')) return;
    await db.execute(
      "ALTER TABLE unit ADD COLUMN memo TEXT NOT NULL DEFAULT ''",
    );
  }

  static Future<void> _createDownloads(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS downloads (
        unit_id TEXT PRIMARY KEY,
        media_id TEXT NOT NULL,
        source_id TEXT NOT NULL,
        media_url TEXT NOT NULL,
        unit_url TEXT NOT NULL,
        media_title TEXT NOT NULL,
        unit_title TEXT NOT NULL,
        total INTEGER NOT NULL DEFAULT 0,
        completed INTEGER NOT NULL DEFAULT 0,
        bytes INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL,
        error TEXT,
        directory TEXT,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS downloads_recent ON downloads (updated_at DESC)',
    );
  }

  /// Version 4 adds the person's own plan and lists to a work.
  static Future<void> _addShelfColumns(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(media)');
    final names = columns.map((column) => column['name']).toSet();
    if (!names.contains('state')) {
      await db.execute(
        "ALTER TABLE media ADD COLUMN state TEXT NOT NULL DEFAULT 'none'",
      );
    }
    if (!names.contains('tags')) {
      await db.execute(
        "ALTER TABLE media ADD COLUMN tags TEXT NOT NULL DEFAULT '[]'",
      );
    }
  }

  /// One row per local day of reading. Small enough to keep forever: a year of
  /// daily use is a few hundred rows.
  static Future<void> _createActivity(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS activity (
        day TEXT PRIMARY KEY,
        pages INTEGER NOT NULL DEFAULT 0,
        minutes INTEGER NOT NULL DEFAULT 0,
        units INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  /// Version 2 shipped without byte accounting. A fresh install already has
  /// the column; an upgrade adds it in place.
  static Future<void> _addDownloadBytes(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(downloads)');
    final hasBytes = columns.any((column) => column['name'] == 'bytes');
    if (!hasBytes) {
      await db.execute(
        'ALTER TABLE downloads ADD COLUMN bytes INTEGER NOT NULL DEFAULT 0',
      );
    }
  }

  Future<void> close() => db.close();
}
