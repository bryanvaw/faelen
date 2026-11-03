import 'package:faelen/core/theme.dart';
import 'package:faelen/features/budget/models/budget_models.dart';
import 'package:faelen/features/budget/screens/budget_screen.dart';
import 'package:faelen/features/budget/services/budget_repo.dart';
import 'package:faelen/features/budget/state/budget_store.dart';
import 'package:faelen/features/budget/widgets/account_form_sheet.dart';
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
      testWidgets('Cards tab: card, switcher, actions and this month are all on screen without scrolling (${b.name})', (tester) async {
        await pump(tester, b: b);
        final h = tester.view.physicalSize.height / tester.view.devicePixelRatio;
        final barTop = tester.getTopLeft(find.text('Cards').last).dy;
        for (final label in ['Expense', 'Income', 'Move', 'Edit', 'In this month', 'Out this month', 'Recent']) {
          final r = tester.getRect(find.text(label).first);
          expect(r.bottom, lessThan(barTop), reason: '$label is above the tab bar');
          expect(r.bottom, lessThan(h));
        }
        expect(find.text('MARIBANK'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('no floating Add on the Cards tab, so nothing overlaps the Recent text', (tester) async {
      await pump(tester);
      expect(find.text('Add'), findsNothing);
      await tester.tap(find.text('Activity'));
      await tester.pumpAndSettle();
      expect(find.text('Add'), findsOneWidget);
    });

    testWidgets('chips switch the card without swiping, and the whole screen takes its colour', (tester) async {
      final store = await pump(tester);
      expect(store.selected!.id, 'a');
      await tester.tap(find.text('Gcash wallet'));
      await tester.pumpAndSettle();
      expect(store.selected!.id, 'b');
      expect(find.text('GCash'), findsOneWidget);
      expect(Tone.from(store.selected!.skinData, Brightness.light).main, cardSkins[10].face);
    });

    testWidgets('swiping the card is a shortcut for the chips', (tester) async {
      final store = await pump(tester);
      await tester.fling(find.text('MARIBANK'), const Offset(-300, 0), 1200);
      await tester.pumpAndSettle();
      expect(store.selected!.id, 'b');
    });

    testWidgets('large text on a small phone still fits', (tester) async {
      await pump(tester, size: const Size(320, 640), text: 1.4, b: Brightness.dark);
      expect(tester.takeException(), isNull);
      for (final tab in ['Activity', 'Budgets', 'Plans', 'Cards']) {
        await tester.tap(find.text(tab).last);
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
