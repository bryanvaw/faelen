import 'package:faelen/core/theme.dart';
import 'package:faelen/features/budget/models/budget_models.dart';
import 'package:faelen/features/budget/screens/import_screen.dart';
import 'package:faelen/features/budget/services/budget_repo.dart';
import 'package:faelen/features/budget/services/statement_import.dart';
import 'package:faelen/features/budget/state/budget_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const _single = '''Account Statement
Account: 1234-5678
Date,Description,Amount,Balance
11/03/2026,JOLLIBEE SM NORTH,"-1,250.50","10,000.00"
11/04/2026,SALARY ACME CORP,"25,000.00","35,000.00"
11/05/2026,Grab Ride,-180.00,"34,820.00"
Total,,"23,569.50",
''';

const _twoCol = '''Transaction Date;Details;Debit;Credit
03-Nov-2026;Meralco Payment;2,345.67;
04-Nov-2026;Cash deposit;;5,000.00
05-Nov-2026;Watsons;120.00;
''';

void main() {
  group('csv', () {
    test('quotes, doubled quotes, commas inside cells and a byte-order mark', () {
      final rows = parseCsv('﻿a,b,c\n"x, y","say ""hi""",3\n\n');
      expect(rows, [
        ['a', 'b', 'c'],
        ['x, y', 'say "hi"', '3'],
      ]);
    });

    test('semicolon, tab and pipe separators and windows line endings', () {
      expect(parseCsv('a;b;c\r\n1;2;3'), [
        ['a', 'b', 'c'],
        ['1', '2', '3'],
      ]);
      expect(parseCsv('a\tb\n1\t2').last, ['1', '2']);
      expect(parseCsv('a|b|c\n1|2|3').last, ['1', '2', '3']);
    });

    test('a newline inside a quoted cell stays in the cell', () {
      expect(parseCsv('a,b\n"line1\nline2",2')[1][0], 'line1\nline2');
    });
  });

  group('dates', () {
    test('common shapes', () {
      expect(parseStatementDate('2026-11-03'), DateTime(2026, 11, 3));
      expect(parseStatementDate('2026/11/03 14:22:10'), DateTime(2026, 11, 3));
      expect(parseStatementDate('11/03/2026'), DateTime(2026, 11, 3));
      expect(parseStatementDate('03-Nov-2026'), DateTime(2026, 11, 3));
      expect(parseStatementDate('3 November 2026'), DateTime(2026, 11, 3));
      expect(parseStatementDate('Nov 3, 2026'), DateTime(2026, 11, 3));
      expect(parseStatementDate('Sept 3 2026'), DateTime(2026, 9, 3));
      expect(parseStatementDate('03/11/26', dayFirst: true), DateTime(2026, 11, 3));
    });

    test('an impossible day or month decides which number is which', () {
      expect(parseStatementDate('25/11/2026'), DateTime(2026, 11, 25));
      expect(parseStatementDate('11/25/2026', dayFirst: true), DateTime(2026, 11, 25));
    });

    test('junk and impossible dates are refused', () {
      expect(parseStatementDate(''), isNull);
      expect(parseStatementDate('Total'), isNull);
      expect(parseStatementDate('2026-02-31'), isNull);
      expect(parseStatementDate('13/13/2026'), isNull);
    });
  });

  group('amounts', () {
    test('signs, currency, brackets and DR/CR', () {
      expect(parseSignedCents('₱1,250.50'), 125050);
      expect(parseSignedCents('-250'), -25000);
      expect(parseSignedCents('(250.00)'), -25000);
      expect(parseSignedCents('250.00 DR'), -25000);
      expect(parseSignedCents('250.00 CR'), 25000);
      expect(parseSignedCents('PHP 99'), 9900);
      expect(parseSignedCents('+10'), 1000);
      expect(parseSignedCents('250-'), -25000);
      expect(parseSignedCents('abc'), isNull);
      expect(parseSignedCents(''), isNull);
    });

    test('type words', () {
      expect(incomeFromType('Debit'), isFalse);
      expect(incomeFromType('Cash Out'), isFalse);
      expect(incomeFromType('Credit'), isTrue);
      expect(incomeFromType('Cash In'), isTrue);
      expect(incomeFromType('Refund received'), isTrue);
      expect(incomeFromType('Something else'), isNull);
    });
  });

  group('categories', () {
    test('guessed from the description', () {
      expect(guessCategory('JOLLIBEE SM NORTH', income: false), 'food');
      expect(guessCategory('Grab Ride', income: false), 'transport');
      expect(guessCategory('GRABFOOD order', income: false), 'food');
      expect(guessCategory('Meralco Payment', income: false), 'bills');
      expect(guessCategory('Watsons', income: false), 'health');
      expect(guessCategory('Shopee', income: false), 'shopping');
      expect(guessCategory('???', income: false), 'other');
      expect(guessCategory('Salary Nov', income: true), 'salary');
      expect(guessCategory('Cash deposit', income: true), 'income_other');
    });
  });

  group('statement table', () {
    test('finds the header under a title block, one amount column, and skips the totals line', () {
      final t = StatementTable.parse(_single);
      expect(t.hasHeader, isTrue);
      expect(t.headers.take(3), ['Date', 'Description', 'Amount']);
      final rows = t.rows(t.guess!);
      expect(rows.length, 3);
      expect([rows[0].income, rows[0].cents, rows[0].category], [false, 125050, 'food']);
      expect([rows[1].income, rows[1].cents, rows[1].category], [true, 2500000, 'salary']);
      expect(rows[2].day, DateTime(2026, 11, 5));
    });

    test('separate debit and credit columns', () {
      final t = StatementTable.parse(_twoCol);
      expect(t.guess!.moneyIn, isNotNull);
      final rows = t.rows(t.guess!);
      expect(rows.map((r) => (r.income, r.cents)), [(false, 234567), (true, 500000), (false, 12000)]);
      expect(rows.first.day, DateTime(2026, 11, 3));
    });

    test('a type column decides the direction when amounts are all positive', () {
      final t = StatementTable.parse('Date,Type,Description,Amount\n2026-11-03,Cash Out,Send to Ana,500.00\n2026-11-04,Cash In,From Ben,300.00');
      final rows = t.rows(t.guess!);
      expect(rows.map((r) => r.income), [false, true]);
      expect(rows.map((r) => r.note), ['Send to Ana', 'From Ben']);
    });

    test('swap flips every row (statements that show purchases as positive)', () {
      final t = StatementTable.parse(_single);
      final rows = t.rows(t.guess!, flip: true);
      expect(rows.map((r) => r.income), [true, false, true]);
    });

    test('day-first dates are recognised from the file itself', () {
      final t = StatementTable.parse('Date,Description,Amount\n25/11/2026,A,-1\n03/11/2026,B,-2');
      final rows = t.rows(t.guess!);
      expect(rows.map((r) => r.day), [DateTime(2026, 11, 25), DateTime(2026, 11, 3)]);
    });

    test('no header row: columns are worked out from what is in them', () {
      final t = StatementTable.parse('2026-11-03,Lunch at the office canteen,-150.00\n2026-11-04,Bus fare to work,-20.00\n2026-11-05,Salary advance,3000.00');
      expect(t.hasHeader, isFalse);
      expect([t.guess!.date, t.guess!.desc, t.guess!.amount], [0, 1, 2]);
      expect(t.rows(t.guess!).length, 3);
    });

    test('a file that is not a statement gives no guess and no rows', () {
      final t = StatementTable.parse('hello\nworld');
      expect(t.guess, isNull);
      expect(StatementTable.parse('').guess, isNull);
    });

    test('rows already on the card are marked as duplicates, one for one', () {
      final t = StatementTable.parse('Date,Description,Amount\n2026-11-03,Coffee,-100\n2026-11-03,Coffee,-100\n2026-11-03,Coffee,-100');
      final existing = [
        Txn(id: '1', accountId: 'a', cents: 10000, income: false, category: 'food', day: DateTime(2026, 11, 3), createdAt: 1),
        Txn(id: '2', accountId: 'other', cents: 10000, income: false, category: 'food', day: DateTime(2026, 11, 3), createdAt: 1),
      ];
      final rows = t.rows(t.guess!, existing: existing, accountId: 'a');
      expect(rows.map((r) => r.duplicate), [true, false, false], reason: 'only one match on card a');
      expect(rows.map((r) => r.selected), [false, true, true]);
    });

    test('long descriptions are cut and blank ones fall back to the type', () {
      final long = 'x' * 200;
      final t = StatementTable.parse('Date,Type,Description,Amount\n2026-11-03,Debit,$long,-1\n2026-11-04,Fee,,-2');
      final rows = t.rows(t.guess!);
      expect(rows[0].note.length, 80);
      expect(rows[1].note, 'Fee');
    });
  });

  group('screen', () {
    Future<BudgetStore> pump(WidgetTester tester, String csv, {int cards = 2, Size size = const Size(360, 740), Brightness b = Brightness.light}) async {
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final store = BudgetStore(MemoryBudgetRepo());
      await store.load();
      await store.saveAccount(const Account(id: 'a', name: 'Main', openingCents: 100000));
      if (cards > 1) await store.saveAccount(const Account(id: 'b', name: 'Wallet', skin: 10));
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(theme: buildTheme(b), home: ImportScreen(text: csv, fileName: 'statement.csv')),
      ));
      await tester.pumpAndSettle();
      return store;
    }

    testWidgets('shows what was found and imports the ticked rows onto the chosen card', (tester) async {
      final store = await pump(tester, _single);
      expect(find.textContaining('3 found'), findsOneWidget);
      expect(find.text('Import 3 transactions'), findsOneWidget);
      expect(find.text('Main'), findsOneWidget, reason: 'the first card is chosen by default');
      await tester.tap(find.text('Main'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wallet').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('JOLLIBEE SM NORTH')); // untick one
      await tester.pumpAndSettle();
      expect(find.text('Import 2 transactions'), findsOneWidget);
      await tester.tap(find.text('Import 2 transactions'));
      await tester.pumpAndSettle();
      expect(store.txns.length, 2);
      expect(store.txns.every((t) => t.accountId == 'b'), isTrue);
      expect(store.balanceOf(store.account('b')!), 2500000 - 18000);
      expect(store.balanceOf(store.account('a')!), 100000);
    });

    testWidgets('importing the same file twice adds nothing the second time', (tester) async {
      final store = await pump(tester, _single, cards: 1);
      await tester.tap(find.text('Import 3 transactions'));
      await tester.pumpAndSettle();
      expect(store.txns.length, 3);

      await tester.pumpWidget(ChangeNotifierProvider.value(
        key: UniqueKey(), // a fresh screen, as when the user opens the import again
        value: store,
        child: MaterialApp(theme: buildTheme(Brightness.light), home: const ImportScreen(text: _single, fileName: 'again.csv')),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('3 already in this card'), findsOneWidget);
      expect(find.text('Nothing ticked'), findsOneWidget);
    });

    testWidgets('swap in/out turns income into expense in the preview', (tester) async {
      await pump(tester, _single, cards: 1);
      expect(find.text('+₱25,000.00'), findsOneWidget);
      await tester.tap(find.byTooltip('Swap in/out'));
      await tester.pumpAndSettle();
      expect(find.text('-₱25,000.00'), findsOneWidget);
      expect(find.text('+₱25,000.00'), findsNothing);
    });

    testWidgets('the import button works from the overview, where no card is selected', (tester) async {
      final store = await pump(tester, _single);
      expect(store.overview, isTrue);
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNotNull);
    });

    testWidgets('a file with no recognisable columns says so and offers the column pickers', (tester) async {
      await pump(tester, 'hello\nworld', cards: 1);
      expect(find.textContaining('could not tell which columns'), findsOneWidget);
      expect(find.text('Date'), findsWidgets);
      expect(find.text('Nothing ticked'), findsOneWidget);
    });

    for (final (name, size, b) in [('phone light', const Size(360, 740), Brightness.light), ('small phone dark', const Size(320, 640), Brightness.dark)]) {
      testWidgets('fits without overflow: $name', (tester) async {
        await pump(tester, _twoCol, size: size, b: b);
        await tester.tap(find.byTooltip('Columns'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
