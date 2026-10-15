import 'dart:convert';

import '../media/state/media_store.dart';

/// Builds and restores a single JSON backup file covering every module.
/// Planner and Budget will add their own keys next to `media`.
class BackupService {
  static const _app = 'faelen';
  static const _version = 1;

  Future<String> build(MediaStore media, {DateTime? now}) async {
    return const JsonEncoder.withIndent('  ').convert({
      'app': _app,
      'version': _version,
      'exportedAt': (now ?? DateTime.now()).toUtc().toIso8601String(),
      'media': await media.exportData(),
    });
  }

  /// Returns the number of entries imported. Throws [FormatException] if [json] is not a Faelen backup.
  Future<int> restore(String json, MediaStore media, {required bool replace}) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      throw const FormatException('This file is not valid JSON');
    }
    if (decoded is! Map || decoded['app'] != _app) {
      throw const FormatException('This is not a Faelen backup file');
    }
    final version = decoded['version'];
    if (version is! int || version > _version) {
      throw const FormatException('This backup was made by a newer version of Faelen');
    }
    final data = decoded['media'];
    if (data is! List) throw const FormatException('Backup has no media list');
    return media.importData(data, replace: replace);
  }

  static String fileName(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return 'faelen-backup-${d.year}-${two(d.month)}-${two(d.day)}.json';
  }
}
