import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:faelen/core/theme.dart';
import 'package:faelen/features/planner/models/task.dart';
import 'package:faelen/features/planner/screens/planner_screen.dart';
import 'package:faelen/features/planner/services/planner_repo.dart';
import 'package:faelen/features/planner/services/task_reminders.dart';
import 'package:faelen/features/planner/state/planner_store.dart';

final _now = DateTime(2026, 11, 4, 10, 0); // a Wednesday

Task _t(String id, String title, {DateTime? due, int minutes = -1, Priority priority = Priority.normal, Repeat repeat = Repeat.none, bool remind = false, DateTime? doneAt, DateTime? updated}) => Task(
  id: id,
  title: title,
  due: due,
  minutes: minutes,
  priority: priority,
  repeat: repeat,
  remind: remind,
  doneAt: doneAt,
  createdAt: DateTime(2026, 11, 1),
  updatedAt: updated ?? DateTime(2026, 11, 1),
);

Future<PlannerStore> _store([List<Task> tasks = const []]) async {
  final repo = MemoryPlannerRepo();
  for (final t in tasks) {
    await repo.put(t);
  }
  final s = PlannerStore(repo, now: () => _now);
  await s.load();
  return s;
}

void main() {
  final today = DateTime(2026, 11, 4);

  group('dates', () {
    test('daily and weekly jump past today even when long overdue', () {
      expect(nextDue(DateTime(2026, 11, 4), Repeat.daily, today), DateTime(2026, 11, 5));
      expect(nextDue(DateTime(2026, 10, 1), Repeat.daily, today), DateTime(2026, 11, 5));
      expect(nextDue(DateTime(2026, 10, 28), Repeat.weekly, today), DateTime(2026, 11, 11));
      expect(nextDue(DateTime(2026, 11, 9), Repeat.weekly, today), DateTime(2026, 11, 9)); // already ahead: unchanged
    });

    test('monthly keeps the day and clamps short months', () {
      expect(nextDue(DateTime(2026, 10, 31), Repeat.monthly, DateTime(2026, 10, 31)), DateTime(2026, 11, 30));
      expect(nextDue(DateTime(2026, 1, 31), Repeat.monthly, DateTime(2026, 2, 1)), DateTime(2026, 2, 28));
    });

    test('a task survives a JSON round trip, and a bad row is dropped', () {
      final t = _t('a', 'Pay rent', due: DateTime(2026, 11, 7), minutes: 570, priority: Priority.high, repeat: Repeat.monthly, remind: true);
      final back = Task.fromJson(t.toJson())!;
      expect(back.title, 'Pay rent');
      expect(back.due, DateTime(2026, 11, 7));
      expect(back.minutes, 570);
      expect(back.priority, Priority.high);
      expect(back.repeat, Repeat.monthly);
      expect(back.remind, isTrue);
      expect(Task.fromJson({'id': 'x', 't': '  '}), isNull);
      expect(Task.fromJson('nope'), isNull);
      expect(Task.fromJson({'id': 'x', 't': 'Ok', 'd': 20261399})!.due, isNull); // impossible date
    });
  });

  group('lists', () {
    test('Today holds overdue first, then today by time; Upcoming is by day with undated last', () async {
      final s = await _store([
        _t('late', 'Late', due: DateTime(2026, 11, 2)),
        _t('later', 'Evening', due: today, minutes: 18 * 60),
        _t('early', 'Morning', due: today, minutes: 8 * 60),
        _t('plain', 'No time', due: today, priority: Priority.high),
        _t('tom', 'Tomorrow thing', due: DateTime(2026, 11, 5)),
        _t('some', 'Someday', due: null),
        _t('fin', 'Finished', due: today, doneAt: _now),
      ]);
      final g = s.groups(PlannerView.today);
      expect(g.map((e) => e.title), ['Overdue', 'Today']);
      expect(g[0].tasks.map((e) => e.id), ['late']);
      expect(g[1].tasks.map((e) => e.id), ['early', 'later', 'plain']);
      final up = s.groups(PlannerView.upcoming);
      expect(up.map((e) => e.title), ['Tomorrow', 'No date']);
      expect(s.todayCount, 4);
      expect(s.overdueCount, 1);
      expect(s.upcomingCount, 2);
      expect(s.doneCount, 1);
    });

    test('finishing a one-off moves it to Done; Undo brings it back', () async {
      final s = await _store([_t('a', 'Once', due: today)]);
      final before = await s.toggle(s.tasks.single);
      expect(s.todayCount, 0);
      expect(s.doneCount, 1);
      await s.restore(before);
      expect(s.todayCount, 1);
      expect(s.doneCount, 0);
    });

    test('finishing a repeating task moves its day instead of filling Done', () async {
      final s = await _store([_t('a', 'Water plants', due: DateTime(2026, 11, 2), repeat: Repeat.weekly)]);
      await s.toggle(s.tasks.single);
      expect(s.doneCount, 0);
      expect(s.tasks.single.due, DateTime(2026, 11, 9));
      expect(s.movedTo('a'), DateTime(2026, 11, 9));
    });

    test('search narrows a list', () async {
      final s = await _store([_t('a', 'Buy rice', due: today), _t('b', 'Call mum', due: today)]);
      expect(s.groups(PlannerView.today, query: 'rice').single.tasks.single.id, 'a');
    });
  });

  group('backup', () {
    test('merge keeps the newer copy, replace swaps everything, junk is refused', () async {
      final s = await _store([_t('a', 'Mine old', updated: DateTime(2026, 11, 1)), _t('b', 'Only mine')]);
      final incoming = [
        _t('a', 'Theirs new', updated: DateTime(2026, 11, 3)).toJson(),
        _t('c', 'Only theirs').toJson(),
        {'id': 'bad'},
      ];
      expect(await s.importData(incoming, replace: false), 2);
      expect(s.tasks.map((t) => t.title).toSet(), {'Theirs new', 'Only mine', 'Only theirs'});
      await s.importData(incoming, replace: true);
      expect(s.tasks.map((t) => t.id).toSet(), {'a', 'c'});
      await expectLater(s.importData('nope', replace: true), throwsFormatException);
    });
  });

  group('reminders', () {
    test('plan covers future open tasks that asked for one, at their time or 9:00', () {
      final plan = TaskReminders.plan([
        _t('a', 'Timed', due: today, minutes: 15 * 60, remind: true),
        _t('b', 'Untimed tomorrow', due: DateTime(2026, 11, 5), remind: true),
        _t('c', 'Already passed', due: today, minutes: 8 * 60, remind: true),
        _t('d', 'Not asked', due: today, minutes: 16 * 60),
        _t('e', 'Finished', due: today, minutes: 17 * 60, remind: true, doneAt: _now),
        _t('f', 'No date', remind: true),
      ], _now);
      expect(plan.map((r) => r.title), ['Timed', 'Untimed tomorrow']);
      expect(plan[0].when, DateTime(2026, 11, 4, 15));
      expect(plan[1].when, DateTime(2026, 11, 5, 9));
      expect(plan[0].body, 'Due at 3:00 PM');
    });
  });

  group('screen', () {
    Future<PlannerStore> pump(WidgetTester tester, {Size size = const Size(360, 740), double text = 1, Brightness mode = Brightness.light, List<Task> tasks = const []}) async {
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      late PlannerStore store;
      await tester.runAsync(() async => store = await _store(tasks));
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: store,
          child: MaterialApp(
            theme: buildTheme(mode),
            builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(text)), child: child!),
            home: const PlannerScreen(),
          ),
        ),
      );
      await tester.pump();
      return store;
    }

    final many = [
      _t('1', 'Pay the electricity bill before the due date this Friday afternoon', due: today, minutes: 9 * 60, priority: Priority.high, repeat: Repeat.monthly, remind: true),
      _t('2', 'Buy rice', due: today),
      _t('3', 'Overdue thing', due: DateTime(2026, 11, 2), minutes: 600),
      _t('4', 'Later', due: DateTime(2026, 11, 9)),
    ];

    for (final (name, size, text, mode) in [
      ('360x740', const Size(360, 740), 1.0, Brightness.light),
      ('320x640 large text', const Size(320, 640), 1.4, Brightness.light),
      ('dark', const Size(360, 740), 1.0, Brightness.dark),
    ]) {
      testWidgets('fits $name with no overflow', (tester) async {
        await pump(tester, size: size, text: text, mode: mode, tasks: many);
        expect(tester.takeException(), isNull);
        expect(find.text('Planner'), findsOneWidget);
        expect(find.text('Overdue thing'), findsOneWidget);
      });
    }

    testWidgets('empty Today offers to add a task', (tester) async {
      await pump(tester);
      expect(find.text('Nothing due today'), findsOneWidget);
      expect(find.text('Add a task'), findsOneWidget);
    });

    testWidgets('adding a task from the sheet puts it on Today', (tester) async {
      final store = await pump(tester);
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      expect(find.text('New task'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'Renew passport');
      await tester.tap(find.text('Add task'));
      await tester.pumpAndSettle();
      expect(store.tasks.single.title, 'Renew passport');
      expect(store.tasks.single.due, today);
      expect(find.text('Renew passport'), findsOneWidget);
    });

    testWidgets('an empty title is refused', (tester) async {
      final store = await pump(tester);
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add task'));
      await tester.pumpAndSettle();
      expect(find.text('Give the task a name'), findsOneWidget);
      expect(store.tasks, isEmpty);
    });

    testWidgets('ticking a task finishes it and Undo brings it back', (tester) async {
      final store = await pump(tester, tasks: [_t('a', 'Buy rice', due: today)]);
      await tester.tap(find.byWidgetPredicate((w) => w is AnimatedContainer && w.constraints?.maxWidth == 26));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(store.doneCount, 1);
      expect(find.text('Done: “Buy rice”'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Undo'));
      await tester.pump();
      expect(store.doneCount, 0);
      expect(store.todayCount, 1);
    });
  });
}
