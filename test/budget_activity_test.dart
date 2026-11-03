import 'package:faelen/core/theme.dart';
import 'package:faelen/features/budget/models/budget_models.dart';
import 'package:faelen/features/budget/screens/budget_screen.dart';
import 'package:faelen/features/budget/services/activity_filter.dart';
import 'package:faelen/features/budget/services/budget_repo.dart';
import 'package:faelen/features/budget/state/budget_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const _main = Account(id: 'a', name: 'Main', issuer: 'BDO');
const _wallet = Account(id: 'b', name: 'GCash wallet', issuer: 'GCash');
Account? _accountOf(String id) => {'a': _main, 'b': _wallet}[id];

Txn tx(String id, int cents, {String acc = 'a', bool income = false, String cat = 'food', DateTime? day, String note = '', String? pair}) =>
    Txn(id: id, accountId: acc, cents: cents, income: income, category: cat, day: day ?? DateTime(2026, 11, 10), note: note, createdAt: 1, pair: pair);

final _now = DateTime(2026, 11, 20);

List<String> ids(ActivityFilter f, List<Txn> all) => f.apply(all, accountOf: _accountOf, now: _now).map((t) => t.id).toList();

void main() {
  final all = [
    tx('lunch', 25050, note: 'Lunch with Ana', cat: 'food', day: DateTime(2026, 11, 18)),
    tx('grab', 18000, note: 'Grab to office', cat: 'transport', day: DateTime(2026, 11, 3)),
    tx('salary', 2500000, income: true, note: 'Salary', cat: 'salary', day: DateTime(2026, 10, 31)),
    tx('load', 10000, acc: 'b', note: 'Globe load', cat: 'bills', day: DateTime(2026, 10, 12)),
    tx('old', 99900, note: 'Shoes', cat: 'shopping', day: DateTime(2025, 3, 2)),
    tx('t1', 5000, acc: 'a', cat: 'transfer', note: 'To GCash wallet', pair: 'p', day: DateTime(2026, 11, 19)),
  ];

  group('search', () {
    test('finds words in the note, category, card and amount', () {
      expect(ids(const ActivityFilter(query: 'lunch'), all), ['lunch']);
      expect(ids(const ActivityFilter(query: 'ANA'), all), ['lunch']);
      expect(ids(const ActivityFilter(query: 'transport'), all), ['grab']);
      expect(ids(const ActivityFilter(query: 'gcash'), all), ['load', 't1']); // the card's bank, and the note
      expect(ids(const ActivityFilter(query: '250.50'), all), ['lunch']);
      expect(ids(const ActivityFilter(query: '₱250.50'), all), ['lunch']);
      expect(ids(const ActivityFilter(query: '25,000'), all), ['salary']);
    });

    test('every word has to match, in any order', () {
      expect(ids(const ActivityFilter(query: 'ana lunch'), all), ['lunch']);
      expect(ids(const ActivityFilter(query: 'lunch grab'), all), isEmpty);
    });

    test('blank search matches everything', () {
      expect(ids(const ActivityFilter(query: '   '), all).length, all.length);
    });
  });

  group('filters', () {
    test('expense and income', () {
      expect(ids(const ActivityFilter(flow: ActivityFlow.income), all), ['salary']);
      expect(ids(const ActivityFilter(flow: ActivityFlow.expense), all).contains('salary'), isFalse);
    });

    test('card and categories (several at once)', () {
      expect(ids(const ActivityFilter(accountId: 'b'), all), ['load']);
      expect(ids(const ActivityFilter(categories: {'food', 'transport'}), all), ['lunch', 'grab']);
      expect(ids(const ActivityFilter(categories: {'transfer'}), all), ['t1']);
    });

    test('periods', () {
      expect(ids(const ActivityFilter(period: ActivityPeriod.thisMonth), all), ['lunch', 'grab', 't1']);
      expect(ids(const ActivityFilter(period: ActivityPeriod.lastMonth), all), ['salary', 'load']);
      // Last 30 days from Nov 20 reaches back to Oct 22.
      expect(ids(const ActivityFilter(period: ActivityPeriod.last30), all), ['lunch', 'grab', 'salary', 't1']);
    });

    test('a custom range includes both end days', () {
      final f = ActivityFilter(period: ActivityPeriod.custom, from: DateTime(2026, 10, 12), to: DateTime(2026, 11, 3));
      expect(ids(f, all), ['grab', 'salary', 'load']);
      expect(ids(ActivityFilter(period: ActivityPeriod.custom, from: DateTime(2026, 11, 18)), all), ['lunch', 't1']);
      expect(ids(ActivityFilter(period: ActivityPeriod.custom, to: DateTime(2026, 10, 12)), all), ['load', 'old']);
    });

    test('last month works across a new year', () {
      final f = const ActivityFilter(period: ActivityPeriod.lastMonth).range(DateTime(2026, 1, 15));
      expect(f, (DateTime(2025, 12), DateTime(2025, 12, 31)));
    });

    test('filters combine', () {
      final f = const ActivityFilter(query: 'a', flow: ActivityFlow.expense, categories: {'food', 'transport', 'bills'}, accountId: 'a');
      expect(ids(f, all), ['lunch', 'grab']);
    });

    test('active and the sheet badge count', () {
      expect(const ActivityFilter().active, isFalse);
      expect(const ActivityFilter(query: 'x').active, isTrue);
      expect(const ActivityFilter(flow: ActivityFlow.income).active, isTrue);
      expect(const ActivityFilter(flow: ActivityFlow.income).sheetCount, 0);
      expect(const ActivityFilter(accountId: 'a', categories: {'food'}, period: ActivityPeriod.thisMonth).sheetCount, 3);
    });

    test('copyWith can clear the card', () {
      final f = const ActivityFilter(accountId: 'a').copyWith(accountId: () => null);
      expect(f.accountId, isNull);
    });
  });

  group('screen', () {
    Future<BudgetStore> pump(WidgetTester tester, {int count = 6, Size size = const Size(360, 740), Brightness b = Brightness.light}) async {
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final store = BudgetStore(MemoryBudgetRepo());
      await store.load();
      await store.saveAccount(_main);
      await store.saveAccount(_wallet);
      final today = DateTime.now();
      for (var i = 0; i < count; i++) {
        await store.saveTxn(tx('t$i', 10000 + i * 100, note: 'Item number $i', cat: i.isEven ? 'food' : 'transport', day: DateTime(today.year, today.month, 1)));
      }
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(theme: buildTheme(b), home: const BudgetScreen()),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Activity'));
      await tester.pumpAndSettle();
      return store;
    }

    testWidgets('typing in the search box narrows the list and shows a summary', (tester) async {
      await pump(tester);
      expect(find.text('Item number 3'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'number 3');
      await tester.pumpAndSettle();
      expect(find.text('Item number 3'), findsOneWidget);
      expect(find.text('Item number 2'), findsNothing);
      expect(find.textContaining('1 transaction'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(find.text('Item number 2'), findsOneWidget);
    });

    testWidgets('no match says so and offers to clear', (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), 'zzzzz');
      await tester.pumpAndSettle();
      expect(find.text('Nothing matches those filters.'), findsOneWidget);
      await tester.tap(find.text('Clear search and filters'));
      await tester.pumpAndSettle();
      expect(find.text('Item number 1'), findsOneWidget);
    });

    testWidgets('the filter sheet narrows by category and shows a badge', (tester) async {
      await pump(tester);
      await tester.tap(find.byIcon(Icons.tune_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Filter'), findsOneWidget);
      await tester.tap(find.text('Transport'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show results'));
      await tester.pumpAndSettle();
      expect(find.text('Item number 1'), findsOneWidget); // odd = transport
      expect(find.text('Item number 0'), findsNothing);
      expect(find.text('1'), findsOneWidget, reason: 'the badge says one filter is on');
      expect(find.textContaining('3 transactions'), findsOneWidget);
    });

    testWidgets('a long history still builds lazily (1,500 transactions)', (tester) async {
      final store = await pump(tester, count: 0);
      final d = DateTime.now();
      await store.addTxns([for (var i = 0; i < 1500; i++) tx('b$i', 100 + i, note: 'Bulk $i', day: DateTime(d.year, d.month, 1 + i % 27))]);
      await tester.pumpAndSettle();
      expect(find.byType(Dismissible).evaluate().length, lessThan(40), reason: 'only the rows on screen exist');
      await tester.enterText(find.byType(TextField), 'Bulk 1499');
      await tester.pumpAndSettle();
      expect(find.byType(Dismissible), findsOneWidget);
      expect(find.textContaining('1 transaction'), findsOneWidget);
    });

    for (final (name, size, b) in [('phone', const Size(360, 740), Brightness.light), ('small phone dark', const Size(320, 640), Brightness.dark)]) {
      testWidgets('search, flow pills and the filter sheet fit: $name', (tester) async {
        await pump(tester, size: size, b: b);
        await tester.tap(find.byIcon(Icons.tune_rounded));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Show results'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
