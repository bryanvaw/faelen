import '../models/budget_models.dart';

/// Reads a bank or wallet statement exported as CSV. Nothing here is specific to one bank: it finds the
/// header row, guesses which column is the date, the description and the amount (or the money in / money
/// out pair), and the screen lets the user correct any guess before anything is added.

/// Splits CSV text into rows of cells. Handles quotes, doubled quotes, a byte-order mark, and comma,
/// semicolon, tab or pipe separators. Blank lines are dropped.
List<List<String>> parseCsv(String input) {
  var text = input.startsWith('﻿') ? input.substring(1) : input;
  text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

  // The separator is whichever of the usual four appears most outside quotes in the first lines.
  final counts = {',': 0, ';': 0, '\t': 0, '|': 0};
  var inQuotes = false;
  var lines = 0;
  for (var i = 0; i < text.length && lines < 6; i++) {
    final c = text[i];
    if (c == '"') {
      inQuotes = !inQuotes;
    } else if (!inQuotes) {
      if (c == '\n') {
        lines++;
      } else if (counts.containsKey(c)) {
        counts[c] = counts[c]! + 1;
      }
    }
  }
  final sep = counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;

  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  inQuotes = false;

  void endCell() {
    row.add(cell.toString().trim());
    cell.clear();
  }

  void endRow() {
    endCell();
    if (row.any((c) => c.isNotEmpty)) rows.add(row);
    row = <String>[];
  }

  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        cell.write(c);
      }
    } else if (c == '"') {
      inQuotes = true;
    } else if (c == sep) {
      endCell();
    } else if (c == '\n') {
      endRow();
    } else {
      cell.write(c);
    }
  }
  if (cell.isNotEmpty || row.isNotEmpty) endRow();
  return rows;
}

const _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, 'jul': 7, 'aug': 8, 'sep': 9, 'sept': 9, 'oct': 10, 'nov': 11, 'dec': 12, //
};

DateTime? _safeDate(int y, int m, int d) {
  if (m < 1 || m > 12 || d < 1 || d > 31 || y < 1990 || y > 2100) return null;
  final date = DateTime(y, m, d);
  return date.month == m ? date : null; // rejects 31 Feb
}

/// A date in the usual statement shapes: 2026-11-03, 11/03/2026, 3 Nov 2026, Nov 3, 2026, 03-Nov-26.
/// [dayFirst] settles 03/11/2026 (3 November when true, March 11 when false). A time after the date is ignored.
DateTime? parseStatementDate(String raw, {bool dayFirst = false}) {
  final s = raw.trim();
  if (s.isEmpty) return null;

  var m = RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})(?!\d)').firstMatch(s);
  if (m != null) return _safeDate(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));

  m = RegExp(r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})(?!\d)').firstMatch(s);
  if (m != null) {
    final a = int.parse(m[1]!), b = int.parse(m[2]!);
    var y = int.parse(m[3]!);
    if (y < 100) y += 2000;
    // Whichever number cannot be a month must be the day, whatever the default says.
    final dFirst = a > 12 ? true : (b > 12 ? false : dayFirst);
    return dFirst ? _safeDate(y, b, a) : _safeDate(y, a, b);
  }

  m = RegExp(r'^(\d{1,2})[ \-.]*([A-Za-z]{3,9})\.?[ \-,]*(\d{2,4})(?!\d)').firstMatch(s);
  if (m != null) {
    final mon = _months[m[2]!.toLowerCase().substring(0, 3)];
    var y = int.parse(m[3]!);
    if (y < 100) y += 2000;
    if (mon != null) return _safeDate(y, mon, int.parse(m[1]!));
  }

  m = RegExp(r'^([A-Za-z]{3,9})\.?[ \-]*(\d{1,2})(?:st|nd|rd|th)?,?[ \-]*(\d{2,4})(?!\d)').firstMatch(s);
  if (m != null) {
    final mon = _months[m[1]!.toLowerCase().substring(0, 3)];
    var y = int.parse(m[3]!);
    if (y < 100) y += 2000;
    if (mon != null) return _safeDate(y, mon, int.parse(m[2]!));
  }
  return null;
}

/// An amount with its sign: "₱1,250.50", "-250", "(250.00)", "250.00 DR", "PHP 99". Null if it is not an amount.
int? parseSignedCents(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;
  var negative = false;
  if (s.startsWith('(') && s.endsWith(')')) {
    negative = true;
    s = s.substring(1, s.length - 1);
  }
  final tail = RegExp(r'\s*(CR|DR)\.?$', caseSensitive: false).firstMatch(s);
  if (tail != null) {
    if (tail[1]!.toUpperCase() == 'DR') negative = true;
    s = s.substring(0, tail.start);
  }
  s = s.replaceAll(RegExp(r'PHP|Php|php|₱|\s'), '');
  if (s.startsWith('-') || s.startsWith('−')) {
    negative = true;
    s = s.substring(1);
  } else if (s.startsWith('+')) {
    s = s.substring(1);
  }
  if (s.endsWith('-')) {
    negative = true;
    s = s.substring(0, s.length - 1);
  }
  final cents = parseCents(s);
  if (cents == null) return null;
  return negative ? -cents : cents;
}

/// Which way money moved according to a "Type" cell, or null when it does not say.
bool? incomeFromType(String raw) {
  final words = raw.toLowerCase().split(RegExp(r'[^a-z]+')).where((w) => w.isNotEmpty).toSet();
  const out = {'debit', 'dr', 'out', 'withdrawal', 'withdraw', 'payment', 'purchase', 'sent', 'send', 'pay', 'paid', 'fee', 'charge', 'transfer'};
  const inn = {'credit', 'cr', 'in', 'deposit', 'received', 'receive', 'refund', 'cashin', 'interest'};
  final isOut = words.any(out.contains), isIn = words.any(inn.contains);
  if (isOut == isIn) return null;
  return isIn;
}

final _categoryRules = <(RegExp, String)>[
  (RegExp(r'jollibee|mcdo|mcdonald|kfc|starbucks|chowking|greenwich|mang inasal|foodpanda|grabfood|restaurant|resto|cafe|coffee|bakery|pizza|burger|milk tea|7[- ]?eleven|seven eleven|ministop|puregold|savemore|s&r|landers|supermarket|grocery|groceries|wet market'), 'food'),
  (RegExp(r'grab|angkas|joyride|move it|beep|lrt|mrt|taxi|uber|shell|petron|caltex|phoenix|seaoil|toll|easytrip|autosweep|parking|bus|jeep|fuel|gasoline|cebu pacific|airasia|philippine airlines'), 'transport'),
  (RegExp(r'meralco|maynilad|manila water|pldt|globe|smart|converge|sky cable|dito|netflix|spotify|youtube|icloud|google|electric|water bill|internet|load|insurance|sun life|philhealth|sss|pag-?ibig|rent|tuition|subscription'), 'bills'),
  (RegExp(r'mercury|watsons|rose pharmacy|southstar|drug|pharmacy|clinic|hospital|dental|dentist|medical|laboratory|optical'), 'health'),
  (RegExp(r'shopee|lazada|zalora|uniqlo|zara|h&m|national book|miniso|ikea|\bsm\b|robinsons|ayala|mall|department store|amazon|shein'), 'shopping'),
  (RegExp(r'steam|playstation|nintendo|xbox|cinema|movie|disney|hbo|concert|ticketnet|bar |resort|karaoke|arcade|timezone'), 'fun'),
];

/// A best guess at the category from the description; the user can change it before importing.
String guessCategory(String description, {required bool income}) {
  final d = description.toLowerCase();
  if (income) {
    if (RegExp(r'salary|payroll|wage|13th').hasMatch(d)) return 'salary';
    if (RegExp(r'allowance|sustento').hasMatch(d)) return 'allowance';
    if (RegExp(r'gift|regalo|ayuda').hasMatch(d)) return 'gift';
    return 'income_other';
  }
  for (final (re, id) in _categoryRules) {
    if (re.hasMatch(d)) return id;
  }
  return 'other';
}

/// Which columns hold what. Column numbers count from 0.
class ColumnMap {
  const ColumnMap({required this.date, required this.desc, required this.amount, this.moneyIn, this.type});
  final int date, desc;

  /// The amount, or "money out" when [moneyIn] is set.
  final int amount;
  final int? moneyIn, type;

  ColumnMap copyWith({int? date, int? desc, int? amount, int? Function()? moneyIn, int? Function()? type}) => ColumnMap(
        date: date ?? this.date,
        desc: desc ?? this.desc,
        amount: amount ?? this.amount,
        moneyIn: moneyIn != null ? moneyIn() : this.moneyIn,
        type: type != null ? type() : this.type,
      );
}

/// One transaction found in the file, ready to be shown and, if kept, added.
class ImportRow {
  ImportRow({required this.day, required this.note, required this.cents, required this.income, required this.category, this.duplicate = false}) : selected = !duplicate;
  final DateTime day;
  final String note;
  final int cents;
  final bool income;
  String category;

  /// The card already has a transaction with the same day, amount and direction.
  final bool duplicate;
  bool selected;
}

class StatementTable {
  StatementTable._(this.headers, this.body, this.hasHeader, this.guess);

  /// Header names (or "Column 1", "Column 2"… when the file has no header row).
  final List<String> headers;
  final List<List<String>> body;
  final bool hasHeader;

  /// Null when the columns could not be worked out; the user then picks them.
  final ColumnMap? guess;

  int get columns => headers.length;

  static StatementTable parse(String text) {
    final all = parseCsv(text);
    if (all.isEmpty) return StatementTable._(const [], const [], false, null);
    final width = all.take(60).fold<int>(0, (m, r) => r.length > m ? r.length : m);

    // The header is the first of the top rows that names a date and an amount (or money in/out).
    for (var i = 0; i < all.length && i < 25; i++) {
      final map = _guessFromHeader(all[i]);
      if (map != null) {
        final headers = [for (var c = 0; c < width; c++) c < all[i].length && all[i][c].isNotEmpty ? all[i][c] : 'Column ${c + 1}'];
        return StatementTable._(headers, all.sublist(i + 1), true, map);
      }
    }
    final headers = [for (var c = 0; c < width; c++) 'Column ${c + 1}'];
    return StatementTable._(headers, all, false, _guessFromContent(all, width));
  }

  static String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z ]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  static ColumnMap? _guessFromHeader(List<String> row) {
    final n = [for (final c in row) _norm(c)];
    int? find(bool Function(String) test) {
      for (var i = 0; i < n.length; i++) {
        if (n[i].isNotEmpty && test(n[i])) return i;
      }
      return null;
    }

    int? findPrefer(List<String> order) {
      for (final key in order) {
        final i = find((c) => c.contains(key));
        if (i != null) return i;
      }
      return null;
    }

    final date = findPrefer(['transaction date', 'trans date', 'posting date', 'posted', 'date', 'time']);
    final debit = find((c) => c == 'dr' || RegExp(r'debit|withdraw|money out|paid out|cash out|outgoing|expense|spent').hasMatch(c));
    final credit = find((c) => c == 'cr' || RegExp(r'credit|deposit|money in|paid in|cash in|incoming|income|received').hasMatch(c));
    final amount = find((c) => c == 'amount' || c == 'amt' || c.startsWith('amount') || c == 'php' || c == 'value');
    final type = find((c) => c == 'type' || c.contains('transaction type') || c == 'dr cr' || c.contains('direction'));
    final desc = findPrefer(['description', 'details', 'particulars', 'merchant', 'narration', 'remarks', 'transaction', 'reference', 'payee', 'name']);
    if (date == null) return null;

    final used = {date, ?debit, ?credit, ?amount, ?type};
    final descCol = desc != null && !used.contains(desc) ? desc : _firstUnused(n.length, used);
    if (descCol == null) return null;

    if (debit != null && credit != null) return ColumnMap(date: date, desc: descCol, amount: debit, moneyIn: credit);
    if (amount != null) return ColumnMap(date: date, desc: descCol, amount: amount, type: type);
    return null;
  }

  static int? _firstUnused(int width, Set<int> used) {
    for (var i = 0; i < width; i++) {
      if (!used.contains(i)) return i;
    }
    return null;
  }

  /// With no header row: the date column is the one that mostly parses as dates, the amount column the
  /// last one that mostly parses as amounts, the description the longest remaining text.
  static ColumnMap? _guessFromContent(List<List<String>> rows, int width) {
    final sample = rows.take(40).toList();
    if (sample.isEmpty) return null;
    double share(int col, bool Function(String) ok) => sample.where((r) => col < r.length && ok(r[col])).length / sample.length;
    int? date;
    final amounts = <int>[];
    for (var c = 0; c < width; c++) {
      if (date == null && share(c, (s) => parseStatementDate(s) != null) >= 0.7) {
        date = c;
      } else if (share(c, (s) => parseSignedCents(s) != null && RegExp(r'\d').hasMatch(s)) >= 0.7) {
        amounts.add(c);
      }
    }
    if (date == null || amounts.isEmpty) return null;
    final amount = amounts.last;
    int? desc;
    var best = -1.0;
    for (var c = 0; c < width; c++) {
      if (c == date || amounts.contains(c)) continue;
      final avg = sample.fold<int>(0, (s, r) => s + (c < r.length ? r[c].length : 0)) / sample.length;
      if (avg > best) {
        best = avg;
        desc = c;
      }
    }
    return desc == null ? null : ColumnMap(date: date, desc: desc, amount: amount);
  }

  /// The transactions in the file under [map]. [flip] swaps income and expense (some statements show
  /// purchases as positive numbers). Rows matching a transaction already in [existing] on the same card
  /// are marked as duplicates and start unticked.
  List<ImportRow> rows(ColumnMap map, {bool flip = false, Iterable<Txn> existing = const [], String? accountId}) {
    String cell(List<String> r, int? c) => c == null || c >= r.length ? '' : r[c];

    // 03/11/2026 is ambiguous; if any date in the column has a first number above 12 it is day first.
    var dayFirst = false;
    for (final r in body) {
      final m = RegExp(r'^(\d{1,2})[-/.](\d{1,2})[-/.]\d{2,4}').firstMatch(cell(r, map.date));
      if (m != null && int.parse(m[1]!) > 12) {
        dayFirst = true;
        break;
      }
    }

    final seen = <String, int>{};
    for (final t in existing) {
      if (accountId != null && t.accountId != accountId) continue;
      final k = '${dayKey(t.day)}|${t.cents}|${t.income}';
      seen[k] = (seen[k] ?? 0) + 1;
    }

    final out = <ImportRow>[];
    for (final r in body) {
      final day = parseStatementDate(cell(r, map.date), dayFirst: dayFirst);
      if (day == null) continue; // totals, balances and notes under the table

      bool income;
      int cents;
      if (map.moneyIn != null) {
        final inn = parseSignedCents(cell(r, map.moneyIn));
        final o = parseSignedCents(cell(r, map.amount));
        if (inn != null && inn != 0) {
          income = true;
          cents = inn.abs();
        } else if (o != null && o != 0) {
          income = false;
          cents = o.abs();
        } else {
          continue;
        }
      } else {
        final v = parseSignedCents(cell(r, map.amount));
        if (v == null || v == 0) continue;
        cents = v.abs();
        income = v > 0;
        if (map.type != null) income = incomeFromType(cell(r, map.type)) ?? income;
      }
      if (flip) income = !income;

      var note = cell(r, map.desc).replaceAll(RegExp(r'\s+'), ' ').trim();
      if (note.isEmpty && map.type != null) note = cell(r, map.type);
      if (note.length > 80) note = note.substring(0, 80);

      final key = '${dayKey(day)}|$cents|$income';
      final dup = (seen[key] ?? 0) > 0;
      if (dup) seen[key] = seen[key]! - 1;
      out.add(ImportRow(day: day, note: note, cents: cents, income: income, category: guessCategory(note, income: income), duplicate: dup));
    }
    return out;
  }
}
