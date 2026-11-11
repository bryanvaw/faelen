import 'dart:convert';
import 'dart:typed_data';

import 'package:faelen/core/settings_store.dart';
import 'package:faelen/features/budget/models/budget_models.dart';
import 'package:faelen/features/budget/services/budget_repo.dart';
import 'package:faelen/features/budget/services/statement_import.dart';
import 'package:faelen/features/budget/state/budget_store.dart';
import 'package:faelen/features/media/models/media_entry.dart';
import 'package:faelen/features/media/services/cover_service.dart';
import 'package:faelen/features/media/services/link_preview_service.dart';
import 'package:faelen/features/media/services/storage_service.dart';
import 'package:faelen/features/media/state/media_store.dart';
import 'package:faelen/features/planner/models/task.dart';
import 'package:faelen/features/planner/services/planner_repo.dart';
import 'package:faelen/features/planner/services/task_reminders.dart';
import 'package:faelen/features/planner/state/planner_store.dart';
import 'package:faelen/features/settings/backup_service.dart';
import 'package:faelen/features/vault/services/pin_service.dart';
import 'package:faelen/features/vault/services/secure_bridge.dart';
import 'package:faelen/features/vault/services/vault_backup.dart';
import 'package:faelen/features/vault/services/vault_crypto.dart';
import 'package:faelen/features/vault/services/vault_storage.dart';
import 'package:faelen/features/vault/state/vault_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fixes from the second read-through of the whole project (2026-11-11).

class _NoBio implements Biometrics {
  @override
  Future<bool> available() async => false;
  @override
  Future<bool> authenticate(String reason) async => false;
}

Future<MediaStore> _media() async {
  final s = MediaStore(StorageService(), covers: CoverService.disabled());
  await s.load();
  return s;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('vault', () {
    test('reading with a missing key fails and never makes a new key', () async {
      final kv = MemoryKv();
      final bytes = await VaultCrypto(kv).encrypt('{"v":1,"items":[]}');
      final lost = MemoryKv(); // the Keystore answers "nothing saved"
      await expectLater(VaultCrypto(lost).decrypt(bytes), throwsFormatException);
      expect(lost.data, isEmpty);
      expect(await VaultCrypto(kv).decrypt(bytes), '{"v":1,"items":[]}');
    });

    test('entries this build cannot read are written back, not dropped', () async {
      final storage = MemoryVaultStorage()
        ..text = jsonEncode({
          'v': 1,
          'items': [
            {'id': 'future', 's': 'shots', 't': 'A kind from a newer Faelen', 'f': []},
            {'id': 'ok', 's': 'logins', 't': 'Mail', 'f': [], 'u': 1},
          ],
        });
      final store = VaultStore(storage: storage, pin: PinService(MemoryKv(), iterations: 10), bridge: FakeSecureBridge(), biometrics: _NoBio());
      await store.setUp('123456');
      expect(store.items.map((i) => i.id), ['ok']);
      await store.remove('ok');
      final saved = (jsonDecode(storage.text!) as Map)['items'] as List;
      expect(saved.map((j) => (j as Map)['id']), ['future']);
      expect(store.backupText(), contains('future'));
      store.dispose();
    });

    test('a backup still opens after the key stretching moved off the main thread', () async {
      final b = VaultBackup(iterations: 10);
      final file = await b.encrypt('{"v":1,"items":[]}', 'correct horse');
      expect(await b.decrypt(file, 'correct horse'), '{"v":1,"items":[]}');
      await expectLater(b.decrypt(file, 'wrong horse'), throwsFormatException);
    });
  });

  group('budget', () {
    test('undo after deleting a card brings its bills back', () async {
      final repo = MemoryBudgetRepo();
      final s = BudgetStore(repo);
      await s.load();
      await s.saveAccount(const Account(id: 'a', name: 'Main'));
      await s.saveBill(const Bill(id: 'rent', name: 'Rent', cents: 500000, category: 'bills', accountId: 'a', day: 28), now: DateTime(2026, 11, 11));
      final gone = (await s.deleteAccount('a'))!;
      expect(s.bills, isEmpty);
      expect(gone.bills.single.id, 'rent');
      await s.restoreAccount(gone.account, gone.txns, bills: gone.bills);
      expect(s.bills.single.id, 'rent');
      expect((await repo.load()).bills.single.id, 'rent');
    });

    test('a "Debit/Credit" column beside Amount says the direction; it is not two amount columns', () {
      final t = StatementTable.parse('Date,Description,Debit/Credit,Amount\n2026-11-03,Jollibee,Debit,250.00\n2026-11-04,Salary,Credit,"30,000.00"\n');
      final map = t.guess!;
      expect(map.moneyIn, isNull);
      expect(t.headers[map.amount], 'Amount');
      expect(t.headers[map.type!], 'Debit/Credit');
      final rows = t.rows(map);
      expect(rows.map((r) => (r.cents, r.income)), [(25000, false), (3000000, true)]);
    });
  });

  group('backup', () {
    test('goals and limits are exported even with no card', () async {
      final budget = BudgetStore(MemoryBudgetRepo());
      await budget.load();
      await budget.saveGoal(const Goal(id: 'g', name: 'Laptop', targetCents: 5000000));
      final json = await BackupService().build(await _media(), budget: budget);
      expect(((jsonDecode(json) as Map)['budget'] as Map)['goals'], hasLength(1));
    });

    test('a file with a bad section changes nothing, not even the media list', () async {
      final media = await _media();
      await media.save(const MediaEntry(id: 'keep', title: 'Keep me'));
      final budget = BudgetStore(MemoryBudgetRepo());
      await budget.load();
      final planner = PlannerStore(MemoryPlannerRepo());
      await planner.load();
      for (final bad in [
        {'budget': 'nope'},
        {'planner': 'nope'},
      ]) {
        final file = jsonEncode({'app': 'faelen', 'version': 1, 'media': <Object>[], ...bad});
        await expectLater(BackupService().restore(file, media, budget: budget, planner: planner, replace: true), throwsFormatException);
        expect(media.items.single.id, 'keep');
      }
    });
  });

  group('planner', () {
    Task task({required DateTime due, Repeat repeat = Repeat.none, bool remind = true, int minutes = -1}) =>
        Task(id: 't', title: 'Pay rent', due: due, repeat: repeat, remind: remind, minutes: minutes, createdAt: DateTime(2026), updatedAt: DateTime(2026));

    test('a monthly task on the 31st goes back to the 31st after February', () async {
      var now = DateTime(2026, 1, 31, 10);
      final repo = MemoryPlannerRepo();
      await repo.put(task(due: DateTime(2026, 1, 31), repeat: Repeat.monthly));
      final s = PlannerStore(repo, now: () => now);
      await s.load();
      await s.toggle(s.tasks.single);
      expect(s.tasks.single.due, DateTime(2026, 2, 28));
      now = DateTime(2026, 2, 28, 10);
      await s.toggle(s.tasks.single);
      expect(s.tasks.single.due, DateTime(2026, 3, 31));
      // The day survives a save and a reload.
      expect(Task.fromJson(s.tasks.single.toJson())!.monthDay, 31);
    });

    test('a repeating reminder is planned for its coming dates, not only the next one', () {
      final now = DateTime(2026, 11, 4, 10);
      final daily = TaskReminders.plan([task(due: DateTime(2026, 11, 4), repeat: Repeat.daily, minutes: 8 * 60)], now);
      expect(daily.length, 7);
      expect(daily.first.when, DateTime(2026, 11, 5, 8)); // today's 8:00 has passed
      expect(daily.last.when, DateTime(2026, 11, 11, 8));

      // Not ticked off for three weeks: it still reminds from today on.
      final late = TaskReminders.plan([task(due: DateTime(2026, 10, 14), repeat: Repeat.weekly)], now);
      expect(late.map((r) => r.when), [DateTime(2026, 11, 11, 9), DateTime(2026, 11, 18, 9), DateTime(2026, 11, 25, 9), DateTime(2026, 12, 2, 9)]);

      final once = TaskReminders.plan([task(due: DateTime(2026, 11, 6))], now);
      expect(once.single.when, DateTime(2026, 11, 6, 9));
    });
  });

  test('settings say when they have been read, so nothing acts on the defaults', () async {
    SharedPreferences.setMockInitialValues({'release_reminders_v1': true});
    final s = SettingsStore();
    expect(s.loaded, isFalse);
    await s.load();
    expect(s.loaded, isTrue);
    expect(s.releaseReminders, isTrue);
  });

  group('link lookup', () {
    final page = Uri.parse('https://site.example/series/solo-leveling/chapter-1');

    test('a % in the address does not break the title', () {
      expect(LinkPreviewService.titleFromUrl(Uri.parse('https://site.example/read/100%25-orange-juice/chapter-1')), '100% Orange Juice');
    });

    test('an id in the address is skipped for the title after it', () {
      expect(LinkPreviewService.titleFromUrl(Uri.parse('https://mangadex.org/title/32d76d19-8a05-4db0-9fc2-e0b0648fe9d0/solo-leveling')), 'Solo Leveling');
    });

    test('covers are also found in structured data, link tags and unquoted attributes', () {
      const html = '''
<html><head><title>Solo Leveling - Site</title>
<meta property=og:image content=https://cdn.example/a.jpg>
<link rel="image_src" href="/img/b.jpg">
<script type="application/ld+json">{"@context":"https://schema.org","@graph":[{"@type":"ComicSeries","name":"Solo Leveling","image":{"@type":"ImageObject","url":"https://cdn.example/c.jpg"},"thumbnailUrl":["https://cdn.example/d.jpg"]}]}</script>
</head></html>''';
      final found = LinkPreviewService.parse(html, page)!;
      expect(found.images.map((u) => u.toString()), ['https://cdn.example/a.jpg', 'https://site.example/img/b.jpg', 'https://cdn.example/c.jpg', 'https://cdn.example/d.jpg']);
      expect(found.imageUrl.toString(), 'https://cdn.example/a.jpg');
    });

    test('a folder named "default" is fine; a file named default, logo or no-image is not a cover', () {
      LinkPreview p(String image) => LinkPreviewService.parse('<title>Solo Leveling</title><meta property="og:image" content="$image">', page)!;
      expect(p('https://cdn.example/uploads/default/solo-leveling.jpg').images, hasLength(1));
      expect(p('https://cdn.example/img/default-cover.png').images, isEmpty);
      expect(p('https://cdn.example/img/no-image.png').images, isEmpty);
      expect(p('https://cdn.example/site-logo.png').images, isEmpty);
    });

    test('a picture is judged by its bytes, not its label', () {
      expect(LinkPreviewService.looksLikeImage(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0])), isTrue);
      expect(LinkPreviewService.looksLikeImage(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D])), isTrue);
      expect(LinkPreviewService.looksLikeImage(Uint8List.fromList([...'RIFF'.codeUnits, 0, 0, 0, 0, ...'WEBP'.codeUnits])), isTrue);
      expect(LinkPreviewService.looksLikeImage(utf8.encode('<!DOCTYPE html><html>Access denied')), isFalse);
      expect(LinkPreviewService.looksLikeImage(Uint8List.fromList([0, 0, 0, 0x1C, ...'ftypavif'.codeUnits])), isFalse);
      expect(LinkPreviewService.looksLikeImage(Uint8List(0)), isFalse);
    });

    test('a catalogue is searched by the title, then without its season', () {
      expect(LinkPreviewService.searchTitles('Solo Leveling Season 2 (2026)'), ['Solo Leveling Season 2', 'Solo Leveling']);
      expect(LinkPreviewService.searchTitles('Vinland Saga 2nd Season'), ['Vinland Saga 2nd Season', 'Vinland Saga']);
      expect(LinkPreviewService.searchTitles('Make Me Tingle (2026)'), ['Make Me Tingle']);
    });
  });
}
