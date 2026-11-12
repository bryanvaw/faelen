import 'package:faelen/core/theme.dart';
import 'package:faelen/features/budget/models/budget_models.dart';
import 'package:faelen/features/budget/screens/budget_screen.dart';
import 'package:faelen/features/budget/services/budget_repo.dart';
import 'package:faelen/features/budget/state/budget_store.dart';
import 'package:faelen/features/media/models/media_entry.dart';
import 'package:faelen/features/media/services/cover_service.dart';
import 'package:faelen/features/media/services/storage_service.dart';
import 'package:faelen/features/media/state/media_store.dart';
import 'package:faelen/features/settings/backup_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Txn tx(String id, String acc, int cents, {bool income = false, String cat = 'food', DateTime? day}) =>
    Txn(id: id, accountId: acc, cents: cents, income: income, category: cat, day: day ?? dateOnly(DateTime.now()), createdAt: 1);

Future<BudgetStore> twoCards([BudgetRepo? repo]) async {
  final s = BudgetStore(repo ?? MemoryBudgetRepo());
  await s.load();
  await s.saveAccount(const Account(id: 'a', name: 'Main', openingCents: 100000));
  await s.saveAccount(const Account(id: 'b', name: 'Wallet'));
  return s;
}

void main() {
  group('transfers', () {
    test('move money between cards without counting it as income or spending', () async {
      final s = await twoCards();
      await s.transfer(from: 'a', to: 'b', cents: 30000);
      expect(s.balanceOf(s.account('a')!), 70000);
      expect(s.balanceOf(s.account('b')!), 30000);
      expect(s.totalBalance, 100000);
      final sum = s.summary();
      expect([sum.income, sum.expense], [0, 0]);
      expect(s.spending().every((r) => r.spent == 0), isTrue);
    });

    test('deleting one half removes both, and undo brings both back', () async {
      final s = await twoCards();
      await s.transfer(from: 'a', to: 'b', cents: 5000);
      final gone = await s.deleteTxn(s.txns.first.id);
      expect(gone.length, 2);
      expect(s.txns, isEmpty);
      expect(s.balanceOf(s.account('b')!), 0);
      await s.restoreTxns(gone);
      expect(s.balanceOf(s.account('b')!), 5000);
    });

    test('refuses same-card, zero and unknown-card transfers', () async {
      final s = await twoCards();
      await s.transfer(from: 'a', to: 'a', cents: 100);
      await s.transfer(from: 'a', to: 'b', cents: 0);
      await s.transfer(from: 'a', to: 'zzz', cents: 100);
      expect(s.txns, isEmpty);
    });

    test('deleting a card also removes the other half of its transfers', () async {
      final s = await twoCards();
      await s.transfer(from: 'a', to: 'b', cents: 5000);
      await s.deleteAccount('a');
      expect(s.txns, isEmpty);
      expect(s.balanceOf(s.account('b')!), 0);
    });
  });

  group('monthly bills', () {
    const bill = Bill(id: 'r', name: 'Rent', cents: 800000, category: 'bills', accountId: 'a', day: 5);

    test('a new bill is not back-filled; it posts on the next due day', () async {
      final s = await twoCards();
      await s.saveBill(bill, now: DateTime(2026, 11, 10)); // the 5th already passed this month
      expect(s.txns, isEmpty);
      expect(s.nextDue(s.bills.single, now: DateTime(2026, 11, 10)), DateTime(2026, 12, 5));
      await s.postDueBills(now: DateTime(2026, 12, 4));
      expect(s.txns, isEmpty);
      await s.postDueBills(now: DateTime(2026, 12, 5));
      expect(s.txns.single.day, DateTime(2026, 12, 5));
      expect(s.txns.single.note, 'Rent');
      expect(s.balanceOf(s.account('a')!), 100000 - 800000);
    });

    test('posting is idempotent and catches up on missed months', () async {
      final s = await twoCards();
      await s.saveBill(bill, now: DateTime(2026, 11, 1));
      await s.postDueBills(now: DateTime(2026, 11, 5));
      await s.postDueBills(now: DateTime(2026, 11, 5));
      await s.postDueBills(now: DateTime(2026, 11, 20));
      expect(s.txns.length, 1);
      await s.postDueBills(now: DateTime(2027, 2, 6)); // the app was closed for months
      expect(s.txns.map((t) => t.day).toSet(), {DateTime(2026, 11, 5), DateTime(2026, 12, 5), DateTime(2027, 1, 5), DateTime(2027, 2, 5)});
    });

    test('a bill due on the 31st falls on the last day of shorter months', () {
      expect(dueDate(2026, 2, 31), DateTime(2026, 2, 28));
      expect(dueDate(2028, 2, 31), DateTime(2028, 2, 29));
      expect(dueDate(2026, 4, 31), DateTime(2026, 4, 30));
      expect(dueDate(2026, 5, 31), DateTime(2026, 5, 31));
    });

    test('bill expenses count toward the month and its category', () async {
      final s = await twoCards();
      await s.saveBill(bill.copyWith(day: 1), now: DateTime.now().subtract(const Duration(days: 40)));
      await s.postDueBills();
      final sum = s.summary();
      expect(sum.expense, 800000);
      expect(s.spending().firstWhere((r) => r.category.id == 'bills').spent, 800000);
    });

    test('a bill whose card is deleted is removed with it', () async {
      final s = await twoCards();
      await s.saveBill(bill);
      await s.deleteAccount('a');
      expect(s.bills, isEmpty);
    });
  });

  group('goals', () {
    test('adding and taking out never goes below zero', () async {
      final s = await twoCards();
      await s.saveGoal(const Goal(id: 'g', name: 'Phone', targetCents: 2000000));
      await s.adjustGoal('g', 500000);
      await s.adjustGoal('g', -200000);
      expect(s.goals.single.savedCents, 300000);
      await s.adjustGoal('g', -999999999);
      expect(s.goals.single.savedCents, 0);
      expect(s.totalBalance, 100000); // a goal never touches a card
    });

    test('reached when saved passes the target', () {
      expect(const Goal(id: 'g', name: 'x', targetCents: 100, savedCents: 100).reached, isTrue);
      expect(const Goal(id: 'g', name: 'x', targetCents: 100, savedCents: 99).reached, isFalse);
    });
  });

  group('storage', () {
    setUpAll(sqfliteFfiInit);

    test('bills, goals and transfers survive a reload from SQLite', () async {
      final repo = SqliteBudgetRepo(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
      final s = await twoCards(repo);
      await s.saveBill(const Bill(id: 'r', name: 'Rent', cents: 100, category: 'bills', accountId: 'a', day: 3), now: DateTime(2026, 11, 10));
      await s.saveGoal(const Goal(id: 'g', name: 'Phone', targetCents: 5000, savedCents: 1000));
      await s.transfer(from: 'a', to: 'b', cents: 700);
      final again = BudgetStore(repo);
      await again.load();
      expect(again.bills.single.name, 'Rent');
      expect(again.goals.single.savedCents, 1000);
      expect(again.txns.where((t) => t.pair != null).length, 2);
      expect(again.balanceOf(again.account('b')!), 700);
      await repo.close();
    });
  });

  group('backup', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<MediaStore> media() async {
      final m = MediaStore(StorageService(), covers: CoverService.disabled());
      await m.load();
      return m;
    }

    test('budget goes into the backup and comes back on replace', () async {
      final s = await twoCards();
      await s.saveTxn(tx('1', 'a', 2500));
      await s.transfer(from: 'a', to: 'b', cents: 500);
      await s.setLimit('food', 9000);
      await s.saveGoal(const Goal(id: 'g', name: 'Trip', targetCents: 10000, savedCents: 400));
      final m = await media();
      await m.save(const MediaEntry(id: 'x', title: 'Show'));
      final json = await BackupService().build(m, budget: s, now: DateTime.utc(2026, 11, 3));
      expect(json, contains('"budget"'));

      final other = BudgetStore(MemoryBudgetRepo());
      await other.load();
      await other.saveAccount(const Account(id: 'old', name: 'Old'));
      final r = await BackupService().restore(json, await media(), budget: other, replace: true);
      expect([r.cards, r.transactions], [2, 3]);
      expect(other.accounts.map((a) => a.id).toSet(), {'a', 'b'});
      expect(other.balanceOf(other.account('a')!), 100000 - 2500 - 500);
      expect(other.limits['food'], 9000);
      expect(other.goals.single.name, 'Trip');
    });

    test('merge keeps what is already there', () async {
      final s = await twoCards();
      await s.saveTxn(tx('1', 'a', 2500));
      final json = await BackupService().build(await media(), budget: s);
      final other = BudgetStore(MemoryBudgetRepo());
      await other.load();
      await other.saveAccount(const Account(id: 'mine', name: 'Mine'));
      await other.saveTxn(tx('own', 'mine', 100));
      await BackupService().restore(json, await media(), budget: other, replace: false);
      expect(other.accounts.length, 3);
      expect(other.txns.map((t) => t.id).toSet(), {'1', 'own'});
    });

    test('an old backup without budget leaves the budget alone', () async {
      final s = await twoCards();
      const old = '{"app":"faelen","version":1,"media":[]}';
      final r = await BackupService().restore(old, await media(), budget: s, replace: true);
      expect(r.cards, 0);
      expect(s.accounts.length, 2);
    });

    test('damaged budget rows are skipped; orphan transactions are dropped', () async {
      final other = BudgetStore(MemoryBudgetRepo());
      await other.load();
      await other.importData({
        'accounts': [
          {'id': 'a', 'name': 'Ok'},
          {'nope': 1},
          5,
        ],
        'txns': [
          tx('1', 'a', 100).toJson(),
          tx('2', 'ghost', 100).toJson(),
          {'id': 'bad'},
        ],
        'limits': {'food': 500, 'x': -1, 'y': 'z'},
        'bills': [
          {'id': 'b', 'name': 'B', 'cents': 5, 'account': 'a', 'day': 40},
        ],
      }, replace: true);
      expect(other.accounts.length, 1);
      expect(other.txns.map((t) => t.id), ['1']);
      expect(other.limits, {'food': 500});
      expect(other.bills, isEmpty);
    });

    test('a budget section that is not a map is refused and nothing changes', () async {
      final s = await twoCards();
      await expectLater(s.importData([1, 2], replace: true), throwsFormatException);
      expect(s.accounts.length, 2);
    });
  });

  group('screen', () {
    Future<BudgetStore> pump(WidgetTester tester, {Size size = const Size(360, 740), Brightness b = Brightness.light, double text = 1}) async {
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final store = await twoCards();
      await store.saveBill(const Bill(id: 'r', name: 'Rent and utilities', cents: 1250000, category: 'bills', accountId: 'a', day: 31), now: DateTime.now());
      await store.saveGoal(const Goal(id: 'g', name: 'New phone', targetCents: 3000000, savedCents: 1200000));
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

    for (final (name, size, b, text) in [
      ('phone', const Size(360, 740), Brightness.light, 1.0),
      ('small phone, large text, dark', const Size(320, 640), Brightness.dark, 1.4),
    ]) {
      testWidgets('cards tab with four actions and the plans tab fit: $name', (tester) async {
        await pump(tester, size: size, b: b, text: text);
        expect(find.text('Move'), findsOneWidget);
        await tester.tap(find.byTooltip('Plans'));
        await tester.pumpAndSettle();
        expect(find.text('Monthly bills'), findsOneWidget);
        expect(find.text('Rent and utilities'), findsOneWidget);
        expect(find.text('Subscriptions'), findsOneWidget);
        // Goals sit below Subscriptions; on a small phone with large text they are a scroll away.
        await tester.scrollUntilVisible(find.text('40%'), 200, scrollable: find.byType(Scrollable).first);
        expect(find.text('Savings goals'), findsOneWidget);
        expect(find.text('New phone'), findsOneWidget);
        expect(find.text('40%'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('moving money from the Cards tab updates both balances', (tester) async {
      final store = await pump(tester);
      await tester.tap(find.text('Move'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '250');
      await tester.tap(find.text('Move money').last);
      await tester.pumpAndSettle();
      expect(store.balanceOf(store.account('b')!), 25000);
      expect(store.balanceOf(store.account('a')!), 100000 - 25000);
    });

    testWidgets('adding money to a goal', (tester) async {
      final store = await pump(tester);
      await tester.tap(find.byTooltip('Plans'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add money'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '500');
      await tester.tap(find.text('Add money').last);
      await tester.pumpAndSettle();
      expect(store.goals.single.savedCents, 1250000);
    });

    testWidgets('taking out more than is saved is refused', (tester) async {
      final store = await pump(tester);
      await tester.tap(find.byTooltip('Plans'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Take out'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '999999');
      await tester.tap(find.text('Take out').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('is saved'), findsOneWidget);
      expect(store.goals.single.savedCents, 1200000);
    });
  });
}
