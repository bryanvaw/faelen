import 'dart:io';

import 'package:faelen/core/update_service.dart';
import 'package:faelen/features/media/models/media_entry.dart';
import 'package:faelen/features/media/services/cover_service.dart';
import 'package:faelen/features/media/services/entry_database.dart';
import 'package:faelen/features/media/services/pinned_actions.dart';
import 'package:faelen/features/media/services/release_schedule.dart';
import 'package:faelen/features/media/services/storage_service.dart';
import 'package:faelen/features/media/state/media_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A storage whose writes fail, to see what the store tells the user.
class _FailingStorage extends StorageService {
  @override
  Future<void> save(List<MediaEntry> entries) async => throw Exception('disk full');
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('pausing the release schedule', () {
    final day0 = DateTime(2026, 10, 1, 12);
    // Every day; 2 were out on day 0.
    final watching = MediaEntry(
      id: 'a', title: 'Daily', status: Status.watching,
      releaseDays: const [1, 2, 3, 4, 5, 6, 7], releasedCount: 2, releasedOn: day0.millisecondsSinceEpoch,
    );

    test('leaving Watching freezes the count at what was out that day', () {
      final day10 = day0.add(const Duration(days: 10));
      final done = settleSchedule(watching, watching.copyWith(status: Status.completed), day10);
      expect(done.releasedCount, 12);
      expect(done.releasedOn, day10.millisecondsSinceEpoch);
    });

    test('coming back counts from the return day, not through the gap', () {
      final day10 = day0.add(const Duration(days: 10));
      final away = settleSchedule(watching, watching.copyWith(status: Status.dropped), day10);

      final day40 = day0.add(const Duration(days: 40));
      final back = settleSchedule(away, away.copyWith(status: Status.watching), day40);
      expect(releaseStatus(back, day40)!.released, 12); // not 42
      expect(releaseStatus(back, day40.add(const Duration(days: 3)))!.released, 15);
    });

    test('on hold still counts, and plain edits change nothing', () {
      final hold = settleSchedule(watching, watching.copyWith(status: Status.onHold), day0.add(const Duration(days: 5)));
      expect(hold.releasedOn, watching.releasedOn);
      final same = settleSchedule(watching, watching.copyWith(notes: 'hi'), day0.add(const Duration(days: 5)));
      expect(same.releasedCount, 2);
    });

    test('a new entry and a series without a schedule are left alone', () {
      expect(settleSchedule(null, watching, day0), watching);
      const plain = MediaEntry(id: 'p', title: 'P', status: Status.watching);
      expect(settleSchedule(plain, plain.copyWith(status: Status.completed), day0).releasedOn, 0);
    });

    test('finishing from a notification button freezes it too', () {
      final out = applyPinnedAction([watching], 'done|a', now: day0.add(const Duration(days: 10)).millisecondsSinceEpoch)!;
      expect(out.entry.status, Status.completed);
      expect(out.entry.releasedCount, 12);
    });

    test('the store applies it on save', () async {
      final s = MediaStore(StorageService(), covers: CoverService.disabled());
      await s.load();
      final today = DateTime.now();
      final e = watching.copyWith(releasedCount: 2, releasedOn: today.subtract(const Duration(days: 10)).millisecondsSinceEpoch);
      await s.save(e);
      await s.save(s.items.single.copyWith(status: Status.completed));
      expect(s.items.single.releasedCount, 12);
    });
  });

  group('values read from a backup', () {
    test('impossible numbers and links are corrected', () {
      final e = MediaEntry.fromJson({
        'id': '1', 'title': 'T', 'current': 50, 'total': 12, 'rating': 99, 'season': -3,
        'url': 'javascript:alert(1)', 'releaseDays': [1], 'releaseMinutes': 5000, 'releasedCount': -4, 'updatedAt': -1,
      });
      expect(e.current, 12);
      expect(e.rating, 10);
      expect(e.season, 0);
      expect(e.url, '');
      expect(e.releaseMinutes, -1);
      expect(e.releasedCount, 0);
      expect(e.updatedAt, 0);
    });

    test('good values and web links are kept', () {
      final e = MediaEntry.fromJson({
        'id': '1', 'title': 'T', 'current': 3, 'total': 12, 'rating': 8, 'url': 'https://example.com/ch-3', 'releaseMinutes': 600,
        'releaseDays': [2], 'releasedCount': 4, 'releasedOn': 5,
      });
      expect((e.current, e.total, e.rating, e.url, e.releaseMinutes), (3, 12, 8, 'https://example.com/ch-3', 600));
    });
  });

  group('cover files', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('faelen_cover_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('names that point outside the folder are refused', () {
      final c = CoverService.inDirectory(dir);
      expect(c.fileFor('a-1.jpg'), isNotNull);
      for (final bad in ['../x.jpg', r'..\x.jpg', 'a/b.jpg', '', '..']) {
        expect(c.fileFor(bad), isNull, reason: bad);
      }
    });

    test('sweep removes only pictures nobody uses, and never everything', () async {
      File('${dir.path}/keep.jpg').writeAsStringSync('k');
      File('${dir.path}/orphan.jpg').writeAsStringSync('o');
      final c = CoverService.inDirectory(dir);

      await c.sweep({});
      expect(File('${dir.path}/orphan.jpg').existsSync(), isTrue); // nothing to compare against: do nothing

      await c.sweep({'keep.jpg'});
      expect(File('${dir.path}/keep.jpg').existsSync(), isTrue);
      expect(File('${dir.path}/orphan.jpg').existsSync(), isFalse);
    });

    test('loading the list sweeps leftovers', () async {
      final s = MediaStore(StorageService(), covers: CoverService.inDirectory(dir));
      await s.load();
      File('${dir.path}/mine.jpg').writeAsStringSync('m');
      await s.save(const MediaEntry(id: '1', title: 'T', cover: 'mine.jpg'));
      File('${dir.path}/leftover.jpg').writeAsStringSync('x');

      final again = MediaStore(StorageService(), covers: CoverService.inDirectory(dir));
      await again.load();
      expect(File('${dir.path}/mine.jpg').existsSync(), isTrue);
      expect(File('${dir.path}/leftover.jpg').existsSync(), isFalse);
    });

    test('an unreadable list does not sweep its pictures away', () async {
      File('${dir.path}/mine.jpg').writeAsStringSync('m');
      SharedPreferences.setMockInitialValues({'media_entries_v1': '[{"id":"1","title":"T","cover":"mine.jpg"}, "bad"]'});
      final s = MediaStore(StorageService(), covers: CoverService.inDirectory(dir));
      await s.load();
      expect(File('${dir.path}/mine.jpg').existsSync(), isTrue);
    });
  });

  group('failed saves', () {
    test('are reported once, not silently dropped', () async {
      final s = MediaStore(_FailingStorage(), covers: CoverService.disabled());
      await s.save(const MediaEntry(id: '1', title: 'T'));
      expect(s.takeSaveError(), contains('disk full'));
      expect(s.takeSaveError(), isNull);
      expect(s.error, isNull); // the "could not load" banner is separate
    });

    test('a replace import keeps the old pictures when it could not be saved', () async {
      final dir = Directory.systemTemp.createTempSync('faelen_import_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/old.jpg').writeAsStringSync('o');
      final s = MediaStore(_FailingStorage(), covers: CoverService.inDirectory(dir));
      await s.save(const MediaEntry(id: '1', title: 'T', cover: 'old.jpg'));
      s.takeSaveError(); // that first failure is not what this test is about
      await s.importData([const MediaEntry(id: '2', title: 'N').toJson()], replace: true);
      expect(File('${dir.path}/old.jpg').existsSync(), isTrue);
    });
  });

  group('bumping builds on the newest saved copy', () {
    late Directory dir;
    final opened = <StorageService>[];
    StorageService open() {
      final s = StorageService(db: EntryDatabase(factory: databaseFactoryFfi, path: '${dir.path}/faelen.db'));
      opened.add(s);
      return s;
    }

    setUp(() {
      sqfliteFfiInit();
      dir = Directory.systemTemp.createTempSync('faelen_update_test');
    });
    tearDown(() async {
      for (final s in opened) {
        await s.close();
      }
      opened.clear();
      dir.deleteSync(recursive: true);
    });

    test('a +1 from a notification is not lost when the app bumps next', () async {
      const x = MediaEntry(id: 'x', title: 'X', status: Status.watching, total: 100);
      final app = MediaStore(open(), covers: CoverService.disabled());
      await app.load();
      await app.save(x);

      // The notification button took X to 50 while the app still shows 0.
      final background = open();
      final theirs = await background.load();
      await background.save([theirs.single.copyWith(current: 50)]);
      expect(app.items.single.current, 0);

      await app.update('x', bumpEntry);
      expect(app.items.single.current, 51);
      expect((await open().load()).single.current, 51);
    });

    test('an entry that is gone is ignored', () async {
      final app = MediaStore(open(), covers: CoverService.disabled());
      await app.load();
      await app.update('nope', bumpEntry);
      expect(app.totalCount, 0);
    });
  });

  test('a failed update check is not counted, so the next launch tries again', () async {
    final svc = UpdateService(fetch: (_) async => null);
    final t = DateTime(2026, 10, 22, 9);
    expect(await svc.shouldAutoCheck(now: t), isTrue);
    await svc.forgetAutoCheck();
    expect(await svc.shouldAutoCheck(now: t.add(const Duration(minutes: 5))), isTrue);
    expect(await svc.shouldAutoCheck(now: t.add(const Duration(minutes: 10))), isFalse);
  });
}
