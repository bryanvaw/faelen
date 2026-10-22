import 'dart:io';

import 'package:faelen/core/settings_store.dart';
import 'package:faelen/features/media/models/media_entry.dart';
import 'package:faelen/features/media/screens/media_screen.dart';
import 'package:faelen/features/media/services/cover_service.dart';
import 'package:faelen/features/media/services/entry_database.dart';
import 'package:faelen/features/media/services/storage_service.dart';
import 'package:faelen/features/media/state/media_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Out so far in the edit form', () {
    final tenDaysAgo = DateTime.now().subtract(const Duration(days: 10)).millisecondsSinceEpoch;
    // Out every day, 2 were out ten days ago, so 12 are out today.
    final daily = MediaEntry(
      id: 'a', title: 'Daily Show', type: MediaType.anime, status: Status.watching,
      releaseDays: const [1, 2, 3, 4, 5, 6, 7], releasedCount: 2, releasedOn: tenDaysAgo,
    );

    Future<MediaStore> openEdit(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = MediaStore(StorageService(), covers: CoverService.disabled());
      await store.load();
      await store.save(daily);
      await tester.pumpWidget(MultiProvider(
        providers: [ChangeNotifierProvider.value(value: store), ChangeNotifierProvider(create: (_) => SettingsStore())],
        child: const MaterialApp(home: MediaScreen()),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Daily Show'));
      await tester.pumpAndSettle();
      return store;
    }

    testWidgets('shows today\'s figure, not the count saved ten days ago', (tester) async {
      await openEdit(tester);
      expect(find.widgetWithText(TextFormField, '12'), findsOneWidget);
    });

    testWidgets('saving without touching the schedule keeps the original anchor', (tester) async {
      final store = await openEdit(tester);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final e = store.items.single;
      expect(e.releasedCount, 2);
      expect(e.releasedOn, tenDaysAgo);
    });

    testWidgets('changing a release day keeps the 12 that are out', (tester) async {
      final store = await openEdit(tester);
      await tester.tap(find.text('Su')); // drop Sunday
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final e = store.items.single;
      expect(e.releaseDays, [1, 2, 3, 4, 5, 6]);
      expect(e.releasedCount, 12); // used to fall back to the stale 2
    });
  });

  group('SQLite after a refresh', () {
    late Directory dir;
    late String path;
    final opened = <StorageService>[];
    StorageService open() {
      final s = StorageService(db: EntryDatabase(factory: databaseFactoryFfi, path: path));
      opened.add(s);
      return s;
    }

    setUp(() {
      sqfliteFfiInit();
      dir = Directory.systemTemp.createTempSync('faelen_refresh_test');
      path = '${dir.path}/faelen.db';
    });
    tearDown(() async {
      for (final s in opened) {
        await s.close();
      }
      opened.clear();
      dir.deleteSync(recursive: true);
    });

    test('an unchanged refresh does not make the next save rewrite (and clobber) everything', () async {
      const x = MediaEntry(id: 'x', title: 'X', status: Status.watching, total: 100);
      const y = MediaEntry(id: 'y', title: 'Y', status: Status.watching, total: 100);
      final app = MediaStore(open(), covers: CoverService.disabled());
      await app.load();
      await app.save(x);
      await app.save(y);

      await app.refresh(); // nothing changed, as on most returns to the app

      // The notification button bumps X while the app is in the background.
      final background = open();
      final theirs = await background.load();
      await background.save([for (final e in theirs) e.id == 'x' ? e.copyWith(current: 50) : e]);

      // The app (not refreshed yet) bumps Y. X must keep the button's value.
      await app.save(app.items.firstWhere((e) => e.id == 'y').copyWith(current: 7));

      final fresh = {for (final e in await open().load()) e.id: e};
      expect(fresh['x']!.current, 50);
      expect(fresh['y']!.current, 7);
    });
  });
}
