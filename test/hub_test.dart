import 'package:faelen/features/hub/hub_screen.dart';
import 'package:faelen/features/media/models/media_entry.dart';
import 'package:faelen/features/media/services/cover_service.dart';
import 'package:faelen/features/media/services/storage_service.dart';
import 'package:faelen/features/media/state/media_store.dart';
import 'package:faelen/features/planner/models/task.dart';
import 'package:faelen/features/planner/services/planner_repo.dart';
import 'package:faelen/features/planner/state/planner_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<MediaStore> pumpHub(WidgetTester tester, {List<MediaEntry> entries = const []}) async {
    final store = MediaStore(StorageService(), covers: CoverService.disabled());
    await store.load();
    for (final e in entries) {
      await store.save(e);
    }
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: store,
      child: const MaterialApp(home: HubScreen()),
    ));
    await tester.pumpAndSettle();
    return store;
  }

  testWidgets('hub lists modules; Vault, Budget and Planner are live', (tester) async {
    await pumpHub(tester);
    expect(find.text('Media'), findsOneWidget);
    expect(find.text('Planner'), findsOneWidget);
    expect(find.text('Budget'), findsOneWidget);
    expect(find.text('Vault'), findsOneWidget);
    expect(find.text('Passwords'), findsNothing);
    expect(find.text('More modules'), findsNothing); // four equal tiles, no second tier
    expect(find.text('Locked'), findsOneWidget);
    expect(find.text('Soon'), findsNothing);
    expect(find.text('Open'), findsNothing); // a tile says what the module has today, not "Open"
  });

  testWidgets('tapping Media opens it and back returns to the hub', (tester) async {
    await pumpHub(tester);
    await tester.tap(find.text('Media'));
    await tester.pumpAndSettle();
    expect(find.text('My List'), findsOneWidget);

    await tester.tap(find.byTooltip('Back to modules'));
    await tester.pumpAndSettle();
    expect(find.text('Your personal space'), findsOneWidget);
  });

  testWidgets('tapping Planner opens it', (tester) async {
    final media = MediaStore(StorageService(), covers: CoverService.disabled());
    await media.load();
    final planner = PlannerStore(MemoryPlannerRepo());
    await planner.load();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: media),
        ChangeNotifierProvider.value(value: planner),
      ],
      child: const MaterialApp(home: HubScreen()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Planner'));
    await tester.pumpAndSettle();
    expect(find.text('No open tasks'), findsOneWidget);
  });

  testWidgets('Media card shows how the list stands and the last followed title', (tester) async {
    await pumpHub(tester, entries: [
      const MediaEntry(id: '1', title: 'Solo Leveling', type: MediaType.manhwa, status: Status.watching, current: 32),
    ]);
    expect(find.text('1 watching'), findsOneWidget);
    expect(find.text('Solo Leveling'), findsOneWidget);
    expect(find.text('Ch 32 / ?'), findsOneWidget);
  });

  testWidgets('hub fits a 360x700 phone with no overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpHub(tester, entries: [
      const MediaEntry(id: '1', title: 'A long title that should be cut off with an ellipsis somewhere', type: MediaType.anime, status: Status.watching, url: 'https://example.com/x'),
    ]);
    expect(tester.takeException(), isNull);
    expect(tester.getBottomLeft(find.text('Budget')).dy, lessThan(700));
  });

  testWidgets('tiles say what each module has today', (tester) async {
    final media = MediaStore(StorageService(), covers: CoverService.disabled());
    await media.load();
    final planner = PlannerStore(MemoryPlannerRepo());
    await planner.load();
    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    Task task(String id, DateTime due) => Task(id: id, title: 'Task $id', due: due, createdAt: today, updatedAt: today);
    await planner.add(task('a', day));
    await planner.add(task('b', day));
    await planner.add(task('c', day.subtract(const Duration(days: 2))));
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: media),
        ChangeNotifierProvider.value(value: planner),
      ],
      child: const MaterialApp(home: HubScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('2 due today · 1 overdue'), findsOneWidget);
    // No Budget provider here, and the Vault never says what is inside.
    expect(find.text('Cards, spending & monthly limits'), findsOneWidget);
    expect(find.text('Locked'), findsOneWidget);
  });
}
