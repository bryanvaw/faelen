import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/media_entry.dart';

/// Persists the whole list as one JSON string in the device's local storage.
class StorageService {
  static const _key = 'media_entries_v1';

  Future<List<MediaEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    return [
      for (final j in jsonDecode(raw) as List) MediaEntry.fromJson(j as Map<String, dynamic>),
    ];
  }

  Future<void> save(List<MediaEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode([for (final e in entries) e.toJson()]));
  }
}
