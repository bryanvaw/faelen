import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../models/budget_models.dart';
import '../services/budget_repo.dart';

/// Per-category spend for one month.
class CategorySpend {
  const CategorySpend(this.category, this.spent, this.limit);
  final Category category;
  final int spent;

  /// 0 = no limit set.
  final int limit;
  bool get over => limit > 0 && spent > limit;
}

class MonthSummary {
  const MonthSummary({required this.income, required this.expense});
  final int income;
  final int expense;
  int get net => income - expense;
}

class BudgetStore extends ChangeNotifier {
  BudgetStore(this._repo);

  final BudgetRepo _repo;

  List<Account> _accounts = [];
  List<Txn> _txns = []; // newest day first
  Map<String, int> _limits = {};
  List<Bill> _bills = [];
  List<Goal> _goals = [];
  bool loading = true;
  Object? error;
  Object? _saveError;
  var _n = 0;

  String? _selectedId;

  /// The card the screens are centred on, or null when the overview of every card is showing (the
  /// default once there is more than one card). Buttons, tabs and sheets take its colour. Not saved.
  Account? get selected {
    if (_accounts.length == 1) return _accounts.first;
    final id = _selectedId;
    return id == null ? null : account(id);
  }

  /// True when more than one card exists and none is picked: the screens show every card together.
  bool get overview => _accounts.length > 1 && selected == null;

  void select(String id) {
    if (_selectedId == id || account(id) == null) return;
    _selectedId = id;
    notifyListeners();
  }

  void selectAll() {
    if (_selectedId == null) return;
    _selectedId = null;
    notifyListeners();
  }

  /// The month the Budgets tab shows (first day).
  DateTime month = _firstOfMonth(DateTime.now());

  static DateTime _firstOfMonth(DateTime d) => DateTime(d.year, d.month);

  List<Account> get accounts => List.unmodifiable(_accounts);
  List<Txn> get txns => List.unmodifiable(_txns);
  Map<String, int> get limits => Map.unmodifiable(_limits);
  List<Bill> get bills => List.unmodifiable(_bills);
  List<Goal> get goals => List.unmodifiable(_goals);

  String newId() => '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${_n++}';

  Future<void> load() async {
    try {
      final d = await _repo.load();
      _accounts = d.accounts;
      _txns = d.txns..sort(_newestFirst);
      _limits = d.limits;
      _bills = d.bills;
      _goals = d.goals;
      error = null;
    } catch (e) {
      error = e;
    }
    loading = false;
    notifyListeners();
    await postDueBills();
  }

  static int _newestFirst(Txn a, Txn b) {
    final c = b.day.compareTo(a.day);
    return c != 0 ? c : b.createdAt.compareTo(a.createdAt);
  }

  /// A save that failed, once; the screen shows it as a snackbar.
  Object? takeSaveError() {
    final e = _saveError;
    _saveError = null;
    return e;
  }

  Future<void> _save(Future<void> Function() write) async {
    try {
      await write();
    } catch (e) {
      _saveError = e;
      notifyListeners();
    }
  }

  Account? account(String id) {
    for (final a in _accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  int balanceOf(Account a) => a.openingCents + _txns.where((t) => t.accountId == a.id).fold(0, (s, t) => s + t.signed);

  int get totalBalance => _accounts.fold(0, (s, a) => s + balanceOf(a));

  Future<void> saveAccount(Account a) async {
    final i = _accounts.indexWhere((x) => x.id == a.id);
    i < 0 ? _accounts.add(a) : _accounts[i] = a;
    notifyListeners();
    await _save(() => _repo.putAccount(a));
  }

  /// Removes the card, its transactions and the other half of any transfer that touched it (or the
  /// other card's balance would be left wrong). Returns what was removed so the caller can offer Undo.
  Future<({Account account, List<Txn> txns, List<Bill> bills})?> deleteAccount(String id) async {
    final a = account(id);
    if (a == null) return null;
    final gone = _txns.where((t) => t.accountId == id).toList();
    final pairs = gone.map((t) => t.pair).whereType<String>().toSet();
    final others = _txns.where((t) => t.accountId != id && t.pair != null && pairs.contains(t.pair)).toList();
    final removed = [...gone, ...others];
    final removedIds = removed.map((t) => t.id).toSet();
    _accounts.removeWhere((x) => x.id == id);
    _txns.removeWhere((t) => removedIds.contains(t.id));
    // Bills on this card would have nowhere to post.
    final billsGone = _bills.where((b) => b.accountId == id).toList();
    _bills.removeWhere((b) => b.accountId == id);
    notifyListeners();
    await _save(() async {
      await _repo.deleteAccount(id);
      for (final t in others) {
        await _repo.deleteTxn(t.id);
      }
      for (final b in billsGone) {
        await _repo.deleteBill(b.id);
      }
    });
    return (account: a, txns: removed, bills: billsGone);
  }

  /// Puts back what [deleteAccount] removed, bills included.
  Future<void> restoreAccount(Account a, List<Txn> txns, {List<Bill> bills = const []}) async {
    _accounts.add(a);
    _txns = [..._txns, ...txns]..sort(_newestFirst);
    _bills = [..._bills, ...bills];
    notifyListeners();
    await _save(() async {
      await _repo.putAccount(a);
      for (final t in txns) {
        await _repo.putTxn(t);
      }
      for (final b in bills) {
        await _repo.putBill(b);
      }
    });
  }

  Future<void> saveTxn(Txn t) async {
    final i = _txns.indexWhere((x) => x.id == t.id);
    i < 0 ? _txns.add(t) : _txns[i] = t;
    _txns.sort(_newestFirst);
    notifyListeners();
    await _save(() => _repo.putTxn(t));
  }

  /// Adds many transactions at once (an imported statement): one screen update, one write.
  Future<void> addTxns(List<Txn> txns) => restoreTxns(txns);

  /// Deletes the transaction (and the other half of a transfer). Returns what was removed, for Undo.
  Future<List<Txn>> deleteTxn(String id) async {
    final t = _txns.where((x) => x.id == id).firstOrNull;
    if (t == null) return const [];
    final gone = t.pair == null ? [t] : _txns.where((x) => x.pair == t.pair).toList();
    final ids = gone.map((x) => x.id).toSet();
    _txns.removeWhere((x) => ids.contains(x.id));
    notifyListeners();
    await _save(() async {
      for (final x in gone) {
        await _repo.deleteTxn(x.id);
      }
    });
    return gone;
  }

  /// Puts back what [deleteTxn] removed.
  Future<void> restoreTxns(List<Txn> txns) async {
    for (final t in txns) {
      final i = _txns.indexWhere((x) => x.id == t.id);
      i < 0 ? _txns.add(t) : _txns[i] = t;
    }
    _txns.sort(_newestFirst);
    notifyListeners();
    await _save(() async {
      for (final t in txns) {
        await _repo.putTxn(t);
      }
    });
  }

  /// Moves money between two cards: an expense on [from] and an income on [to], tied together.
  Future<void> transfer({required String from, required String to, required int cents, String note = '', DateTime? day}) async {
    final a = account(from), b = account(to);
    if (from == to || cents <= 0 || a == null || b == null) return;
    final d = day ?? dateOnly(DateTime.now());
    final pair = newId();
    final now = DateTime.now().millisecondsSinceEpoch;
    final text = note.trim();
    await restoreTxns([
      Txn(id: newId(), accountId: from, cents: cents, income: false, category: transferCategory.id, day: d, note: text.isEmpty ? 'To ${b.name}' : text, createdAt: now, pair: pair),
      Txn(id: newId(), accountId: to, cents: cents, income: true, category: transferCategory.id, day: d, note: text.isEmpty ? 'From ${a.name}' : text, createdAt: now, pair: pair),
    ]);
  }

  // --- monthly bills -------------------------------------------------------------------------

  /// Saves a bill. A new bill starts from now on: it is not back-filled for months before it existed.
  Future<void> saveBill(Bill b, {DateTime? now}) async {
    final i = _bills.indexWhere((x) => x.id == b.id);
    var bill = b;
    if (i < 0 && b.lastPosted == 0) {
      final n = dateOnly(now ?? DateTime.now());
      final dueThisMonth = dueDate(n.year, n.month, b.day);
      final prev = DateTime(n.year, n.month - 1);
      bill = b.copyWith(lastPosted: dueThisMonth.isBefore(n) ? monthKey(n) : monthKey(prev));
    }
    i < 0 ? _bills.add(bill) : _bills[i] = bill;
    notifyListeners();
    await _save(() => _repo.putBill(bill));
    await postDueBills(now: now);
  }

  Future<Bill?> deleteBill(String id) async {
    final b = _bills.where((x) => x.id == id).firstOrNull;
    if (b == null) return null;
    _bills.removeWhere((x) => x.id == id);
    notifyListeners();
    await _save(() => _repo.deleteBill(id));
    return b;
  }

  /// Adds the expense for every bill whose due day has come, once per month. Safe to call as often as you like.
  Future<void> postDueBills({DateTime? now}) async {
    final today = dateOnly(now ?? DateTime.now());
    final fresh = <Txn>[];
    final changed = <Bill>[];
    for (var i = 0; i < _bills.length; i++) {
      var b = _bills[i];
      if (account(b.accountId) == null) continue;
      var guard = 0;
      while (guard++ < 36) {
        final next = _nextMonth(b, today);
        final due = dueDate(next.year, next.month, b.day);
        if (due.isAfter(today)) break;
        final id = 'bill-${b.id}-${monthKey(next)}';
        if (!_txns.any((t) => t.id == id)) {
          fresh.add(Txn(id: id, accountId: b.accountId, cents: b.cents, income: false, category: b.category, day: due, note: b.name, createdAt: DateTime.now().millisecondsSinceEpoch));
        }
        b = b.copyWith(lastPosted: monthKey(next));
      }
      if (b.lastPosted != _bills[i].lastPosted) {
        _bills[i] = b;
        changed.add(b);
      }
    }
    if (fresh.isEmpty && changed.isEmpty) return;
    _txns = [..._txns, ...fresh]..sort(_newestFirst);
    notifyListeners();
    await _save(() async {
      for (final t in fresh) {
        await _repo.putTxn(t);
      }
      for (final b in changed) {
        await _repo.putBill(b);
      }
    });
  }

  static DateTime _nextMonth(Bill b, DateTime today) {
    final last = b.lastPosted;
    return last == 0 ? DateTime(today.year, today.month) : DateTime(last ~/ 100, last % 100 + 1);
  }

  /// The next date a bill will be added.
  DateTime nextDue(Bill b, {DateTime? now}) {
    final next = _nextMonth(b, dateOnly(now ?? DateTime.now()));
    return dueDate(next.year, next.month, b.day);
  }

  // --- savings goals -------------------------------------------------------------------------

  Future<void> saveGoal(Goal g) async {
    final i = _goals.indexWhere((x) => x.id == g.id);
    i < 0 ? _goals.add(g) : _goals[i] = g;
    notifyListeners();
    await _save(() => _repo.putGoal(g));
  }

  Future<Goal?> deleteGoal(String id) async {
    final g = _goals.where((x) => x.id == id).firstOrNull;
    if (g == null) return null;
    _goals.removeWhere((x) => x.id == id);
    notifyListeners();
    await _save(() => _repo.deleteGoal(id));
    return g;
  }

  /// Puts money into a goal (or takes it out with a negative amount); never below zero.
  Future<void> adjustGoal(String id, int deltaCents) async {
    final g = _goals.where((x) => x.id == id).firstOrNull;
    if (g == null) return;
    final saved = (g.savedCents + deltaCents).clamp(0, 1 << 52);
    await saveGoal(g.copyWith(savedCents: saved));
  }

  // --- limits --------------------------------------------------------------------------------

  Future<void> setLimit(String category, int cents) async {
    cents <= 0 ? _limits.remove(category) : _limits[category] = cents;
    notifyListeners();
    await _save(() => _repo.setLimit(category, cents));
  }

  void shiftMonth(int by) {
    month = DateTime(month.year, month.month + by);
    notifyListeners();
  }

  bool get isCurrentMonth => month == _firstOfMonth(DateTime.now());

  bool _inMonth(Txn t, DateTime m) => t.day.year == m.year && t.day.month == m.month;

  /// In and out for a month, across every card or one card. Transfers are left out: the money only moved.
  MonthSummary summary({DateTime? of, String? accountId}) {
    final m = of ?? month;
    var inc = 0, exp = 0;
    for (final t in _txns) {
      if (t.pair != null || !_inMonth(t, m) || (accountId != null && t.accountId != accountId)) continue;
      t.income ? inc += t.cents : exp += t.cents;
    }
    return MonthSummary(income: inc, expense: exp);
  }

  /// Every expense category with its spend this month, biggest spend first; categories with a limit
  /// but no spend yet are included so the limit stays visible.
  List<CategorySpend> spending() => spendingFor(month);

  /// [spending] for any month (the overview always looks at the current one).
  List<CategorySpend> spendingFor(DateTime m) {
    final spent = <String, int>{};
    for (final t in _txns) {
      if (t.income || t.pair != null || !_inMonth(t, m)) continue;
      spent[t.category] = (spent[t.category] ?? 0) + t.cents;
    }
    final rows = [
      for (final c in expenseCategories) CategorySpend(c, spent[c.id] ?? 0, _limits[c.id] ?? 0),
    ]..sort((a, b) {
        final s = b.spent.compareTo(a.spent);
        return s != 0 ? s : (b.limit > 0 ? 1 : 0) - (a.limit > 0 ? 1 : 0);
      });
    return rows;
  }

  int get totalLimit => _limits.values.fold(0, (s, v) => s + v);

  /// Newest first; [accountId] limits it to one card.
  List<Txn> recent({String? accountId, int? limit}) {
    final list = _txns.where((t) => accountId == null || t.accountId == accountId);
    return (limit == null ? list : list.take(limit)).toList();
  }

  // --- backup --------------------------------------------------------------------------------

  /// True when there is anything worth putting in a backup (goals and limits need no card).
  bool get hasData => _accounts.isNotEmpty || _goals.isNotEmpty || _limits.isNotEmpty;

  Map<String, Object?> exportData() => {
        'accounts': [for (final a in _accounts) a.toJson()],
        'txns': [for (final t in _txns) t.toJson()],
        'limits': Map.of(_limits),
        'bills': [for (final b in _bills) b.toJson()],
        'goals': [for (final g in _goals) g.toJson()],
      };

  /// Reads the `budget` part of a backup; damaged rows are skipped. With [replace] false, items with the
  /// same id are overwritten and everything else is kept. Throws [FormatException] if [raw] is not budget data.
  Future<({int accounts, int txns})> importData(Object? raw, {required bool replace}) async {
    if (raw is! Map) throw const FormatException('Backup has no budget data');
    List<T> read<T>(Object? list, T? Function(Object?) parse) => list is List ? [for (final x in list) ?parse(x)] : <T>[];
    final accounts = read(raw['accounts'], Account.fromJson);
    final known = {...accounts.map((a) => a.id), if (!replace) ..._accounts.map((a) => a.id)};
    // A transaction whose card is not in the data would belong to nothing; drop it.
    final txns = read(raw['txns'], Txn.fromJson).where((t) => known.contains(t.accountId)).toList();
    final bills = read(raw['bills'], Bill.fromJson).where((b) => known.contains(b.accountId)).toList();
    final goals = read(raw['goals'], Goal.fromJson);
    final limits = <String, int>{};
    final l = raw['limits'];
    if (l is Map) {
      for (final e in l.entries) {
        final v = e.value;
        if (e.key is String && v is int && v > 0) limits[e.key as String] = v;
      }
    }

    Iterable<T> merged<T>(Iterable<T> mine, Iterable<T> theirs, String Function(T) id) => {for (final x in [...mine, ...theirs]) id(x): x}.values;
    final data = replace
        ? BudgetData(accounts: accounts, txns: txns, limits: limits, bills: bills, goals: goals)
        : BudgetData(
            accounts: merged(_accounts, accounts, (a) => a.id).toList(),
            txns: merged(_txns, txns, (t) => t.id).toList(),
            limits: {..._limits, ...limits},
            bills: merged(_bills, bills, (b) => b.id).toList(),
            goals: merged(_goals, goals, (g) => g.id).toList(),
          );
    await _repo.replaceAll(data); // all or nothing; memory only changes after it worked
    _accounts = data.accounts;
    _txns = data.txns..sort(_newestFirst);
    _limits = Map.of(data.limits);
    _bills = data.bills;
    _goals = data.goals;
    notifyListeners();
    await postDueBills();
    return (accounts: accounts.length, txns: txns.length);
  }
}
