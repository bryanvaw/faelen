import 'package:faelen/core/theme.dart';
import 'package:faelen/features/budget/models/budget_models.dart';
import 'package:faelen/features/budget/screens/budget_screen.dart';
import 'package:faelen/features/budget/services/budget_repo.dart';
import 'package:faelen/features/budget/state/budget_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Txn tx(String id, String acc, int cents, {bool income = false, String cat = 'food', DateTime? day, String note = ''}) =>
    Txn(id: id, accountId: acc, cents: cents, income: income, category: cat, day: day ?? dateOnly(DateTime.now()), note: note, createdAt: 1);

void main() {
  group('money', () {
    test('peso formats centavos with grouping and sign', () {
      expect(peso(0), '₱0.00');
      expect(peso(123456789), '₱1,234,567.89');
      expect(peso(-5050), '-₱50.50');
      expect(peso(250000, compact: true), '₱2,500');
      expect(peso(250050, compact: true), '₱2,500.50');
      expect(peso(1000, sign: true), '+₱10.00');
    });

    test('parseCents is exact and strict', () {
      expect(parseCents('250'), 25000);
      expect(parseCents('250.5'), 25050);
      expect(parseCents('1,250.75'), 125075);
      expect(parseCents('0.07'), 7);
      expect(parseCents('19.99'), 1999);
      expect(parseCents(''), isNull);
      expect(parseCents('abc'), isNull);
      expect(parseCents('1.234'), isNull);
      expect(parseCents('-5'), isNull);
    });

    test('centsToField round trips', () {
      expect(centsToField(25000), '250');
      expect(centsToField(25050), '250.50');
      expect(parseCents(centsToField(7)), 7);
    });
  });

  group('models', () {
    test('account and transaction JSON round trip; bad rows are rejected', () {
      const a = Account(id: 'a', name: 'Everyday', issuer: 'BDO', kind: CardKind.credit, network: CardNetwork.visa, last4: '1234', skin: 2, openingCents: -5000);
      final back = Account.fromJson(a.toJson())!;
      expect([back.name, back.issuer, back.kind, back.network, back.last4, back.skin, back.openingCents], ['Everyday', 'BDO', CardKind.credit, CardNetwork.visa, '1234', 2, -5000]);
      expect(Account.fromJson({'id': '', 'name': 'x'}), isNull);
      expect(Account.fromJson({'id': 'a', 'name': 'x', 'last4': '12ab3456789'})!.last4, '1234');
      expect(Account.fromJson({'id': 'a', 'name': 'x', 'skin': 99})!.skin, 0);

      final t = tx('t', 'a', 1234, note: 'Lunch', day: DateTime(2026, 11, 3));
      expect(Txn.fromJson(t.toJson())!.day, DateTime(2026, 11, 3));
      expect(Txn.fromJson({...t.toJson(), 'cents': 0}), isNull);
      expect(Txn.fromJson({...t.toJson(), 'day': 20261399}), isNull);
    });
  });

  group('store', () {
    Future<BudgetStore> build() async {
      final s = BudgetStore(MemoryBudgetRepo());
      await s.load();
      await s.saveAccount(const Account(id: 'a', name: 'Main', openingCents: 100000));
      await s.saveAccount(const Account(id: 'b', name: 'Wallet'));
      return s;
    }

    test('balance is opening plus income minus expenses, per card', () async {
      final s = await build();
      await s.saveTxn(tx('1', 'a', 25050));
      await s.saveTxn(tx('2', 'a', 50000, income: true, cat: 'salary'));
      await s.saveTxn(tx('3', 'b', 1000));
      expect(s.balanceOf(s.account('a')!), 100000 - 25050 + 50000);
      expect(s.balanceOf(s.account('b')!), -1000);
      expect(s.totalBalance, 100000 - 25050 + 50000 - 1000);
    });

    test('editing and deleting a transaction changes the balance; undo restores it', () async {
      final s = await build();
      final t = tx('1', 'a', 20000);
      await s.saveTxn(t);
      await s.saveTxn(t.copyWith(cents: 5000));
      expect(s.balanceOf(s.account('a')!), 95000);
      await s.deleteTxn('1');
      expect(s.balanceOf(s.account('a')!), 100000);
      await s.saveTxn(t);
      expect(s.balanceOf(s.account('a')!), 80000);
    });

    test('deleting a card removes its transactions and can be undone', () async {
      final s = await build();
      await s.saveTxn(tx('1', 'a', 100));
      await s.saveTxn(tx('2', 'b', 200));
      final gone = (await s.deleteAccount('a'))!;
      expect(s.accounts.map((a) => a.id), ['b']);
      expect(s.txns.map((t) => t.id), ['2']);
      await s.restoreAccount(gone.account, gone.txns);
      expect(s.accounts.length, 2);
      expect(s.txns.length, 2);
    });

    test('month summary and category spend only count the chosen month', () async {
      final s = await build();
      final now = DateTime.now();
      final thisMonth = DateTime(now.year, now.month, 1);
      final lastMonth = DateTime(now.year, now.month - 1, 15);
      await s.saveTxn(tx('1', 'a', 30000, cat: 'food', day: thisMonth));
      await s.saveTxn(tx('2', 'a', 10000, cat: 'transport', day: thisMonth));
      await s.saveTxn(tx('3', 'a', 99999, cat: 'food', day: lastMonth));
      await s.saveTxn(tx('4', 'a', 70000, income: true, cat: 'salary', day: thisMonth));
      final sum = s.summary();
      expect([sum.income, sum.expense, sum.net], [70000, 40000, 30000]);
      expect(s.summary(accountId: 'b').expense, 0);
      final food = s.spending().firstWhere((r) => r.category.id == 'food');
      expect(food.spent, 30000);
      s.shiftMonth(-1);
      expect(s.spending().firstWhere((r) => r.category.id == 'food').spent, 99999);
      expect(s.isCurrentMonth, isFalse);
    });

    test('limits flag over-budget categories and 0 removes a limit', () async {
      final s = await build();
      await s.saveTxn(tx('1', 'a', 30000, cat: 'food'));
      await s.setLimit('food', 20000);
      var food = s.spending().firstWhere((r) => r.category.id == 'food');
      expect(food.over, isTrue);
      expect(s.totalLimit, 20000);
      await s.setLimit('food', 0);
      food = s.spending().firstWhere((r) => r.category.id == 'food');
      expect(food.over, isFalse);
      expect(s.limits, isEmpty);
    });

    test('transactions are listed newest first', () async {
      final s = await build();
      await s.saveTxn(tx('old', 'a', 1, day: DateTime(2026, 1, 1)));
      await s.saveTxn(tx('new', 'a', 1, day: DateTime(2026, 6, 1)));
      expect(s.recent().map((t) => t.id), ['new', 'old']);
      expect(s.recent(limit: 1).length, 1);
    });
  });

  group('sqlite', () {
    setUpAll(sqfliteFfiInit);

    test('records are stored, changed and removed', () async {
      final repo = SqliteBudgetRepo(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
      await repo.putAccount(const Account(id: 'a', name: 'Main', openingCents: 5));
      await repo.putTxn(tx('1', 'a', 1250, note: 'Lunch'));
      await repo.putTxn(tx('2', 'a', 99));
      await repo.setLimit('food', 50000);
      await repo.deleteTxn('2');
      final d = await repo.load();
      expect(d.accounts.single.name, 'Main');
      expect(d.txns.single.note, 'Lunch');
      expect(d.limits, {'food': 50000});
      await repo.setLimit('food', 0);
      expect((await repo.load()).limits, isEmpty);
      await repo.deleteAccount('a');
      final after = await repo.load();
      expect(after.accounts, isEmpty);
      expect(after.txns, isEmpty);
      await repo.close();
    });
  });

  group('screen', () {
    Future<BudgetStore> pump(WidgetTester tester, {bool seed = true, Size size = const Size(360, 740), Brightness b = Brightness.light, double text = 1}) async {
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final store = BudgetStore(MemoryBudgetRepo());
      await store.load();
      if (seed) {
        await store.saveAccount(const Account(id: 'a', name: 'Everyday', issuer: 'BDO', kind: CardKind.debit, network: CardNetwork.mastercard, last4: '4821', skin: 1, openingCents: 1234567));
        await store.saveAccount(const Account(id: 'b', name: 'GCash', issuer: 'GCash', kind: CardKind.ewallet, skin: 4));
        await store.saveTxn(tx('1', 'a', 35000, note: 'Lunch with Ana'));
        await store.saveTxn(tx('2', 'a', 1500000, income: true, cat: 'salary', note: 'Salary'));
        await store.saveTxn(tx('3', 'b', 12000, cat: 'transport', day: dateOnly(DateTime.now()).subtract(const Duration(days: 1))));
        await store.setLimit('food', 30000);
      }
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(
          theme: buildTheme(b),
          builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(text)), child: child!),
          home: const BudgetScreen(),
        ),
      ));
      await tester.pumpAndSettle();
      return store;
    }

    testWidgets('first run asks for a card, and adding one works', (tester) async {
      await pump(tester, seed: false);
      expect(find.text('Add your first card'), findsOneWidget);
      await tester.tap(find.text('Add a card'));
      await tester.pumpAndSettle();
      expect(find.text('New card'), findsOneWidget);
      await tester.tap(find.text('Add card'));
      await tester.pumpAndSettle();
      expect(find.text('Add your first card'), findsNothing);
    });

    for (final (name, size, b, text) in [
      ('phone light', const Size(360, 740), Brightness.light, 1.0),
      ('small phone dark large text', const Size(320, 640), Brightness.dark, 1.4),
      ('tablet', const Size(900, 700), Brightness.light, 1.0),
    ]) {
      testWidgets('all three tabs fit without overflow: $name', (tester) async {
        await pump(tester, size: size, b: b, text: text);
        expect(find.text('Total across 2 cards'), findsOneWidget);
        await tester.tap(find.byTooltip('Activity'));
        await tester.pumpAndSettle();
        expect(find.text('Yesterday'), findsOneWidget);
        expect(find.text('Lunch with Ana'), findsOneWidget);
        await tester.tap(find.byTooltip('Budgets'));
        await tester.pumpAndSettle();
        expect(find.text('By category'), findsOneWidget);
        expect(find.textContaining('over the limit'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('adding an expense updates the card balance', (tester) async {
      final store = await pump(tester);
      final before = store.balanceOf(store.account('a')!);
      await tester.tap(find.text('Expense'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '100.50');
      await tester.tap(find.text('Add expense'));
      await tester.pumpAndSettle();
      expect(store.balanceOf(store.account('a')!), before - 10050);
    });

    testWidgets('an empty or zero amount is refused', (tester) async {
      final store = await pump(tester);
      final n = store.txns.length;
      await tester.tap(find.text('Expense'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add expense'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Enter an amount'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).first, '0');
      await tester.tap(find.text('Add expense'));
      await tester.pumpAndSettle();
      expect(find.textContaining('more than zero'), findsOneWidget);
      expect(store.txns.length, n);
    });

    testWidgets('hide balances masks the amounts', (tester) async {
      await pump(tester);
      expect(find.textContaining('₱26,875'), findsWidgets);
      await tester.tap(find.byIcon(Icons.visibility_rounded));
      await tester.pumpAndSettle();
      expect(find.textContaining('••••'), findsWidgets);
    });
  });
}
