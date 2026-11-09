import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/task.dart';

/// Where the tasks live. The app uses [SqlitePlannerRepo]; tests and the browser build use [MemoryPlannerRepo].
abstract class PlannerRepo {
  Future<List<Task>> load();
  Future<void> put(Task t);
  Future<void> delete(String id);

  /// Replaces everything (a "replace" restore from a backup), all or nothing.
  Future<void> replaceAll(List<Task> tasks);
}

PlannerRepo newPlannerRepo() => SqlitePlannerRepo.usesSqlite ? SqlitePlannerRepo() : MemoryPlannerRepo();

class MemoryPlannerRepo implements PlannerRepo {
  final _tasks = <String, Task>{};

  @override
  Future<List<Task>> load() async => _tasks.values.toList();
  @override
  Future<void> put(Task t) async => _tasks[t.id] = t;
  @override
  Future<void> delete(String id) async => _tasks.remove(id);
  @override
  Future<void> replaceAll(List<Task> tasks) async {
    _tasks
      ..clear()
      ..addEntries(tasks.map((t) => MapEntry(t.id, t)));
  }
}

/// Its own SQLite file (`faelen_planner.db`), like the Budget: a JSON `data` column next to the
/// columns that are queried, so a new task field never needs a schema change.
class SqlitePlannerRepo implements PlannerRepo {
  // ignore: prefer_initializing_formals
  SqlitePlannerRepo({DatabaseFactory? factory, this.path}) : _factory = factory;

  final DatabaseFactory? _factory;
  final String? path;
  Future<Database>? _db;

  Future<Database> get _open => _db ??= _openDb();

  static bool get usesSqlite => !kIsWeb;

  Future<Database> _openDb() async {
    final f = _factory ?? _platformFactory();
    final file = path ?? p.join(await _folder(), 'faelen_planner.db');
    return f.openDatabase(
      file,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) => db.execute('CREATE TABLE tasks (id TEXT PRIMARY KEY, data TEXT NOT NULL)'),
      ),
    );
  }

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

  @override
  Future<List<Task>> load() async {
    final db = await _open;
    final out = <Task>[];
    for (final r in await db.rawQuery('SELECT data FROM tasks ORDER BY rowid')) {
      try {
        final t = Task.fromJson(jsonDecode(r['data']! as String));
        if (t != null) out.add(t);
      } catch (_) {} // one damaged row never hides the rest
    }
    return out;
  }

  @override
  Future<void> put(Task t) async {
    final db = await _open;
    await db.insert('tasks', {'id': t.id, 'data': jsonEncode(t.toJson())}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> delete(String id) async {
    final db = await _open;
    await db.delete('tasks', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> replaceAll(List<Task> tasks) async {
    final db = await _open;
    await db.transaction((t) async {
      await t.delete('tasks');
      for (final x in tasks) {
        await t.insert('tasks', {'id': x.id, 'data': jsonEncode(x.toJson())});
      }
    });
  }
}
