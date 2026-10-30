import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:faelen/core/theme.dart';
import 'package:faelen/features/vault/models/vault_item.dart';
import 'package:faelen/features/vault/screens/vault_screen.dart';
import 'package:faelen/features/vault/services/password_generator.dart';
import 'package:faelen/features/vault/services/pin_service.dart';
import 'package:faelen/features/vault/services/secure_bridge.dart';
import 'package:faelen/features/vault/services/vault_crypto.dart';
import 'package:faelen/features/vault/services/vault_storage.dart';
import 'package:faelen/features/vault/state/vault_store.dart';

class _Bio implements Biometrics {
  bool ok = true;
  int asked = 0;
  @override
  Future<bool> available() async => true;
  @override
  Future<bool> authenticate(String reason) async {
    asked++;
    return ok;
  }
}

class _Rig {
  _Rig({VaultStorage? storage, MemoryKv? kv, DateTime Function()? now})
      : kv = kv ?? MemoryKv(),
        storage = storage ?? MemoryVaultStorage(),
        bridge = FakeSecureBridge(),
        bio = _Bio() {
    pin = PinService(this.kv, now: now, iterations: 10);
    store = VaultStore(storage: this.storage, pin: pin, bridge: bridge, biometrics: bio, now: now);
  }
  final MemoryKv kv;
  final VaultStorage storage;
  final FakeSecureBridge bridge;
  final _Bio bio;
  late final PinService pin;
  late final VaultStore store;
}

/// A vault file that cannot be decrypted, like one copied over by a phone restore.
class _Unreadable implements VaultStorage {
  bool wiped = false;
  @override
  Future<String?> read() async => wiped ? null : throw const FormatException('The vault could not be decrypted');
  @override
  Future<void> write(String text) async {}
  @override
  Future<void> wipe() async => wiped = true;
}

VaultItem _login(String id, String title, {bool fav = false}) => VaultItem(
      id: id,
      section: VaultSection.logins,
      title: title,
      fields: const [VaultField('Username', 'me@mail.test'), VaultField('Password', 'Secret-123', secret: true)],
      updatedAt: DateTime(2026, 1, 1),
      favorite: fav,
    );

void vaultTest(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (t) async {
    final handle = t.ensureSemantics();
    try {
      await body(t);
    } finally {
      handle.dispose();
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('crypto', () {
    test('round trip, and the file bytes do not contain the text', () async {
      final crypto = VaultCrypto(MemoryKv());
      final bytes = await crypto.encrypt('{"password":"Secret-123"}');
      expect(utf8.decode(bytes, allowMalformed: true), isNot(contains('Secret-123')));
      expect(await crypto.decrypt(bytes), '{"password":"Secret-123"}');
    });

    test('a tampered file is refused', () async {
      final crypto = VaultCrypto(MemoryKv());
      final bytes = await crypto.encrypt('hello');
      bytes[bytes.length - 1] ^= 1;
      expect(() => crypto.decrypt(bytes), throwsFormatException);
    });

    test('another key cannot read it', () async {
      final bytes = await VaultCrypto(MemoryKv()).encrypt('hello');
      expect(() => VaultCrypto(MemoryKv()).decrypt(bytes), throwsFormatException);
    });

    test('file storage writes encrypted bytes and reads them back', () async {
      final dir = await Directory.systemTemp.createTemp('vault_test');
      addTearDown(() => dir.delete(recursive: true));
      final s = FileVaultStorage(VaultCrypto(MemoryKv()), dir: () async => dir);
      expect(await s.read(), isNull);
      await s.write('{"a":"Secret-123"}');
      expect(await File('${dir.path}/vault.enc').readAsString().catchError((_) => ''), isNot(contains('Secret-123')));
      expect(await s.read(), '{"a":"Secret-123"}');
    });
  });

  group('review fixes', () {
    test('two saves started together both land, in order, on a fresh key', () async {
      final dir = await Directory.systemTemp.createTemp('vault_race');
      addTearDown(() => dir.delete(recursive: true));
      final kv = MemoryKv();
      final storage = FileVaultStorage(VaultCrypto(kv), dir: () async => dir);
      final r = _Rig(storage: storage, kv: kv);
      await r.store.setUp('123456');
      await Future.wait([r.store.add(_login('1', 'A')), r.store.add(_login('2', 'B')), r.store.toggleFavorite(_login('1', 'A'))]);
      expect(r.store.saveError, isNull);
      final again = _Rig(storage: FileVaultStorage(VaultCrypto(kv), dir: () async => dir), kv: kv);
      await again.store.unlockWithPin('123456');
      expect(again.store.loadError, isNull);
      expect(again.store.items.map((i) => i.title).toSet(), {'A', 'B'});
    });

    test('a change right before a lock is still saved', () async {
      final r = _Rig();
      await r.store.setUp('123456');
      final saving = r.store.add(_login('1', 'A'));
      r.store.lock();
      await saving;
      await r.store.unlockWithPin('123456');
      expect(r.store.items.single.title, 'A');
    });

    test('Undo after the vault locked does not leak an entry into memory', () async {
      final r = _Rig();
      await r.store.setUp('123456');
      r.store.lock();
      await r.store.add(_login('1', 'A'));
      expect(r.store.items, isEmpty);
    });

    test('a vault file this phone cannot read is cleared when a new PIN is made', () async {
      final bad = _Unreadable();
      final rig = _Rig(storage: bad);
      await rig.store.setUp('123456');
      expect(bad.wiped, isTrue);
      expect(rig.store.loadError, isNull);
    });

    test('PIN from the earlier two-key format still works', () async {
      final kv = MemoryKv();
      final old = PinService(kv, iterations: 10);
      await old.setPin('123456');
      // Rewrite as the old build stored it.
      final v = kv.data.remove('vault_pin_v2')!;
      kv.data['vault_pin_salt_v1'] = v.split('.').first;
      kv.data['vault_pin_hash_v1'] = v.split('.').last;
      expect(await old.hasPin(), isTrue);
      expect((await old.check('123456')).outcome, PinOutcome.ok);
      expect((await old.check('000000')).outcome, PinOutcome.wrong);
    });
  });

  group('PIN', () {
    test('right PIN opens, wrong PIN counts down, then locks with growing waits', () async {
      var t = DateTime(2026, 1, 1, 12);
      final pin = PinService(MemoryKv(), now: () => t, iterations: 10);
      await pin.setPin('123456');
      expect((await pin.check('123456')).outcome, PinOutcome.ok);
      final first = await pin.check('000000');
      expect(first.outcome, PinOutcome.wrong);
      expect(first.triesLeft, 4);
      for (var i = 0; i < 3; i++) {
        await pin.check('000000');
      }
      final locked = await pin.check('000000'); // the 5th wrong try
      expect(locked.outcome, PinOutcome.locked);
      expect(locked.wait, const Duration(seconds: 30));
      // Even the right PIN is refused while locked.
      expect((await pin.check('123456')).outcome, PinOutcome.locked);
      t = t.add(const Duration(seconds: 31));
      expect((await pin.check('000000')).wait, const Duration(minutes: 1));
      t = t.add(const Duration(minutes: 2));
      expect((await pin.check('123456')).outcome, PinOutcome.ok);
      expect(await pin.lockedFor(), Duration.zero);
    });

    test('the PIN itself is never stored', () async {
      final kv = MemoryKv();
      await PinService(kv, iterations: 10).setPin('654321');
      expect(kv.data.values.any((v) => v.contains('654321')), isFalse);
    });
  });

  group('store', () {
    test('first run asks for a PIN, then data survives lock and unlock', () async {
      final r = _Rig();
      await r.store.init();
      expect(r.store.status, VaultStatus.needsSetup);
      await r.store.setUp('123456');
      expect(r.store.status, VaultStatus.unlocked);
      await r.store.add(_login('1', 'Netflix'));
      r.store.lock();
      expect(r.store.status, VaultStatus.locked);
      expect(r.store.items, isEmpty); // nothing kept in memory while locked
      expect(r.bridge.clears, 1);
      expect((await r.store.unlockWithPin('000000')).outcome, PinOutcome.wrong);
      expect(r.store.status, VaultStatus.locked);
      expect((await r.store.unlockWithPin('123456')).outcome, PinOutcome.ok);
      expect(r.store.items.single.title, 'Netflix');
      expect(r.store.items.single.field('Password')?.value, 'Secret-123');
    });

    test('a new store over the same files unlocks with the same PIN', () async {
      final a = _Rig();
      await a.store.init();
      await a.store.setUp('123456');
      await a.store.add(_login('1', 'Netflix'));
      final b = _Rig(storage: a.storage, kv: a.kv);
      await b.store.init();
      expect(b.store.status, VaultStatus.locked);
      await b.store.unlockWithPin('123456');
      expect(b.store.items.single.title, 'Netflix');
    });

    test('fingerprint opens it only when it was turned on', () async {
      final r = _Rig();
      await r.store.init();
      await r.store.setUp('123456', useBiometric: true);
      r.store.lock();
      expect(await r.store.unlockWithBiometric(), isTrue);
      r.store.lock();
      r.bio.ok = false;
      expect(await r.store.unlockWithBiometric(), isFalse);
      expect(r.store.status, VaultStatus.locked);
    });

    test('a damaged file blocks saving instead of being overwritten', () async {
      final storage = _BrokenStorage();
      final r = _Rig(storage: storage);
      await r.store.init();
      await r.store.setUp('123456');
      expect(r.store.loadError, isNotNull);
      await r.store.add(_login('1', 'Netflix'));
      expect(storage.writes, 0);
      expect(r.store.saveError, isNotNull);
    });

    test('copy marks secrets sensitive with a timed clear, plain fields not', () async {
      final r = _Rig();
      await r.store.init();
      await r.store.setUp('123456');
      final item = _login('1', 'Netflix');
      await r.store.copy(item.field('Password')!);
      await r.store.copy(item.field('Username')!);
      expect(r.bridge.copies[0].sensitive, isTrue);
      expect(r.bridge.copies[0].clearAfter, clipboardClear);
      expect(r.bridge.copies[1].sensitive, isFalse);
      expect(r.bridge.copies[1].clearAfter, isNull);
    });

    test('locks after the time limit in the background, not before', () async {
      var t = DateTime(2026, 1, 1, 12);
      final r = _Rig(now: () => t);
      await r.store.init();
      await r.store.setUp('123456');
      r.store.didChangeAppLifecycleState(AppLifecycleState.paused);
      t = t.add(const Duration(seconds: 10));
      r.store.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(r.store.status, VaultStatus.unlocked);
      r.store.didChangeAppLifecycleState(AppLifecycleState.paused);
      t = t.add(const Duration(seconds: 31));
      r.store.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(r.store.status, VaultStatus.locked);
    });

    test('an unreadable secure store shows an error instead of spinning or offering a new PIN', () async {
      final r = _Rig(kv: _ThrowingKv());
      await r.store.init();
      expect(r.store.status, VaultStatus.failed);
      expect(r.store.startError, isNotNull);
    });

    test('erase wipes the data and asks for a new PIN', () async {
      final r = _Rig();
      await r.store.init();
      await r.store.setUp('123456');
      await r.store.add(_login('1', 'Netflix'));
      await r.store.eraseEverything();
      expect(r.store.status, VaultStatus.needsSetup);
      expect(await r.storage.read(), isNull);
      await r.store.setUp('111111');
      expect(r.store.items, isEmpty);
    });
  });

  group('items', () {
    test('subtitle never shows a secret and IDs are masked', () {
      expect(_login('1', 'Netflix').subtitle, 'me@mail.test');
      final id = VaultItem(
        id: '2',
        section: VaultSection.ids,
        title: 'Passport',
        fields: const [VaultField('ID number', 'P1234567A', secret: true)],
        updatedAt: DateTime(2026),
      );
      expect(id.subtitle, isNot(contains('P12345')));
      expect(id.subtitle.endsWith('67A'), isTrue);
    });

    test('main field defaults per section and survives a JSON round trip', () {
      final back = VaultItem.fromJson(jsonDecode(jsonEncode(_login('1', 'Netflix', fav: true).toJson())))!;
      expect(back.mainField?.label, 'Password');
      expect(back.favorite, isTrue);
      expect(VaultItem.fromJson({'id': 1}), isNull);
      expect(VaultItem.fromJson({'id': 'x', 's': 'nope', 't': 'T'}), isNull);
    });

    test('expiry days count from today', () {
      final item = VaultItem(
        id: '3',
        section: VaultSection.ids,
        title: 'Passport',
        fields: const [],
        updatedAt: DateTime(2026),
        expiry: DateTime(2026, 3, 10),
      );
      expect(item.daysLeft(DateTime(2026, 3, 1, 23)), 9);
      expect(item.daysLeft(DateTime(2026, 3, 11)), -1);
    });

    test('generated passwords have every kind of character and no look-alikes', () {
      for (var i = 0; i < 50; i++) {
        final p = generatePassword(random: Random(i));
        expect(p.length, 16);
        expect(p, matches(RegExp(r'[a-z]')));
        expect(p, matches(RegExp(r'[A-Z]')));
        expect(p, matches(RegExp(r'[0-9]')));
        expect(p, matches(RegExp(r'[^A-Za-z0-9]')));
        expect(p, isNot(matches(RegExp(r'[Il1O0]'))));
      }
    });
  });

  group('screen', () {
    Future<_Rig> open(WidgetTester t, {Size size = const Size(360, 800), List<VaultItem> items = const []}) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final r = _Rig();
      // Real time, not the tester's fake clock: the PIN hash runs on a background isolate.
      await t.runAsync(() async {
        await r.store.init();
        await r.store.setUp('123456');
        for (final i in items) {
          await r.store.add(i);
        }
      });
      await t.pumpWidget(ChangeNotifierProvider<VaultStore>.value(
        value: r.store,
        child: MaterialApp(theme: buildTheme(Brightness.light), home: const VaultScreen()),
      ));
      await t.pump(const Duration(milliseconds: 100));
      return r;
    }

    vaultTest('PIN setup: six digits move to a confirm step, a mismatch starts over, a match opens the Vault', (t) async {
      t.view.physicalSize = const Size(360, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final r = _Rig();
      await t.pumpWidget(ChangeNotifierProvider<VaultStore>.value(
        value: r.store,
        child: MaterialApp(theme: buildTheme(Brightness.light), home: const VaultFlow()),
      ));
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('Choose a 6-digit PIN'), findsOneWidget);
      expect(find.text('Step 1 of 2'), findsOneWidget);

      Future<void> type(String digits) async {
        for (final d in digits.split('')) {
          await t.tap(find.bySemanticsLabel(d));
          await t.pump();
        }
        await t.pump(const Duration(milliseconds: 300));
      }

      await type('123456');
      expect(find.text('Confirm your PIN'), findsOneWidget);
      expect(find.text('Step 2 of 2'), findsOneWidget);
      expect(find.textContaining('same PIN again'), findsOneWidget);

      await type('111111'); // does not match
      expect(find.text('Choose a 6-digit PIN'), findsOneWidget);
      expect(find.textContaining('did not match'), findsOneWidget);

      await type('123456');
      await type('123456');
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
      await t.pump();
      expect(r.store.status, VaultStatus.unlocked);
      expect(find.text('Vault'), findsOneWidget);
      await t.pump(const Duration(seconds: 1));
    });

    vaultTest('leave the Vault and come back: the same PIN opens it and the entry is still there', (t) async {
      t.view.physicalSize = const Size(360, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final r = _Rig();
      await t.pumpWidget(ChangeNotifierProvider<VaultStore>.value(
        value: r.store,
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Builder(
            builder: (c) => Scaffold(
              body: Center(child: TextButton(onPressed: () => Navigator.push(c, MaterialPageRoute<void>(builder: (_) => const VaultFlow())), child: const Text('open vault'))),
            ),
          ),
        ),
      ));

      Future<void> type(String digits) async {
        for (final d in digits.split('')) {
          await t.tap(find.bySemanticsLabel(d));
          await t.pump();
        }
        await t.pump(const Duration(milliseconds: 300));
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
        await t.pump(const Duration(milliseconds: 300));
      }

      await t.tap(find.text('open vault'));
      await t.pumpAndSettle();
      await type('482915');
      await type('482915');
      expect(r.store.status, VaultStatus.unlocked);
      await t.runAsync(() => r.store.add(_login('1', 'facebook')));
      await t.pump();

      await t.tap(find.byTooltip('Back')); // leave the Vault
      await t.pumpAndSettle();
      await t.pump(const Duration(milliseconds: 100));
      expect(r.store.status, VaultStatus.locked);

      r.bio.ok = false; // like a PC with no fingerprint reader: only the PIN can open it
      await t.tap(find.text('open vault')); // and come back
      await t.pumpAndSettle();
      expect(find.text('Enter your PIN'), findsOneWidget);
      await type('482915');
      expect(find.textContaining('Wrong PIN'), findsNothing);
      expect(r.store.status, VaultStatus.unlocked);
      expect(find.text('facebook'), findsOneWidget);
    });

    vaultTest('add form: generate shows strength, Save stores the login, Cancel stores nothing', (t) async {
      final r = await open(t);
      await t.tap(find.bySemanticsLabel('Add'));
      await t.pumpAndSettle();
      expect(find.text('Add login'), findsOneWidget);
      expect(find.text('Generate'), findsOneWidget);

      await t.tap(find.text('Save')); // empty name is refused
      await t.pump();
      expect(find.text('Give it a name'), findsOneWidget);

      await t.enterText(find.widgetWithText(TextFormField, 'Netflix').first, 'Netflix');
      await t.enterText(find.widgetWithText(TextFormField, 'you@mail.com'), 'me@mail.test');
      await t.tap(find.text('Generate'));
      await t.pump();
      expect(find.text('Strong'), findsOneWidget); // generated passwords always score full
      expect(t.takeException(), isNull);

      await t.tap(find.text('Add a link or notes'));
      await t.pump();
      expect(find.text('Link'), findsOneWidget);

      await t.runAsync(() async {
        await t.tap(find.text('Save'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await t.pumpAndSettle();
      final saved = r.store.items.single;
      expect(saved.title, 'Netflix');
      expect(saved.field('Username')?.value, 'me@mail.test');
      expect(saved.field('Password')?.value.length, 16);
      expect(saved.field('Password')?.secret, isTrue);
    });

    vaultTest('ID form: type chips fill the name and expiry shortcuts set a date', (t) async {
      final r = await open(t);
      await t.tap(find.bySemanticsLabel('IDs'));
      await t.pump();
      await t.tap(find.bySemanticsLabel('Add'));
      await t.pumpAndSettle();
      await t.tap(find.descendant(of: find.byType(Wrap).first, matching: find.text('Passport')));
      await t.pump();
      await t.ensureVisible(find.text('In 5 years'));
      await t.pump();
      await t.tap(find.text('In 5 years'));
      await t.pump();
      await t.ensureVisible(find.widgetWithText(TextFormField, 'As printed on the ID'));
      await t.enterText(find.widgetWithText(TextFormField, 'As printed on the ID'), 'P1234567A');
      await t.runAsync(() async {
        await t.tap(find.text('Save'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await t.pumpAndSettle();
      final id = r.store.items.single;
      expect(id.title, 'Passport');
      expect(id.expiry!.year, DateTime.now().year + 5);
      expect(id.field('ID number')?.secret, isTrue);
    });

    vaultTest('empty section offers to add', (t) async {
      await open(t);
      expect(find.text('No logins yet'), findsOneWidget);
      expect(find.text('Add a login'), findsOneWidget);
    });

    vaultTest('the main Copy button copies the password as sensitive and shows the timer state', (t) async {
      final r = await open(t, items: [_login('1', 'Netflix')]);
      await t.tap(find.bySemanticsLabel('Copy password for Netflix'));
      await t.pump();
      expect(r.bridge.copies.single.text, 'Secret-123');
      expect(r.bridge.copies.single.sensitive, isTrue);
      expect(find.bySemanticsLabel('Copied password for Netflix'), findsOneWidget);
      await t.pump(clipboardClear + const Duration(seconds: 1)); // back to normal, no pending timers
      expect(find.bySemanticsLabel('Copy password for Netflix'), findsOneWidget);
    });

    vaultTest('an open row masks secrets until the eye is tapped; copy needs no reveal', (t) async {
      final r = await open(t, items: [_login('1', 'Netflix')]);
      await t.tap(find.text('Netflix'));
      await t.pump();
      expect(find.text('Secret-123'), findsNothing);
      expect(find.text('••••••••'), findsOneWidget);
      await t.tap(find.bySemanticsLabel('Copy password for Netflix').last);
      await t.pump();
      expect(r.bridge.copies.last.text, 'Secret-123');
      await t.tap(find.bySemanticsLabel('Show password'));
      await t.pump();
      expect(find.text('Secret-123'), findsOneWidget);
      await t.pump(const Duration(seconds: 31)); // the eye re-hides itself, copy state ends
      expect(find.text('Secret-123'), findsNothing);
    });

    vaultTest('pinned entries appear in the Favorites strip and copy in one tap', (t) async {
      final r = await open(t, items: [_login('1', 'Netflix', fav: true)]);
      expect(find.bySemanticsLabel('Copy password for Netflix'), findsNWidgets(2)); // chip + row button
      await t.tap(find.bySemanticsLabel('Copy password for Netflix').first);
      await t.pump();
      expect(r.bridge.copies.single.text, 'Secret-123');
      await t.pump(clipboardClear + const Duration(seconds: 1));
    });

    vaultTest('search looks at titles only, never at secrets', (t) async {
      await open(t, items: [_login('1', 'Netflix'), _login('2', 'Bank')]);
      await t.tap(find.byTooltip('Search'));
      await t.pump();
      await t.enterText(find.byType(TextField), 'Secret');
      await t.pump();
      expect(find.text('No match'), findsOneWidget);
      await t.enterText(find.byType(TextField), 'bank');
      await t.pump();
      expect(find.text('Bank'), findsOneWidget);
      expect(find.text('Netflix'), findsNothing);
    });

    vaultTest('fits 360x640 with large text and no overflow', (t) async {
      t.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await open(t, size: const Size(360, 640), items: [_login('1', 'A very long site name that keeps going', fav: true)]);
      await t.tap(find.text('A very long site name that keeps going').last);
      await t.pump();
      expect(t.takeException(), isNull);
    });
  });
}

class _BrokenStorage implements VaultStorage {
  int writes = 0;
  @override
  Future<String?> read() async => throw const FormatException('The vault could not be decrypted');
  @override
  Future<void> write(String text) async => writes++;
  @override
  Future<void> wipe() async {}
}

class _ThrowingKv extends MemoryKv {
  @override
  Future<String?> read(String key) async => throw StateError('no secure storage');
}
