import 'package:faelen/core/theme.dart';
import 'package:faelen/features/budget/models/budget_models.dart';
import 'package:faelen/features/budget/screens/budget_screen.dart';
import 'package:faelen/features/budget/services/budget_repo.dart';
import 'package:faelen/features/budget/services/subscription_reminders.dart';
import 'package:faelen/features/budget/state/budget_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<BudgetStore> cards([BudgetRepo? repo]) async {
  final s = BudgetStore(repo ?? MemoryBudgetRepo());
  await s.load();
  await s.saveAccount(const Account(id: 'a', name: 'Main', openingCents: 1000000));
  await s.saveAccount(const Account(id: 'b', name: 'Wallet'));
  return s;
}

Subscription sub(String id, DateTime next, {int cents = 54900, BillingCycle cycle = BillingCycle.monthly, bool trial = false, SubStatus status = SubStatus.active, String account = 'a', int remind = 1, String link = ''}) =>
    Subscription(id: id, name: 'Netflix $id', cents: cents, accountId: account, next: next, cycle: cycle, trial: trial, status: status, remindDays: remind, link: link);

void main() {
  final today = DateTime(2026, 11, 12);

  group('renewal dates', () {
    test('each cycle moves on by its own length', () {
      expect(sub('w', DateTime(2026, 11, 12), cycle: BillingCycle.weekly).after(DateTime(2026, 11, 12)), DateTime(2026, 11, 19));
      expect(sub('m', DateTime(2026, 11, 12)).after(DateTime(2026, 11, 12)), DateTime(2026, 12, 12));
      expect(sub('q', DateTime(2026, 11, 12), cycle: BillingCycle.quarterly).after(DateTime(2026, 11, 12)), DateTime(2027, 2, 12));
      expect(sub('y', DateTime(2026, 11, 12), cycle: BillingCycle.yearly).after(DateTime(2026, 11, 12)), DateTime(2027, 11, 12));
    });

    test('a charge on the 31st falls on the last day of a short month and goes back to the 31st', () {
      final s = sub('m', DateTime(2026, 1, 31));
      final feb = s.after(DateTime(2026, 1, 31));
      expect(feb, DateTime(2026, 2, 28));
      expect(s.after(feb), DateTime(2026, 3, 31));
    });

    test('a leap-day yearly charge survives a year without a 29th', () {
      final s = sub('y', DateTime(2028, 2, 29), cycle: BillingCycle.yearly);
      expect(s.after(DateTime(2028, 2, 29)), DateTime(2029, 2, 28));
    });

    test('cycles convert to a monthly and yearly cost', () {
      expect(sub('m', today).monthlyCents, 54900);
      expect(sub('y', today, cents: 120000, cycle: BillingCycle.yearly).monthlyCents, 10000);
      expect(sub('q', today, cents: 30000, cycle: BillingCycle.quarterly).monthlyCents, 10000);
      expect(sub('w', today, cents: 10000, cycle: BillingCycle.weekly).yearlyCents, 520000);
    });
  });

  group('posting charges', () {
    test('adds the expense on the renewal date and moves to the next one', () async {
      final s = await cards();
      await s.saveSubscription(sub('n', today), now: today);
      expect(s.txns.single.cents, 54900);
      expect(s.txns.single.day, today);
      expect(s.txns.single.note, 'Netflix n');
      expect(s.subscriptions.single.next, DateTime(2026, 12, 12));
      expect(s.balanceOf(s.account('a')!), 1000000 - 54900);
    });

    test('is not added twice when run again', () async {
      final s = await cards();
      await s.saveSubscription(sub('n', today), now: today);
      await s.postDueSubscriptions(now: today);
      await s.postDueSubscriptions(now: today);
      expect(s.txns.length, 1);
    });

    test('a new subscription is not back-filled for dates before it was added', () async {
      final s = await cards();
      await s.saveSubscription(sub('n', DateTime(2026, 8, 5)), now: today);
      expect(s.txns, isEmpty);
      expect(s.subscriptions.single.next, DateTime(2026, 12, 5));
    });

    test('catches up charges missed while the app was closed', () async {
      final s = await cards();
      await s.saveSubscription(sub('n', DateTime(2026, 12, 20)), now: today);
      await s.postDueSubscriptions(now: DateTime(2027, 3, 1));
      expect(s.txns.map((t) => t.day).toSet(), {DateTime(2026, 12, 20), DateTime(2027, 1, 20), DateTime(2027, 2, 20)});
      expect(s.subscriptions.single.next, DateTime(2027, 3, 20));
    });

    test('a paused or cancelled subscription adds nothing, and resuming does not back-fill', () async {
      final s = await cards();
      await s.saveSubscription(sub('p', DateTime(2026, 12, 1), status: SubStatus.paused), now: today);
      await s.saveSubscription(sub('c', DateTime(2026, 12, 1), status: SubStatus.cancelled), now: today);
      await s.postDueSubscriptions(now: DateTime(2027, 1, 15));
      expect(s.txns, isEmpty);
      await s.saveSubscription(s.subscriptions.firstWhere((x) => x.id == 'p').copyWith(status: SubStatus.active), now: DateTime(2027, 1, 15));
      expect(s.txns, isEmpty, reason: 'the months it was paused are not charged');
      expect(s.subscriptions.firstWhere((x) => x.id == 'p').next, DateTime(2027, 2, 1));
    });

    test('a free trial charges on its first date and is no longer a trial after it', () async {
      final s = await cards();
      await s.saveSubscription(sub('t', DateTime(2026, 11, 20), trial: true), now: today);
      expect(s.subscriptionsMonthly, 0, reason: 'a trial is not counted yet');
      expect(s.txns, isEmpty);
      await s.postDueSubscriptions(now: DateTime(2026, 11, 20));
      expect(s.txns.length, 1);
      expect(s.subscriptions.single.trial, isFalse);
      expect(s.subscriptionsMonthly, 54900);
    });

    test('totals count only active ones and cancelled ones show what is saved', () async {
      final s = await cards();
      await s.saveSubscription(sub('a1', DateTime(2026, 12, 1)), now: today);
      await s.saveSubscription(sub('y1', DateTime(2026, 12, 1), cents: 120000, cycle: BillingCycle.yearly), now: today);
      await s.saveSubscription(sub('c1', DateTime(2026, 12, 1), status: SubStatus.cancelled), now: today);
      expect(s.subscriptionsMonthly, 54900 + 10000);
      expect(s.subscriptionsYearly, 54900 * 12 + 120000);
      expect(s.subscriptionsSavedYearly, 54900 * 12);
    });

    test('deleting a card removes its subscriptions and Undo brings them back', () async {
      final s = await cards();
      await s.saveSubscription(sub('n', DateTime(2026, 12, 1), account: 'b'), now: today);
      final gone = await s.deleteAccount('b');
      expect(s.subscriptions, isEmpty);
      await s.restoreAccount(gone!.account, gone.txns, bills: gone.bills, subs: gone.subs);
      expect(s.subscriptions.length, 1);
    });

    test('delete and Undo', () async {
      final s = await cards();
      await s.saveSubscription(sub('n', DateTime(2026, 12, 1)), now: today);
      final gone = await s.deleteSubscription('n');
      expect(s.subscriptions, isEmpty);
      await s.saveSubscription(gone!, now: today);
      expect(s.subscriptions.single.id, 'n');
    });
  });

  group('storage and backup', () {
    test('SQLite keeps subscriptions across a reload', () async {
      sqfliteFfiInit();
      final repo = SqliteBudgetRepo(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
      final s = await cards(repo);
      await s.saveSubscription(sub('n', DateTime(2026, 12, 1), link: 'https://example.com/cancel'), now: today);
      final again = BudgetStore(repo);
      await again.load();
      expect(again.subscriptions.single.name, 'Netflix n');
      expect(again.subscriptions.single.link, 'https://example.com/cancel');
      await repo.close();
    });

    test('export and import round-trip, and old backups without subscriptions still load', () async {
      final s = await cards();
      await s.saveSubscription(sub('n', DateTime(2026, 12, 1), cycle: BillingCycle.yearly, trial: true), now: today);
      final out = s.exportData();
      final t = BudgetStore(MemoryBudgetRepo());
      await t.load();
      await t.importData(out, replace: true);
      expect(t.subscriptions.single.cycle, BillingCycle.yearly);
      expect(t.subscriptions.single.trial, isTrue);
      final old = Map<String, Object?>.of(out)..remove('subscriptions');
      await t.importData(old, replace: false);
      expect(t.subscriptions.length, 1);
    });

    test('damaged rows, unknown cards and non-web links are dropped', () {
      expect(Subscription.fromJson({'id': 'x', 'name': 'N', 'cents': 0, 'account': 'a', 'next': 20261201}), isNull);
      expect(Subscription.fromJson({'id': 'x', 'name': 'N', 'cents': 5, 'account': 'a', 'next': 20261399}), isNull);
      final s = Subscription.fromJson({'id': 'x', 'name': 'N', 'cents': 5, 'account': 'a', 'next': 20261201, 'link': 'javascript:alert(1)', 'cycle': 'nonsense'})!;
      expect(s.link, isEmpty);
      expect(s.cycle, BillingCycle.monthly);
    });

    test('a subscription whose card is not in the backup is skipped', () async {
      final s = await cards();
      final raw = {
        'accounts': [const Account(id: 'a', name: 'Main').toJson()],
        'subscriptions': [sub('ok', DateTime(2026, 12, 1)).toJson(), sub('lost', DateTime(2026, 12, 1), account: 'zzz').toJson()],
      };
      await s.importData(raw, replace: true);
      expect(s.subscriptions.map((x) => x.id), ['ok']);
    });
  });

  group('reminders', () {
    test('one reminder at 9:00 the chosen number of days before the charge', () {
      final r = SubscriptionReminders.plan([sub('n', DateTime(2026, 11, 20), remind: 3)], today);
      expect(r.single.when, DateTime(2026, 11, 17, 9));
      expect(r.single.title, 'Netflix n renews in 3 days');
      expect(r.single.body, '₱549 will be charged.');
    });

    test('a free trial warns that it ends and how to avoid paying', () {
      final r = SubscriptionReminders.plan([sub('n', DateTime(2026, 11, 20), trial: true)], today);
      expect(r.single.title, 'Netflix n trial ends tomorrow');
      expect(r.single.body, contains('Cancel before then'));
    });

    test('nothing for paused, cancelled, no-reminder or already-passed ones', () {
      final r = SubscriptionReminders.plan([
        sub('p', DateTime(2026, 11, 20), status: SubStatus.paused),
        sub('c', DateTime(2026, 11, 20), status: SubStatus.cancelled),
        sub('z', DateTime(2026, 11, 20), remind: 0),
        sub('late', DateTime(2026, 11, 12)),
      ], today);
      expect(r, isEmpty);
    });
  });

  group('screen', () {
    Future<BudgetStore> pump(WidgetTester tester, {Size size = const Size(360, 740), Brightness b = Brightness.light, double text = 1}) async {
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final store = await cards();
      final now = DateTime.now();
      final d = DateTime(now.year, now.month, now.day);
      await store.saveSubscription(sub('a', d.add(const Duration(days: 2)), link: 'https://example.com/cancel'));
      await store.saveSubscription(sub('b', d.add(const Duration(days: 20)), cents: 120000, cycle: BillingCycle.yearly, account: 'b'));
      await store.saveSubscription(sub('t', d.add(const Duration(days: 5)), trial: true));
      await store.saveSubscription(sub('c', d.add(const Duration(days: 9)), status: SubStatus.cancelled));
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(
          theme: buildTheme(b),
          builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(text)), child: child!),
          home: const BudgetScreen(),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Plans'));
      await tester.pumpAndSettle();
      return store;
    }

    for (final (name, size, b, text) in [
      ('phone', const Size(360, 740), Brightness.light, 1.0),
      ('small phone, large text, dark', const Size(320, 640), Brightness.dark, 1.4),
    ]) {
      testWidgets('the Subscriptions section fits: $name', (tester) async {
        await pump(tester, size: size, b: b, text: text);
        await tester.scrollUntilVisible(find.text('Subscriptions'), 200, scrollable: find.byType(Scrollable).first);
        expect(find.text('Subscriptions'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('Netflix a'), 100, scrollable: find.byType(Scrollable).first);
        expect(find.text('Renews in 2 days'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('shows totals, the trial, and what cancelling saved', (tester) async {
      await pump(tester);
      await tester.scrollUntilVisible(find.text('Netflix a'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.textContaining('a month'), findsWidgets);
      expect(find.text('Trial ends in 5 days'), findsOneWidget);
      expect(find.text('Cancelled'), findsOneWidget);
      expect(find.textContaining('Cancelled ones save you'), findsOneWidget);
    });

    testWidgets('adding a subscription from the form', (tester) async {
      final store = await pump(tester);
      await store.deleteSubscription('a');
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Subscriptions'), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Add').at(1)); // Bills, Subscriptions, Goals
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'Spotify');
      await tester.enterText(find.byType(TextFormField).at(1), '149');
      await tester.tap(find.widgetWithText(FilledButton, 'Add subscription'));
      await tester.pumpAndSettle();
      final s = store.subscriptions.firstWhere((x) => x.name == 'Spotify');
      expect(s.cents, 14900);
      expect(s.cycle, BillingCycle.monthly);
    });

    testWidgets('the form asks for a name, a real amount and a web address', (tester) async {
      final store = await pump(tester);
      final before = store.subscriptions.length;
      await tester.scrollUntilVisible(find.text('Subscriptions'), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Add').at(1)); // Bills, Subscriptions, Goals
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Add subscription'));
      await tester.pumpAndSettle();
      expect(find.text('Give the subscription a name'), findsOneWidget);
      expect(find.textContaining('Enter an amount'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).at(0), 'X');
      await tester.enterText(find.byType(TextFormField).at(1), '10');
      await tester.enterText(find.byType(TextFormField).at(2), 'not a link');
      await tester.tap(find.widgetWithText(FilledButton, 'Add subscription'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Start with https://'), findsOneWidget);
      expect(store.subscriptions.length, before);
    });
  });
}
