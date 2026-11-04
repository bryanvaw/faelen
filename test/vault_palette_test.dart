import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:faelen/core/settings_store.dart';
import 'package:faelen/core/theme.dart';
import 'package:faelen/features/vault/models/vault_item.dart';
import 'package:faelen/features/vault/screens/vault_screen.dart';
import 'package:faelen/features/vault/services/pin_service.dart';
import 'package:faelen/features/vault/services/secure_bridge.dart';
import 'package:faelen/features/vault/services/vault_crypto.dart';
import 'package:faelen/features/vault/services/vault_storage.dart';
import 'package:faelen/features/vault/state/vault_store.dart';

class _NoBio implements Biometrics {
  @override
  Future<bool> available() async => false;
  @override
  Future<bool> authenticate(String reason) async => false;
}

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('Vault colour: pick a deep colour, it is remembered, and nothing overflows at 320x640 (${brightness.name})', (t) async {
      SharedPreferences.setMockInitialValues({});
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final kv = MemoryKv();
      final store = VaultStore(storage: MemoryVaultStorage(), pin: PinService(kv, iterations: 10), bridge: FakeSecureBridge(), biometrics: _NoBio());
      await t.runAsync(() async {
        await store.init();
        await store.setUp('123456');
        await store.add(VaultItem(
          id: '1',
          section: VaultSection.logins,
          title: 'Netflix',
          updatedAt: DateTime(2026, 1, 1),
          favorite: true,
          fields: const [VaultField('Username', 'me@mail.test'), VaultField('Password', 'Secret-123', secret: true)],
        ));
      });
      final settings = SettingsStore();
      await t.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<VaultStore>.value(value: store),
          ChangeNotifierProvider<SettingsStore>.value(value: settings),
        ],
        child: MaterialApp(theme: buildTheme(brightness), home: const VaultScreen()),
      ));
      await t.pump(const Duration(milliseconds: 100));

      await t.tap(find.byTooltip('Vault colour'));
      await t.pumpAndSettle();
      expect(find.text('Vault colour'), findsWidgets);
      await t.tap(find.bySemanticsLabel('Navy'));
      await t.pumpAndSettle();
      expect(settings.vaultColor, 13); // Navy's place in vaultSwatches (two calico colours come first)

      // Back on the Vault with the deep colour: open the add form and a row, no overflow anywhere.
      await t.tapAt(const Offset(160, 20));
      await t.pumpAndSettle();
      await t.tap(find.text('Netflix').last);
      await t.pump();
      expect(t.takeException(), isNull);

      await t.runAsync(() => settings.setVaultColor(-1));
      expect(settings.vaultColor, -1);
    });
  }
}
