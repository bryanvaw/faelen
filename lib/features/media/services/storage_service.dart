import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/media_entry.dart';

/// Persists the whole list as one JSON string in the device's local storage.
///
/// Two safety nets keep a bad read from destroying data: entries that cannot be parsed are
/// skipped one by one (not the whole list), and the previous copy of the list is kept under
/// [_prevKey] before every write. Anything unreadable is parked under [_corruptKey].
class StorageService {
  static const _key = 'media_entries_v1';
  static const _prevKey = 'media_entries_prev_v1';
  static const _corruptKey = 'media_entries_corrupt_v1';
  static const _sortKey = 'media_sort_v1';

  /// Entries skipped by the last [load] because they could not be read.
  int skipped = 0;

  /// True when the last [load] had to fall back to the previous copy of the list.
  bool recovered = false;

  Future<List<MediaEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
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
    final prefs = await SharedPreferences.getInstance();
    final old = prefs.getString(_key);
    if (old != null) await prefs.setString(_prevKey, old);
    await prefs.setString(_key, jsonEncode([for (final e in entries) e.toJson()]));
  }

  Future<String?> loadSort() async => (await SharedPreferences.getInstance()).getString(_sortKey);

  Future<void> saveSort(String name) async => (await SharedPreferences.getInstance()).setString(_sortKey, name);
}
