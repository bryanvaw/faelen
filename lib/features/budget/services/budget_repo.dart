import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/budget_models.dart';

class BudgetData {
  const BudgetData({this.accounts = const [], this.txns = const [], this.limits = const {}, this.bills = const [], this.goals = const []});
  final List<Account> accounts;
  final List<Txn> txns;
  final List<Bill> bills;
  final List<Goal> goals;

  /// Monthly limit in centavos per expense category id.
  final Map<String, int> limits;
}

/// Where the Budget lives. The app uses [SqliteBudgetRepo]; tests and the browser build use [MemoryBudgetRepo].
abstract class BudgetRepo {
  Future<BudgetData> load();
  Future<void> putAccount(Account a);

  /// Removes the card and every transaction on it.
  Future<void> deleteAccount(String id);
  Future<void> putTxn(Txn t);
  Future<void> deleteTxn(String id);

  /// A limit of 0 removes it.
  Future<void> setLimit(String category, int cents);
  Future<void> putBill(Bill b);
  Future<void> deleteBill(String id);
  Future<void> putGoal(Goal g);
  Future<void> deleteGoal(String id);

  /// Replaces everything (a "replace" restore from a backup), all or nothing.
  Future<void> replaceAll(BudgetData data);
}

class MemoryBudgetRepo implements BudgetRepo {
  final _accounts = <String, Account>{};
  final _txns = <String, Txn>{};
  final _limits = <String, int>{};
  final _bills = <String, Bill>{};
  final _goals = <String, Goal>{};

  @override
  Future<BudgetData> load() async => BudgetData(
        accounts: _accounts.values.toList(),
        txns: _txns.values.toList(),
        limits: Map.of(_limits),
        bills: _bills.values.toList(),
        goals: _goals.values.toList(),
      );

  @override
  Future<void> putBill(Bill b) async => _bills[b.id] = b;

  @override
  Future<void> deleteBill(String id) async => _bills.remove(id);

  @override
  Future<void> putGoal(Goal g) async => _goals[g.id] = g;

  @override
  Future<void> deleteGoal(String id) async => _goals.remove(id);

  @override
  Future<void> replaceAll(BudgetData d) async {
    _accounts
      ..clear()
      ..addEntries(d.accounts.map((a) => MapEntry(a.id, a)));
    _txns
      ..clear()
      ..addEntries(d.txns.map((t) => MapEntry(t.id, t)));
    _limits
      ..clear()
      ..addAll(d.limits);
    _bills
      ..clear()
      ..addEntries(d.bills.map((b) => MapEntry(b.id, b)));
    _goals
      ..clear()
      ..addEntries(d.goals.map((g) => MapEntry(g.id, g)));
  }

  @override
  Future<void> putAccount(Account a) async => _accounts[a.id] = a;

  @override
  Future<void> deleteAccount(String id) async {
    _accounts.remove(id);
    _txns.removeWhere((_, t) => t.accountId == id);
  }

  @override
  Future<void> putTxn(Txn t) async => _txns[t.id] = t;

  @override
  Future<void> deleteTxn(String id) async => _txns.remove(id);

  @override
  Future<void> setLimit(String category, int cents) async => cents <= 0 ? _limits.remove(category) : _limits[category] = cents;
}

/// Its own SQLite file (`faelen_budget.db`), separate from the Media list. Each record is a JSON `data`
/// column next to the few columns we query, so new fields never need a schema change.
class SqliteBudgetRepo implements BudgetRepo {
  // ignore: prefer_initializing_formals
  SqliteBudgetRepo({DatabaseFactory? factory, this.path}) : _factory = factory;

  final DatabaseFactory? _factory;
  final String? path;
  Future<Database>? _db;

  Future<Database> get _open => _db ??= _openDb();

  static bool get usesSqlite => !kIsWeb;

  Future<Database> _openDb() async {
    final f = _factory ?? _platformFactory();
    final file = path ?? p.join(await _folder(), 'faelen_budget.db');
    return f.openDatabase(
      file,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, _) async {
          await db.execute('CREATE TABLE accounts (id TEXT PRIMARY KEY, data TEXT NOT NULL)');
          await db.execute('CREATE TABLE txns (id TEXT PRIMARY KEY, account_id TEXT NOT NULL, day INTEGER NOT NULL, data TEXT NOT NULL)');
          await db.execute('CREATE INDEX txns_day ON txns (day)');
          await db.execute('CREATE TABLE limits (category TEXT PRIMARY KEY, cents INTEGER NOT NULL)');
          await _createPlans(db);
        },
        onUpgrade: (db, from, _) async {
          if (from < 2) await _createPlans(db);
        },
      ),
    );
  }

  static Future<void> _createPlans(Database db) async {
    await db.execute('CREATE TABLE bills (id TEXT PRIMARY KEY, data TEXT NOT NULL)');
    await db.execute('CREATE TABLE goals (id TEXT PRIMARY KEY, data TEXT NOT NULL)');
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
  Future<BudgetData> load() async {
    final db = await _open;
    final accounts = <Account>[];
    for (final r in await db.rawQuery('SELECT data FROM accounts ORDER BY rowid')) {
      try {
        final a = Account.fromJson(jsonDecode(r['data']! as String));
        if (a != null) accounts.add(a);
      } catch (_) {} // one damaged row never hides the rest
    }
    final txns = <Txn>[];
    for (final r in await db.rawQuery('SELECT data FROM txns')) {
      try {
        final t = Txn.fromJson(jsonDecode(r['data']! as String));
        if (t != null) txns.add(t);
      } catch (_) {}
    }
    final limits = <String, int>{};
    for (final r in await db.rawQuery('SELECT category, cents FROM limits')) {
      limits[r['category']! as String] = r['cents']! as int;
    }
    final bills = <Bill>[];
    for (final r in await db.rawQuery('SELECT data FROM bills ORDER BY rowid')) {
      try {
        final b = Bill.fromJson(jsonDecode(r['data']! as String));
        if (b != null) bills.add(b);
      } catch (_) {}
    }
    final goals = <Goal>[];
    for (final r in await db.rawQuery('SELECT data FROM goals ORDER BY rowid')) {
      try {
        final g = Goal.fromJson(jsonDecode(r['data']! as String));
        if (g != null) goals.add(g);
      } catch (_) {}
    }
    return BudgetData(accounts: accounts, txns: txns, limits: limits, bills: bills, goals: goals);
  }

  @override
  Future<void> putBill(Bill b) async {
    final db = await _open;
    await db.insert('bills', {'id': b.id, 'data': jsonEncode(b.toJson())}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> deleteBill(String id) async {
    final db = await _open;
    await db.delete('bills', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> putGoal(Goal g) async {
    final db = await _open;
    await db.insert('goals', {'id': g.id, 'data': jsonEncode(g.toJson())}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> deleteGoal(String id) async {
    final db = await _open;
    await db.delete('goals', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> replaceAll(BudgetData d) async {
    final db = await _open;
    await db.transaction((t) async {
      for (final table in ['accounts', 'txns', 'limits', 'bills', 'goals']) {
        await t.delete(table);
      }
      for (final a in d.accounts) {
        await t.insert('accounts', {'id': a.id, 'data': jsonEncode(a.toJson())});
      }
      for (final x in d.txns) {
        await t.insert('txns', {'id': x.id, 'account_id': x.accountId, 'day': dayKey(x.day), 'data': jsonEncode(x.toJson())});
      }
      for (final e in d.limits.entries) {
        await t.insert('limits', {'category': e.key, 'cents': e.value});
      }
      for (final b in d.bills) {
        await t.insert('bills', {'id': b.id, 'data': jsonEncode(b.toJson())});
      }
      for (final g in d.goals) {
        await t.insert('goals', {'id': g.id, 'data': jsonEncode(g.toJson())});
      }
    });
  }

  @override
  Future<void> putAccount(Account a) async {
    final db = await _open;
    await db.insert('accounts', {'id': a.id, 'data': jsonEncode(a.toJson())}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> deleteAccount(String id) async {
    final db = await _open;
    await db.transaction((t) async {
      await t.delete('txns', where: 'account_id = ?', whereArgs: [id]);
      await t.delete('accounts', where: 'id = ?', whereArgs: [id]);
    });
  }

  @override
  Future<void> putTxn(Txn t) async {
    final db = await _open;
    await db.insert(
      'txns',
      {'id': t.id, 'account_id': t.accountId, 'day': dayKey(t.day), 'data': jsonEncode(t.toJson())},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> deleteTxn(String id) async {
    final db = await _open;
    await db.delete('txns', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> setLimit(String category, int cents) async {
    final db = await _open;
    if (cents <= 0) {
      await db.delete('limits', where: 'category = ?', whereArgs: [category]);
    } else {
      await db.insert('limits', {'category': category, 'cents': cents}, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<void> close() async {
    final db = _db;
    _db = null;
    if (db != null) await (await db).close();
  }
}

BudgetRepo newBudgetRepo() => SqliteBudgetRepo.usesSqlite ? SqliteBudgetRepo() : MemoryBudgetRepo();
