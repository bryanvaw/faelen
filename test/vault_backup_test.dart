import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:faelen/features/vault/models/vault_item.dart';
import 'package:faelen/features/vault/services/pin_service.dart';
import 'package:faelen/features/vault/services/secure_bridge.dart';
import 'package:faelen/features/vault/services/vault_backup.dart';
import 'package:faelen/features/vault/services/vault_crypto.dart';
import 'package:faelen/features/vault/services/vault_storage.dart';
import 'package:faelen/features/vault/state/vault_store.dart';

class _Bio implements Biometrics {
  @override
  Future<bool> available() async => false;
  @override
  Future<bool> authenticate(String reason) async => false;
}

Future<VaultStore> _open() async {
  SharedPreferences.setMockInitialValues({});
  final s = VaultStore(
    storage: MemoryVaultStorage(),
    pin: PinService(MemoryKv(), iterations: 10),
    bridge: FakeSecureBridge(),
    biometrics: _Bio(),
  );
  await s.init();
  await s.setUp('123456');
  return s;
}

VaultItem _item(String id, String title, DateTime at) => VaultItem(
  id: id,
  section: VaultSection.logins,
  title: title,
  fields: [VaultField('Password', 'pw-secret', secret: true)],
  updatedAt: at,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final b = VaultBackup(iterations: 10);

  test('round trip, and the file hides the content', () async {
    final file = await b.encrypt('{"v":1,"items":[]} secret-title', 'correct horse');
    expect(file.contains('secret-title'), isFalse);
    expect(await b.decrypt(file, 'correct horse'), '{"v":1,"items":[]} secret-title');
  });

  test('wrong passphrase and bad files are refused', () async {
    final file = await b.encrypt('x', 'correct horse');
    await expectLater(b.decrypt(file, 'wrong one'), throwsFormatException);
    await expectLater(b.decrypt('not json', 'a'), throwsFormatException);
    await expectLater(b.decrypt('{"app":"faelen"}', 'a'), throwsFormatException);
  });

  test('replace swaps the vault, merge keeps the newer copy', () async {
    final s = await _open();
    final t0 = DateTime(2026, 1, 1), t1 = DateTime(2026, 6, 1);
    await s.add(_item('a', 'Old A', t0));
    await s.add(_item('b', 'Only here', t0));
    final text = s.backupText()!;

    final other = await _open();
    await other.add(_item('a', 'New A', t1));
    await other.add(_item('c', 'Only there', t0));

    expect(await other.restoreBackup(text, replace: false), 2);
    expect(other.items.map((i) => i.title).toSet(), {'New A', 'Only here', 'Only there'});

    await other.restoreBackup(text, replace: true);
    expect(other.items.map((i) => i.title).toSet(), {'Old A', 'Only here'});
  });

  test('a locked vault gives no backup text and refuses a restore', () async {
    final s = await _open();
    s.lock();
    expect(s.backupText(), isNull);
    await expectLater(s.restoreBackup('{"items":[]}', replace: true), throwsFormatException);
  });
}
