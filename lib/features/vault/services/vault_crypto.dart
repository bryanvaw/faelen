import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Small key/value store for secrets (the data key, the PIN hash, the lockout counters).
/// The app uses the Android Keystore through `flutter_secure_storage`; tests use memory.
abstract class SecureKv {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class KeystoreKv implements SecureKv {
  // The plugin's default (resetOnError) answers a failed read by deleting the value and saying
  // "nothing saved", which for the Vault means a lost data key or PIN. With it off, a failed read
  // throws and the Vault shows its "could not start / could not be read" screens instead.
  KeystoreKv([FlutterSecureStorage? storage])
    : _s =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(resetOnError: false),
          );
  final FlutterSecureStorage _s;

  @override
  Future<String?> read(String key) => _s.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _s.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _s.delete(key: key);
}

class MemoryKv implements SecureKv {
  final Map<String, String> data = {};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
  @override
  Future<void> delete(String key) async => data.remove(key);
}

Uint8List randomBytes(int n) {
  final r = Random.secure();
  return Uint8List.fromList(List<int>.generate(n, (_) => r.nextInt(256)));
}

/// AES-256-GCM over the whole vault text. The key is made once, lives in [SecureKv] and never
/// leaves the device. Output layout: one version byte, then nonce + cipher text + tag.
class VaultCrypto {
  VaultCrypto(this._kv);
  final SecureKv _kv;

  static const _keyName = 'vault_data_key_v1';
  static const _version = 1;
  final _aes = AesGcm.with256bits();

  Future<SecretKey>? _cached;

  /// One load at a time: two saves arriving together on a fresh install must not each make a key.
  /// Only a save may [create] the key. Reading never does: a new key cannot open data written
  /// with the old one, and making it would hide that the old one is gone.
  Future<SecretKey> _key({required bool create}) async {
    final pending = _cached ??= _load(create);
    try {
      return await pending;
    } catch (_) {
      if (identical(_cached, pending)) _cached = null; // try again next time
      rethrow;
    }
  }

  Future<SecretKey> _load(bool create) async {
    final stored = await _kv.read(_keyName);
    if (stored != null) return SecretKey(base64Decode(stored));
    if (!create) throw const FormatException('The vault key is missing');
    final bytes = randomBytes(32);
    await _kv.write(_keyName, base64Encode(bytes));
    return SecretKey(bytes);
  }

  Future<Uint8List> encrypt(String text) async {
    final box = await _aes.encrypt(utf8.encode(text), secretKey: await _key(create: true));
    return Uint8List.fromList([_version, ...box.concatenation()]);
  }

  /// Throws [FormatException] when the bytes are damaged or the key does not match.
  Future<String> decrypt(Uint8List bytes) async {
    if (bytes.isEmpty || bytes[0] != _version) {
      throw const FormatException('Unknown vault format');
    }
    try {
      final box = SecretBox.fromConcatenation(
        bytes.sublist(1),
        nonceLength: 12,
        macLength: 16,
      );
      return utf8.decode(await _aes.decrypt(box, secretKey: await _key(create: false)));
    } catch (_) {
      throw const FormatException('The vault could not be decrypted');
    }
  }
}
