import 'dart:convert';

import '../budget/state/budget_store.dart';
import '../media/state/media_store.dart';

/// What a restore brought in.
class RestoreResult {
  const RestoreResult({required this.entries, this.cards = 0, this.transactions = 0});
  final int entries;
  final int cards;
  final int transactions;
}

/// Builds and restores a single JSON backup file covering every module.
/// Media is under `media`, the Budget under `budget` (backups made before Budget existed have no such key).
/// Planner will add its own key next to them.
class BackupService {
  static const _app = 'faelen';
  static const _version = 1;

  Future<String> build(MediaStore media, {BudgetStore? budget, DateTime? now}) async {
    return const JsonEncoder.withIndent('  ').convert({
      'app': _app,
      'version': _version,
      'exportedAt': (now ?? DateTime.now()).toUtc().toIso8601String(),
      'media': await media.exportData(),
      if (budget != null && !budget.loading && budget.accounts.isNotEmpty) 'budget': budget.exportData(),
    });
  }

  /// Throws [FormatException] if [json] is not a Faelen backup.
  Future<RestoreResult> restore(String json, MediaStore media, {BudgetStore? budget, required bool replace}) async {
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
    final entries = await media.importData(data, replace: replace);

    final extra = decoded['budget'];
    if (extra == null || budget == null) return RestoreResult(entries: entries);
    final b = await budget.importData(extra, replace: replace);
    return RestoreResult(entries: entries, cards: b.accounts, transactions: b.txns);
  }

  static String fileName(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return 'faelen-backup-${d.year}-${two(d.month)}-${two(d.day)}.json';
  }
}
