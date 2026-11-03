import '../models/budget_models.dart';

enum ActivityFlow { all, expense, income }

enum ActivityPeriod {
  all('All time'),
  thisMonth('This month'),
  lastMonth('Last month'),
  last30('Last 30 days'),
  custom('Pick dates');

  const ActivityPeriod(this.label);
  final String label;
}

/// What the Activity list is narrowed to: a search, expense/income, a card, categories and a period.
/// Pure data, so the rules can be tested without a screen.
class ActivityFilter {
  const ActivityFilter({
    this.query = '',
    this.flow = ActivityFlow.all,
    this.accountId,
    this.categories = const {},
    this.period = ActivityPeriod.all,
    this.from,
    this.to,
  });

  final String query;
  final ActivityFlow flow;
  final String? accountId;

  /// Category ids; empty means every category.
  final Set<String> categories;
  final ActivityPeriod period;

  /// Only used when [period] is custom (both ends included).
  final DateTime? from, to;

  /// How many of the choices in the filter sheet are on (the search and expense/income pills show for themselves).
  int get sheetCount => (accountId != null ? 1 : 0) + (categories.isNotEmpty ? 1 : 0) + (period != ActivityPeriod.all ? 1 : 0);

  bool get active => query.trim().isNotEmpty || flow != ActivityFlow.all || sheetCount > 0;

  ActivityFilter copyWith({
    String? query,
    ActivityFlow? flow,
    String? Function()? accountId,
    Set<String>? categories,
    ActivityPeriod? period,
    DateTime? from,
    DateTime? to,
  }) =>
      ActivityFilter(
        query: query ?? this.query,
        flow: flow ?? this.flow,
        accountId: accountId != null ? accountId() : this.accountId,
        categories: categories ?? this.categories,
        period: period ?? this.period,
        from: from ?? this.from,
        to: to ?? this.to,
      );

  /// The first and last day of [period] (null = no limit on that side).
  (DateTime?, DateTime?) range(DateTime now) {
    final today = dateOnly(now);
    switch (period) {
      case ActivityPeriod.all:
        return (null, null);
      case ActivityPeriod.thisMonth:
        return (DateTime(today.year, today.month), DateTime(today.year, today.month + 1, 0));
      case ActivityPeriod.lastMonth:
        return (DateTime(today.year, today.month - 1), DateTime(today.year, today.month, 0));
      case ActivityPeriod.last30:
        return (today.subtract(const Duration(days: 29)), today);
      case ActivityPeriod.custom:
        return (from == null ? null : dateOnly(from!), to == null ? null : dateOnly(to!));
    }
  }

  /// Every word typed has to be found in the note, the category, the card, or the amount.
  bool matches(Txn t, {required Account? Function(String id) accountOf, DateTime? now}) {
    if (flow == ActivityFlow.expense && t.income) return false;
    if (flow == ActivityFlow.income && !t.income) return false;
    if (accountId != null && t.accountId != accountId) return false;
    if (categories.isNotEmpty && !categories.contains(t.category)) return false;

    final (lo, hi) = range(now ?? DateTime.now());
    if (lo != null && t.day.isBefore(lo)) return false;
    if (hi != null && t.day.isAfter(hi)) return false;

    final words = query.toLowerCase().split(RegExp(r'\s+')).map((w) => w.replaceAll(RegExp(r'[₱,]'), '')).where((w) => w.isNotEmpty);
    if (words.isEmpty) return true;
    final a = accountOf(t.accountId);
    final hay = [t.note, categoryById(t.category).label, if (a != null) ...[a.name, a.issuer], centsToField(t.cents), peso(t.cents)].join(' ').toLowerCase().replaceAll(',', '');
    return words.every(hay.contains);
  }

  List<Txn> apply(Iterable<Txn> all, {required Account? Function(String id) accountOf, DateTime? now}) =>
      [for (final t in all) if (matches(t, accountOf: accountOf, now: now)) t];
}

/// A short, plain description of the dates, for the filter chip and the summary line.
String periodLabel(ActivityFilter f, String Function(DateTime) fmt) {
  if (f.period != ActivityPeriod.custom) return f.period.label;
  if (f.from == null && f.to == null) return 'Pick dates';
  if (f.from != null && f.to != null) return '${fmt(f.from!)} to ${fmt(f.to!)}';
  return f.from != null ? 'From ${fmt(f.from!)}' : 'Until ${fmt(f.to!)}';
}
