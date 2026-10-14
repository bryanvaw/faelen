import 'package:flutter_test/flutter_test.dart';
import 'package:media_tracker_flutter/models/media_entry.dart';
import 'package:media_tracker_flutter/services/storage_service.dart';
import 'package:media_tracker_flutter/state/media_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('add, edit and delete persist across store instances', () async {
    final a = MediaStore(StorageService());
    await a.load();
    const e = MediaEntry(id: '1', title: 'Hello, "World"', type: MediaType.drama, current: 3, total: 16, notes: 'a\nb');
    await a.save(e);
    await a.save(MediaEntry(id: '1', title: e.title, type: e.type, current: 4, total: 16, notes: e.notes));

    final b = MediaStore(StorageService());
    await b.load();
    expect(b.totalCount, 1);
    expect(b.visible.single.current, 4);
    expect(b.visible.single.title, 'Hello, "World"');

    await b.delete('1');
    final c = MediaStore(StorageService());
    await c.load();
    expect(c.totalCount, 0);
  });

  test('filters by keyword, type and status', () async {
    final s = MediaStore(StorageService());
    await s.load();
    await s.save(const MediaEntry(id: '1', title: 'Solo Leveling', type: MediaType.manhwa, status: Status.watching));
    await s.save(const MediaEntry(id: '2', title: 'Solo Camping', type: MediaType.anime));
    s.setQuery('solo');
    expect(s.visible.length, 2);
    s.setType(MediaType.manhwa);
    expect(s.visible.single.id, '1');
    s.setType(null);
    s.setStatus(Status.planToWatch);
    expect(s.visible.single.id, '2');
  });
}
