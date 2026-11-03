import 'package:faelen/core/theme.dart';
import 'package:faelen/features/budget/models/budget_models.dart';
import 'package:faelen/features/budget/screens/budget_screen.dart';
import 'package:faelen/features/budget/services/budget_repo.dart';
import 'package:faelen/features/budget/state/budget_store.dart';
import 'package:faelen/features/budget/widgets/account_form_sheet.dart';
import 'package:faelen/features/budget/widgets/bank_card.dart';
import 'package:faelen/features/budget/widgets/budget_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

double contrast(Color a, Color b) {
  final l1 = a.computeLuminance(), l2 = b.computeLuminance();
  return (l1 > l2 ? l1 + 0.05 : l2 + 0.05) / (l1 > l2 ? l2 + 0.05 : l1 + 0.05);
}

void main() {
  group('colours', () {
    test('there are many card colours and the first six keep their old places', () {
      expect(cardSkins.length, 18);
      expect(cardSkins.take(6).map((s) => s.name), ['Coral', 'Lilac', 'Sun', 'Mint', 'Sky', 'Ink']);
      expect(cardSkins.map((s) => s.name).toSet().length, 18, reason: 'names are unique');
      expect(cardSkins.map((s) => s.face.toARGB32()).toSet().length, 18, reason: 'faces are unique');
      expect(cardSkins.any((s) => s.name == 'Royal blue' && s.dark), isTrue, reason: 'a proper deep blue for e-wallets');
    });

    test('text on every action colour is readable, in both themes', () {
      for (final s in cardSkins) {
        for (final b in Brightness.values) {
          final t = Tone.from(s, b);
          expect(contrast(t.main, t.on), greaterThanOrEqualTo(4.5), reason: '${s.name} ${b.name} main/on');
          // The wash is what unselected tiles sit on, with the page's normal text over it.
          final text = b == Brightness.dark ? Palette.dark.text : Palette.light.text;
          expect(contrast(t.soft, text), greaterThanOrEqualTo(4.5), reason: '${s.name} ${b.name} soft/text');
        }
      }
    });

    test('in the dark theme the outline is a tint of the colour, not the near-white ink', () {
      for (final s in cardSkins) {
        final light = Tone.from(s, Brightness.light);
        final dark = Tone.from(s, Brightness.dark);
        expect(light.line, Palette.light.ink);
        expect(dark.line, isNot(Palette.dark.ink), reason: s.name);
        expect(dark.shade.computeLuminance(), lessThan(dark.main.computeLuminance()), reason: '${s.name} shadow is deeper than the fill');
      }
    });

    test('deep colours are lifted on the dark page so they do not vanish into it', () {
      for (final s in cardSkins.where((s) => s.dark)) {
        final t = Tone.from(s, Brightness.dark);
        expect(contrast(t.main, Palette.dark.bg), greaterThanOrEqualTo(3), reason: s.name);
      }
    });

    test('goals only offer light colours', () {
      expect(lightSkinIndexes.every((i) => !cardSkins[i].dark), isTrue);
      expect(lightSkinIndexes, isNotEmpty);
    });
  });

  group('layout', () {
    Future<BudgetStore> pump(WidgetTester tester, {Size size = const Size(360, 740), Brightness b = Brightness.light, double text = 1, int cards = 3}) async {
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final store = BudgetStore(MemoryBudgetRepo());
      await store.load();
      await store.saveAccount(const Account(id: 'a', name: 'MARICARD', issuer: 'MARIBANK', network: CardNetwork.mastercard, last4: '4821', skin: 0, openingCents: 7100000));
      if (cards > 1) await store.saveAccount(const Account(id: 'b', name: 'Gcash wallet', issuer: 'GCash', kind: CardKind.ewallet, skin: 10, openingCents: 10000));
      if (cards > 2) await store.saveAccount(const Account(id: 'c', name: 'Cash', kind: CardKind.cash, skin: 3));
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

    for (final b in Brightness.values) {
      testWidgets('Overview (the default with several cards) fits on one screen: total, actions, every card (${b.name})', (tester) async {
        final store = await pump(tester, b: b);
        expect(store.overview, isTrue);
        final barTop = tester.getTopLeft(find.byTooltip('Cards')).dy;
        for (final label in ['All cards', 'Total across 3 cards', 'Expense', 'Income', 'Move', 'Your cards', 'MARICARD']) {
          final r = tester.getRect(find.text(label).first);
          expect(r.bottom, lessThan(barTop), reason: '$label is above the tab bar');
        }
        expect(find.text('Gcash wallet'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('A single card fits on one screen: card, actions, this month, Recent (${b.name})', (tester) async {
        final store = await pump(tester, b: b);
        store.select('a');
        await tester.pumpAndSettle();
        final barTop = tester.getTopLeft(find.byTooltip('Cards')).dy;
        for (final label in ['MARICARD', 'Expense', 'Income', 'Move', 'Edit', 'In this month', 'Out this month', 'Recent']) {
          final r = tester.getRect(find.text(label).first);
          expect(r.bottom, lessThan(barTop), reason: '$label is above the tab bar');
        }
        expect(find.text('MARIBANK'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('nothing floats over the lists: Add lives in the Activity search row', (tester) async {
      await pump(tester);
      expect(find.byIcon(Icons.add_rounded), findsNothing);
      await tester.tap(find.byTooltip('Activity'));
      await tester.pumpAndSettle();
      // The Add button sits in the search row, so nothing floats over the list.
      expect(find.byIcon(Icons.add_rounded), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('one selector lists every card with its balance; picking one drills in, All cards goes back', (tester) async {
      final store = await pump(tester);
      await tester.tap(find.text('All cards').first);
      await tester.pumpAndSettle();
      expect(find.text('Add a card'), findsOneWidget);
      expect(find.text('3 cards together'), findsOneWidget);
      await tester.tap(find.text('Gcash wallet').last);
      await tester.pumpAndSettle();
      expect(store.selected!.id, 'b');
      expect(store.overview, isFalse);
      expect(find.text('GCash'), findsOneWidget);
      expect(Tone.from(store.selected!.skinData, Brightness.light).main, cardSkins[10].face);

      await tester.tap(find.text('Gcash wallet').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('All cards').last);
      await tester.pumpAndSettle();
      expect(store.overview, isTrue);
    });

    testWidgets('tapping a card in the overview opens it', (tester) async {
      final store = await pump(tester);
      await tester.tap(find.text('Cash').first);
      await tester.pumpAndSettle();
      expect(store.selected!.id, 'c');
    });

    testWidgets('the selector and the buttons keep their place whether there are 2 cards or 12', (tester) async {
      final few = await pump(tester, cards: 2);
      few.select('a');
      await tester.pumpAndSettle();
      final selectorFew = tester.getRect(find.byTooltip('Hide balances').evaluate().isEmpty ? find.byIcon(Icons.visibility_rounded) : find.byTooltip('Hide balances'));
      final expenseFew = tester.getTopLeft(find.text('Expense').first);

      for (var i = 0; i < 10; i++) {
        await few.saveAccount(Account(id: 'x$i', name: 'Extra card number $i', skin: i % 18));
      }
      few.select('a');
      await tester.pumpAndSettle();
      final selectorMany = tester.getRect(find.byIcon(Icons.visibility_rounded));
      final expenseMany = tester.getTopLeft(find.text('Expense').first);
      expect(selectorMany, selectorFew);
      expect(expenseMany, expenseFew, reason: 'more cards never push the rest of the screen down');
      expect(tester.takeException(), isNull);
    });

    testWidgets('the overview adds up every card and shows where the money went', (tester) async {
      final store = await pump(tester);
      await store.saveTxn(Txn(id: 't1', accountId: 'a', cents: 25000, income: false, category: 'food', day: dateOnly(DateTime.now()), createdAt: 1));
      await store.saveTxn(Txn(id: 't2', accountId: 'b', cents: 100000, income: true, category: 'salary', day: dateOnly(DateTime.now()), createdAt: 2));
      await tester.pumpAndSettle();
      expect(find.text('Where it went this month'), findsOneWidget);
      expect(find.text('Food'), findsWidgets);
      expect(find.text('Kept'), findsOneWidget);
      expect(store.summary().net, 75000);
    });

    testWidgets('Activity filters stay on one row', (tester) async {
      await pump(tester);
      await tester.tap(find.byTooltip('Activity'));
      await tester.pumpAndSettle();
      final all = tester.getTopLeft(find.text('All')).dy;
      expect(tester.getTopLeft(find.text('Expenses')).dy, closeTo(all, 8));
      expect(tester.getTopLeft(find.text('Income')).dy, closeTo(all, 8));
      expect(find.byIcon(Icons.tune_rounded), findsOneWidget);
      expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    });

    testWidgets('a card called Debit does not say Debit twice on its face', (tester) async {
      tester.view.physicalSize = const Size(360, 740) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final store = BudgetStore(MemoryBudgetRepo());
      await store.load();
      await store.saveAccount(const Account(id: 'd', name: 'Debit', issuer: 'BDO'));
      await tester.pumpWidget(ChangeNotifierProvider.value(value: store, child: MaterialApp(theme: buildTheme(Brightness.light), home: const BudgetScreen())));
      await tester.pumpAndSettle();
      expect(find.text('Debit'), findsWidgets);
      final onFace = find.descendant(of: find.byType(BankCard), matching: find.text('Debit'));
      expect(onFace, findsOneWidget);
    });

    testWidgets('large text on a small phone still fits', (tester) async {
      await pump(tester, size: const Size(320, 640), text: 1.4, b: Brightness.dark);
      expect(tester.takeException(), isNull);
      for (final tab in ['Activity', 'Budgets', 'Plans', 'Cards']) {
        await tester.tap(find.byTooltip(tab));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: tab);
      }
    });

    for (final b in Brightness.values) {
      testWidgets('card form shows the card, every colour and every field without scrolling (${b.name})', (tester) async {
        tester.view.physicalSize = const Size(360, 740) * 3;
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
          theme: buildTheme(b),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(child: TextButton(onPressed: () => showAccountForm(context, newId: () => 'x'), child: const Text('open'))),
            ),
          ),
        ));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        final h = 740.0;
        for (final label in ['Colour', 'Card name', 'Bank or wallet', 'Type', 'Network', 'Last 4 digits', 'Balance today', 'Add card']) {
          final r = tester.getRect(find.text(label).first);
          expect(r.bottom, lessThanOrEqualTo(h), reason: '$label is on screen without scrolling');
          expect(r.top, greaterThan(0));
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('picking a colour in the form changes the card preview', (tester) async {
      tester.view.physicalSize = const Size(360, 740) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      Account? saved;
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(child: TextButton(onPressed: () async => saved = await showAccountForm(context, newId: () => 'x'), child: const Text('open'))),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final swatches = find.byWidgetPredicate((w) => w is Container && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).shape == BoxShape.circle && cardSkins.any((s) => (w.decoration as BoxDecoration).color == s.face));
      expect(swatches, findsNWidgets(18));
      await tester.tap(swatches.at(10)); // Royal blue
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add card'));
      await tester.pumpAndSettle();
      expect(saved!.skin, 10);
    });
  });
}
