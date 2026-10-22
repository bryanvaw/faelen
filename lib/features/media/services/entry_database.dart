import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/media_entry.dart';

/// The media list as rows in one SQLite file in the app's private storage (nothing leaves the
/// device). Each entry is one row: the columns drive filtering and paging, `data` holds the full
/// entry as JSON so new fields never need a schema change.
class EntryDatabase {
  /// [factory] and [path] are for tests (an ffi factory with a temp file or in-memory path).
  // ignore: prefer_initializing_formals
  EntryDatabase({DatabaseFactory? factory, this.path}) : _factory = factory;

  final DatabaseFactory? _factory;
  final String? path;
  Future<Database>? _db;

  static const _version = 1;

  Future<Database> get _open => _db ??= _openDb();

  Future<Database> _openDb() async {
    final f = _factory ?? _platformFactory();
    final file = path ?? p.join(await _folder(), 'faelen.db');
    return f.openDatabase(
      file,
      options: OpenDatabaseOptions(
        version: _version,
        // The notification buttons write from another isolate; wait for each other instead of failing.
        onConfigure: (db) => db.rawQuery('PRAGMA busy_timeout = 5000'),
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE entries (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              type TEXT NOT NULL,
              status TEXT NOT NULL,
              updated_at INTEGER NOT NULL,
              data TEXT NOT NULL
            )''');
          await db.execute('CREATE INDEX entries_type_status ON entries (type, status)');
        },
      ),
    );
  }

  /// Android and iOS use the sqflite plugin; desktop has no plugin, so it goes through ffi.
  static DatabaseFactory _platformFactory() {
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      return databaseFactoryFfi;
    }
    return databaseFactory;
  }

  static Future<String> _folder() async {
    if (Platform.isWindows || Platform.isLinux) return (await getApplicationSupportDirectory()).path;
    return _platformFactory().getDatabasesPath();
  }

  Future<int> count() async {
    final db = await _open;
    return Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM entries')) ?? 0;
  }

  /// The JSON of every row, in the order they were first saved.
  Future<List<String>> readAll() async {
    final db = await _open;
    final rows = await db.rawQuery('SELECT data FROM entries ORDER BY rowid');
    return [for (final r in rows) r['data']! as String];
  }

  /// The JSON of one row, or null if there is none.
  Future<String?> readOne(String id) async {
    final db = await _open;
    final rows = await db.rawQuery('SELECT data FROM entries WHERE id = ?', [id]);
    return rows.isEmpty ? null : rows.first['data']! as String;
  }

  /// Writes only the rows that changed, all or nothing.
  Future<void> write({Iterable<MediaEntry> upserts = const [], Iterable<String> deletes = const []}) async {
    final db = await _open;
    final batch = db.batch();
    for (final id in deletes) {
      batch.delete('entries', where: 'id = ?', whereArgs: [id]);
    }
    for (final e in upserts) {
      batch.insert(
        'entries',
        {
          'id': e.id,
          'title': e.title,
          'type': e.type.name,
          'status': e.status.name,
          'updated_at': e.updatedAt,
          'data': jsonEncode(e.toJson()),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> close() async {
    final db = _db;
    _db = null;
    if (db != null) await (await db).close();
  }
}
