import 'dart:io';
import 'dart:typed_data';

import 'package:faelen/core/settings_store.dart';
import 'package:faelen/features/media/models/media_entry.dart';
import 'package:faelen/features/media/services/cover_service.dart';
import 'package:faelen/features/media/services/storage_service.dart';
import 'package:faelen/features/media/state/media_store.dart';
import 'package:faelen/features/settings/backup_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<MediaStore> newStore({CoverService? covers}) async {
  final s = MediaStore(StorageService(), covers: covers);
  await s.load();
  return s;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('sorting', () {
    Future<MediaStore> seeded() async {
      final s = await newStore();
      await s.save(const MediaEntry(id: 'a', title: 'Banana', rating: 4));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await s.save(const MediaEntry(id: 'b', title: 'Apple', rating: 10));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await s.save(const MediaEntry(id: 'c', title: 'Cherry')); // unrated
      return s;
    }

    test('title, recently updated, rating', () async {
      final s = await seeded();
      expect(s.visible.map((e) => e.id), ['b', 'a', 'c']); // A-Z
      await s.setSort(MediaSort.updated);
      expect(s.visible.map((e) => e.id), ['c', 'b', 'a']);
      await s.setSort(MediaSort.rating);
      expect(s.visible.map((e) => e.id), ['b', 'a', 'c']); // unrated last
    });

    test('editing moves an entry to the top of recently updated', () async {
      final s = await seeded();
      await s.setSort(MediaSort.updated);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await s.save(s.visible.last.copyWith(current: 1)); // 'a'
      expect(s.visible.first.id, 'a');
    });

    test('sort choice is remembered', () async {
      final s = await seeded();
      await s.setSort(MediaSort.rating);
      final again = await newStore();
      expect(again.sort, MediaSort.rating);
    });
  });

  group('backup', () {
    test('export then replace-import restores everything, including covers', () async {
      final dir = await Directory.systemTemp.createTemp('faelen_covers');
      addTearDown(() => dir.delete(recursive: true));
      final covers = CoverService.inDirectory(dir);
      final a = await newStore(covers: covers);
      final name = await covers.saveBytes('x', Uint8List.fromList([1, 2, 3, 4]));
      await a.save(MediaEntry(id: 'x', title: 'With cover', rating: 7, current: 2, total: 12, cover: name));
      await a.save(const MediaEntry(id: 'y', title: 'No cover', type: MediaType.movie));

      final json = await BackupService().build(a, now: DateTime.utc(2026, 10, 15));
      expect(json, contains('"app": "faelen"'));

      SharedPreferences.setMockInitialValues({});
      final dir2 = await Directory.systemTemp.createTemp('faelen_covers2');
      addTearDown(() => dir2.delete(recursive: true));
      final b = await newStore(covers: CoverService.inDirectory(dir2));
      await b.save(const MediaEntry(id: 'old', title: 'Will be replaced'));
      final n = await BackupService().restore(json, b, replace: true);

      expect(n, 2);
      expect(b.totalCount, 2);
      final x = b.visible.firstWhere((e) => e.id == 'x');
      expect(x.rating, 7);
      expect(x.total, 12);
      expect(await b.covers.readBytes(x.cover), [1, 2, 3, 4]);
      expect(b.visible.any((e) => e.id == 'old'), isFalse);
    });

    test('merge keeps the more recently updated copy', () async {
      final s = await newStore();
      await s.save(const MediaEntry(id: '1', title: 'Local', current: 5));
      final localTime = s.visible.single.updatedAt;
      final json = '{"app":"faelen","version":1,"media":['
          '{"id":"1","title":"Older","updatedAt":${localTime - 1000}},'
          '{"id":"2","title":"New one","updatedAt":1}]}';
      await BackupService().restore(json, s, replace: false);
      expect(s.totalCount, 2);
      expect(s.visible.firstWhere((e) => e.id == '1').title, 'Local');

      final newer = '{"app":"faelen","version":1,"media":[{"id":"1","title":"Newer","updatedAt":${localTime + 1000}}]}';
      await BackupService().restore(newer, s, replace: false);
      expect(s.visible.firstWhere((e) => e.id == '1').title, 'Newer');
    });

    test('rejects bad files without touching data', () async {
      final s = await newStore();
      await s.save(const MediaEntry(id: '1', title: 'Keep me'));
      for (final bad in ['not json', '[]', '{"app":"other","version":1,"media":[]}', '{"app":"faelen","version":99,"media":[]}', '{"app":"faelen","version":1}', '{"app":"faelen","version":1,"media":[5]}']) {
        await expectLater(BackupService().restore(bad, s, replace: true), throwsFormatException, reason: bad);
      }
      expect(s.totalCount, 1);
    });
  });

  test('theme choice persists', () async {
    final a = SettingsStore();
    await a.load();
    expect(a.themeMode, ThemeMode.system);
    await a.setThemeMode(ThemeMode.dark);
    final b = SettingsStore();
    await b.load();
    expect(b.themeMode, ThemeMode.dark);
  });
}
