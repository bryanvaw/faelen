import 'dart:convert';

import 'package:faelen/features/media/models/media_entry.dart';
import 'package:faelen/features/media/services/cover_service.dart';
import 'package:faelen/features/media/services/release_reminders.dart';
import 'package:faelen/features/media/services/storage_service.dart';
import 'package:faelen/features/media/state/media_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

MediaStore newStore() => MediaStore(StorageService(), covers: CoverService.disabled());

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('loading damaged data', () {
    test('one bad entry is skipped, the rest load, and a notice is shown', () async {
      SharedPreferences.setMockInitialValues({
        'media_entries_v1': jsonEncode([
          {'id': '1', 'title': 'Good'},
          {'id': '2'}, // no title
          {'id': '3', 'title': 'Also good'},
        ]),
      });
      final s = newStore();
      await s.load();
      expect(s.items.map((e) => e.id), ['1', '3']);
      expect(s.notice, contains('1 entry'));
      // The original text is parked, not lost.
      expect((await SharedPreferences.getInstance()).getString('media_entries_corrupt_v1'), isNotNull);
    });

    test('an unreadable list falls back to the copy from before the last write', () async {
      final a = newStore();
      await a.load();
      await a.save(const MediaEntry(id: '1', title: 'One'));
      await a.save(const MediaEntry(id: '2', title: 'Two')); // the first list is now the previous copy
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('media_entries_v1', '{not json');

      final b = newStore();
      await b.load();
      expect(b.items.map((e) => e.id), ['1']);
      expect(b.notice, contains('previous saved copy'));
      expect(prefs.getString('media_entries_corrupt_v1'), '{not json');
    });

    test('saving after a bad load keeps the previous copy', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('media_entries_v1', jsonEncode([{'id': '9'}]));
      final s = newStore();
      await s.load();
      await s.save(const MediaEntry(id: '1', title: 'New'));
      expect(prefs.getString('media_entries_prev_v1'), contains('"id":"9"'));
    });
  });

  group('delete with undo', () {
    test('softDelete removes, restore brings the entry back unchanged', () async {
      final s = newStore();
      await s.load();
      await s.save(const MediaEntry(id: '1', title: 'One', current: 4));
      final removed = await s.softDelete('1');
      expect(s.totalCount, 0);
      await s.restore(removed!);
      expect(s.items.single.current, 4);
      final again = newStore();
      await again.load();
      expect(again.totalCount, 1);
    });
  });

  test('rapid saves all land, in order', () async {
    final s = newStore();
    await s.load();
    final writes = [for (var i = 1; i <= 20; i++) s.save(MediaEntry(id: 'a', title: 'A', current: i))];
    await Future.wait(writes);
    final again = newStore();
    await again.load();
    expect(again.items.single.current, 20);
  });

  group('new sorts', () {
    test('progress puts the furthest along first; added puts the newest id first', () async {
      final s = newStore();
      await s.load();
      await s.save(const MediaEntry(id: 'x', title: 'Low', current: 1, total: 10));
      await s.save(const MediaEntry(id: 'y', title: 'High', current: 9, total: 10));
      await s.setSort(MediaSort.progress);
      expect(s.visible.map((e) => e.title), ['High', 'Low']);

      final older = newId();
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final newer = newId();
      final t = MediaStore(StorageService(), covers: CoverService.disabled());
      await t.load();
      await t.save(MediaEntry(id: older, title: 'Older'));
      await t.save(MediaEntry(id: newer, title: 'Newer'));
      await t.setSort(MediaSort.added);
      expect(t.visible.first.title, 'Newer');
    });
  });

  test('reminder plan uses the chosen default time', () {
    final e = MediaEntry(
      id: '1',
      title: 'Show',
      status: Status.watching,
      releaseDays: const [3],
      releasedCount: 1,
      releasedOn: DateTime(2026, 10, 13).millisecondsSinceEpoch,
    );
    final plan = ReleaseReminders.plan([e], DateTime(2026, 10, 13), defaultMinutes: 20 * 60 + 30);
    expect(plan.single.minutes, 20 * 60 + 30);
  });
}
