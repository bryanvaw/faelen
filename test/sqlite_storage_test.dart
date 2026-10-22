import 'dart:convert';
import 'dart:io';

import 'package:faelen/features/media/models/media_entry.dart';
import 'package:faelen/features/media/screens/media_screen.dart';
import 'package:faelen/features/media/services/cover_service.dart';
import 'package:faelen/features/media/services/entry_database.dart';
import 'package:faelen/features/media/services/storage_service.dart';
import 'package:faelen/features/media/state/media_store.dart';
import 'package:faelen/features/media/widgets/media_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

MediaEntry entry(String id, {String? title, int current = 0, Status status = Status.watching}) =>
    MediaEntry(id: id, title: title ?? 'Title $id', type: MediaType.anime, status: status, current: current, total: 100);

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late String path;

  /// A new connection to the same file, as the app and a notification button each have.
  final opened = <StorageService>[];
  StorageService open() {
    final s = StorageService(db: EntryDatabase(factory: databaseFactoryFfi, path: path));
    opened.add(s);
    return s;
  }

  MediaStore newStore([StorageService? s]) => MediaStore(s ?? open(), covers: CoverService.disabled());

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dir = Directory.systemTemp.createTempSync('faelen_db_test');
    path = '${dir.path}/faelen.db';
  });
  tearDown(() async {
    for (final s in opened) {
      await s.close();
    }
    opened.clear();
    dir.deleteSync(recursive: true);
  });

  group('SQLite storage', () {
    test('entries survive a restart, including edits and deletes', () async {
      final a = open();
      await a.load();
      await a.save([entry('1'), entry('2'), entry('3')]);

      final b = open();
      var loaded = await b.load();
      expect(loaded.map((e) => e.id).toSet(), {'1', '2', '3'});

      await b.save([for (final e in loaded) if (e.id != '2') e.id == '3' ? e.copyWith(current: 9) : e]);
      loaded = await open().load();
      expect(loaded.map((e) => e.id).toSet(), {'1', '3'});
      expect(loaded.firstWhere((e) => e.id == '3').current, 9);
    });

    test('saving writes only what changed, so another writer\'s change is not overwritten', () async {
      final app = open();
      await app.save([entry('x'), entry('y')]);
      final inApp = await app.load();

      // The notification button (another isolate, another connection) bumps x.
      final background = open();
      final theirs = await background.load();
      await background.save([for (final e in theirs) e.id == 'x' ? e.copyWith(current: 50) : e]);

      // The app, still holding the old x, bumps y. The old whole-list save would have undone x.
      await app.save([for (final e in inApp) e.id == 'y' ? e.copyWith(current: 7) : e]);

      final fresh = {for (final e in await open().load()) e.id: e};
      expect(fresh['x']!.current, 50);
      expect(fresh['y']!.current, 7);
    });

    test('the old JSON list is carried over once and left in place', () async {
      SharedPreferences.setMockInitialValues({
        'media_entries_v1': jsonEncode([entry('1').toJson(), entry('2').toJson()]),
      });
      final s = open();
      expect((await s.load()).map((e) => e.id).toSet(), {'1', '2'});

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('media_entries_v1'), isNotNull); // untouched, as a fallback
      expect(prefs.getBool('media_sqlite_migrated_v1'), isTrue);

      // Later edits live in the database only; the old text is never imported again.
      await s.save([entry('1')]);
      await prefs.setString('media_entries_v1', jsonEncode([entry('9').toJson()]));
      expect((await open().load()).map((e) => e.id), ['1']);
    });

    test('entries the old reader had to skip are reported on the first run', () async {
      SharedPreferences.setMockInitialValues({
        'media_entries_v1': jsonEncode([entry('1').toJson(), 'not an entry', entry('3').toJson()]),
      });
      final s = open();
      expect((await s.load()).map((e) => e.id), ['1', '3']);
      expect(s.skipped, 1);
    });

    test('an unreadable row is skipped but kept in the file', () async {
      final s = open();
      await s.save([entry('1')]);
      final db = await databaseFactoryFfi.openDatabase(path);
      await db.insert('entries', {'id': 'bad', 'title': 't', 'type': 'anime', 'status': 'watching', 'updated_at': 0, 'data': '{broken'});
      await db.close();

      final again = open();
      expect((await again.load()).map((e) => e.id), ['1']);
      expect(again.skipped, 1);

      await again.save([entry('1', current: 2)]); // saving must not delete the row it could not read
      final db2 = await databaseFactoryFfi.openDatabase(path);
      expect(await db2.query('entries', where: "id = 'bad'"), hasLength(1));
      await db2.close();
    });

    test('a store on SQLite keeps data across restarts, import and undo', () async {
      final s = newStore();
      await s.load();
      await s.save(entry('1'));
      await s.save(entry('2'));
      final removed = await s.softDelete('1');
      await s.restore(removed!);
      await s.importData([entry('3').toJson()], replace: false);

      final again = newStore();
      await again.load();
      expect(again.totalCount, 3);
      await again.importData([entry('7').toJson()], replace: true);
      final last = newStore();
      await last.load();
      expect(last.items.map((e) => e.id), ['7']);
    });

    test('refresh picks up a change made through another connection', () async {
      final s = newStore();
      await s.load();
      await s.save(entry('1'));

      final other = open();
      final theirs = await other.load();
      await other.save([theirs.single.copyWith(current: 40)]);

      await s.refresh();
      expect(s.items.single.current, 40);
    });

    test('a library of several thousand entries loads quickly', () async {
      final s = open();
      await s.save([for (var i = 0; i < 5000; i++) entry('$i', title: 'Show number $i')]);

      final watch = Stopwatch()..start();
      final loaded = await open().load();
      watch.stop();
      expect(loaded, hasLength(5000));
      expect(watch.elapsed, lessThan(const Duration(seconds: 3)));
    });
  });

  group('cached list', () {
    test('visible is reused until something changes, then rebuilt', () async {
      final s = MediaStore(StorageService(), covers: CoverService.disabled());
      await s.load();
      await s.save(entry('1', title: 'Naruto'));
      await s.save(entry('2', title: 'Bleach'));

      final first = s.visible;
      expect(identical(s.visible, first), isTrue);

      s.setQuery('nar');
      expect(s.visible.map((e) => e.id), ['1']);
      s.setQuery('');
      s.setStatus(Status.completed);
      expect(s.visible, isEmpty);
      s.setStatus(null);

      await s.save(entry('1', title: 'Naruto', current: 5));
      expect(s.visible.firstWhere((e) => e.id == '1').current, 5);
    });

    test('status counts follow saves and deletes', () async {
      final s = MediaStore(StorageService(), covers: CoverService.disabled());
      await s.load();
      await s.save(entry('1'));
      await s.save(entry('2', status: Status.completed));
      expect(s.countWhere(Status.watching), 1);
      expect(s.countWhere(Status.completed), 1);

      await s.save(entry('1', status: Status.completed));
      expect(s.countWhere(Status.watching), 0);
      expect(s.countWhere(Status.completed), 2);

      await s.delete('2');
      expect(s.countWhere(Status.completed), 1);
    });
  });

  testWidgets('a big library builds only the cards on screen', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final store = MediaStore(StorageService(), covers: CoverService.disabled());
    await store.load();
    await store.importData([for (var i = 0; i < 1000; i++) entry('$i', title: 'Show ${i.toString().padLeft(4, '0')}').toJson()], replace: true);

    await tester.pumpWidget(ChangeNotifierProvider.value(value: store, child: const MaterialApp(home: MediaScreen())));
    await tester.pumpAndSettle();

    expect(find.byType(MediaCard).evaluate().length, lessThan(15));
    expect(find.text('1000'), findsWidgets); // the library count still covers everything

    // Scrolling far brings later entries in, and drops the early ones.
    await tester.dragUntilVisible(find.text('Show 0500'), find.byType(CustomScrollView), const Offset(0, -600), maxIteration: 2000);
    expect(find.text('Show 0500'), findsOneWidget);
    expect(find.text('Show 0000'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
