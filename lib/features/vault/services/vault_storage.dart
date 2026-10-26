import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'vault_crypto.dart';

/// Where the vault text is kept. The text is JSON; implementations store it encrypted.
abstract class VaultStorage {
  /// The app's storage: an encrypted file on devices, encrypted text in `shared_preferences` in the browser.
  static VaultStorage forApp(VaultCrypto crypto) => kIsWeb ? PrefsVaultStorage(crypto) : FileVaultStorage(crypto);

  /// Null when nothing has been saved yet. Throws [FormatException] when the data is unreadable;
  /// callers must then refuse to save so the damaged file is not overwritten.
  Future<String?> read();
  Future<void> write(String text);
  Future<void> wipe();
}

/// One encrypted file (`vault.enc`) in the app's documents folder, replaced atomically.
class FileVaultStorage implements VaultStorage {
  FileVaultStorage(this._crypto, {Future<Directory> Function()? dir}) : _dir = dir ?? getApplicationDocumentsDirectory;
  final VaultCrypto _crypto;
  final Future<Directory> Function() _dir;

  Future<File> _file() async => File(p.join((await _dir()).path, 'vault.enc'));

  @override
  Future<String?> read() async {
    final f = await _file();
    if (!await f.exists()) return null;
    return _crypto.decrypt(await f.readAsBytes());
  }

  @override
  Future<void> write(String text) async {
    final f = await _file();
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsBytes(await _crypto.encrypt(text), flush: true);
    await tmp.rename(f.path);
  }

  @override
  Future<void> wipe() async {
    final f = await _file();
    if (await f.exists()) await f.delete();
  }
}

class MemoryVaultStorage implements VaultStorage {
  String? text;
  @override
  Future<String?> read() async => text;
  @override
  Future<void> write(String t) async => text = t;
  @override
  Future<void> wipe() async => text = null;
}

/// Browser build: no files, so the encrypted bytes are kept as base64 text. Same encryption as the file.
class PrefsVaultStorage implements VaultStorage {
  PrefsVaultStorage(this._crypto);
  final VaultCrypto _crypto;
  static const _key = 'vault_enc_v1';

  @override
  Future<String?> read() async {
    final text = (await SharedPreferences.getInstance()).getString(_key);
    if (text == null) return null;
    return _crypto.decrypt(base64Decode(text)); // throws FormatException when damaged
  }

  @override
  Future<void> write(String text) async {
    final bytes = await _crypto.encrypt(text);
    await (await SharedPreferences.getInstance()).setString(_key, base64Encode(bytes));
  }

  @override
  Future<void> wipe() async => (await SharedPreferences.getInstance()).remove(_key);
}
