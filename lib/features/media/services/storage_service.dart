import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/media_entry.dart';
import 'entry_database.dart';

/// Persists the media list on the device.
///
/// In the app it is a SQLite file ([StorageService.forApp]): saving writes only the entries that
/// changed, not the whole library. Without a database (tests, and the browser build, where SQLite
/// is not available) the whole list is one JSON string in local storage.
///
/// Two safety nets keep a bad read from destroying data: entries that cannot be parsed are
/// skipped one by one (not the whole list), and in the JSON mode the previous copy of the list is
/// kept under [_prevKey] before every write. Anything unreadable is parked under [_corruptKey].
class StorageService {
  // ignore: prefer_initializing_formals
  StorageService({EntryDatabase? db}) : _db = db;

  /// SQLite everywhere it exists, the JSON string in the browser.
  factory StorageService.forApp() => StorageService(db: kIsWeb ? null : EntryDatabase());

  final EntryDatabase? _db;

  /// The entries as the database holds them, by id. Saving compares by identity against this, so
  /// only entries that were replaced since the last load or save are written.
  Map<String, MediaEntry> _written = {};

  static const _migratedKey = 'media_sqlite_migrated_v1';
  static const _key = 'media_entries_v1';
  static const _prevKey = 'media_entries_prev_v1';
  static const _corruptKey = 'media_entries_corrupt_v1';
  static const _sortKey = 'media_sort_v1';

  /// Entries skipped by the last [load] because they could not be read.
  int skipped = 0;

  /// True when the last [load] had to fall back to the previous copy of the list.
  bool recovered = false;

  /// With [reload], first picks up anything another isolate (a notification button) saved.
  Future<List<MediaEntry>> load({bool reload = false}) async {
    final db = _db;
    if (db == null) return _loadJson(reload: reload);

    final prefs = await SharedPreferences.getInstance();
    if (reload) await prefs.reload();
    skipped = 0;
    recovered = false;
    // First run on SQLite: bring the old JSON list across once. The old copy stays untouched,
    // and anything the old reader skipped or recovered is reported like it always was.
    if (prefs.getBool(_migratedKey) != true) {
      if (await db.count() == 0) await db.write(upserts: await _loadJson(reload: false));
      await prefs.setBool(_migratedKey, true);
    }
    final entries = await _entriesIn(db);
    _written = {for (final e in entries) e.id: e};
    return entries;
  }

  /// The entries in the file. An entry that has not changed since the last load or save keeps its
  /// old instance, so the next [save] can tell by identity that it needs no write.
  Future<List<MediaEntry>> _entriesIn(EntryDatabase db) async {
    final out = <MediaEntry>[];
    for (final raw in await db.readAll()) {
      try {
        final fresh = MediaEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        final old = _written[fresh.id];
        out.add(old != null && jsonEncode(old.toJson()) == jsonEncode(fresh.toJson()) ? old : fresh);
      } catch (_) {
        skipped++; // the row stays in the file, it is just not shown
      }
    }
    return out;
  }

  Future<List<MediaEntry>> _loadJson({required bool reload}) async {
    final prefs = await SharedPreferences.getInstance();
    if (reload) await prefs.reload();
    skipped = 0;
    recovered = false;
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    var entries = _parse(raw);
    if (entries == null) {
      // The whole blob is unreadable: park it, then try the copy from before the last write.
      await prefs.setString(_corruptKey, raw);
      final prev = prefs.getString(_prevKey);
      entries = prev == null ? null : _parse(prev);
      recovered = entries != null;
      skipped = 0;
    }
    if (skipped > 0) await prefs.setString(_corruptKey, raw);
    return entries ?? [];
  }

  /// Entries in [raw], skipping (and counting) the ones that fail; null if [raw] is not a JSON list.
  List<MediaEntry>? _parse(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (decoded is! List) return null;
    final out = <MediaEntry>[];
    for (final j in decoded) {
      try {
        out.add(MediaEntry.fromJson(j as Map<String, dynamic>));
      } catch (_) {
        skipped++;
      }
    }
    return out;
  }

  Future<void> save(List<MediaEntry> entries) async {
    final db = _db;
    if (db != null) {
      final ids = {for (final e in entries) e.id};
      await db.write(
        upserts: [for (final e in entries) if (!identical(_written[e.id], e)) e],
        deletes: [for (final id in _written.keys) if (!ids.contains(id)) id],
      );
      _written = {for (final e in entries) e.id: e};
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final old = prefs.getString(_key);
    if (old != null) await prefs.setString(_prevKey, old);
    await prefs.setString(_key, jsonEncode([for (final e in entries) e.toJson()]));
  }

  /// The saved copy of one entry, read straight from the file (another isolate may have changed it
  /// since this one loaded). Null in the JSON mode, or when the entry is not there or unreadable.
  Future<MediaEntry?> loadOne(String id) async {
    final db = _db;
    if (db == null) return null;
    try {
      final raw = await db.readOne(id);
      if (raw == null) return null;
      final fresh = MediaEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      final old = _written[id];
      return old != null && jsonEncode(old.toJson()) == jsonEncode(fresh.toJson()) ? old : fresh;
    } catch (_) {
      return null;
    }
  }

  /// Closes the database file (a no-op in the JSON mode).
  Future<void> close() async => _db?.close();

  Future<String?> loadSort() async => (await SharedPreferences.getInstance()).getString(_sortKey);

  Future<void> saveSort(String name) async => (await SharedPreferences.getInstance()).setString(_sortKey, name);
}
