import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'vault_crypto.dart' show randomBytes;

/// A passphrase-protected copy of the Vault that can be opened on any phone. The key comes from the
/// passphrase (PBKDF2-SHA256 + a random salt), never from this phone's Keystore, so the file is
/// useless without the passphrase and there is no way to recover a forgotten one.
class VaultBackup {
  VaultBackup({this.iterations = defaultIterations});

  static const defaultIterations = 150000;
  static const _app = 'faelen-vault';
  static const _version = 1;
  static const minPassphrase = 8;

  final int iterations;
  final _aes = AesGcm.with256bits();

  Future<SecretKey> _derive(String passphrase, List<int> salt, int rounds) =>
      Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: rounds, bits: 256)
          .deriveKeyFromPassword(password: passphrase, nonce: salt);

  /// [vaultJson] is the Vault text (`{"v":1,"items":[...]}`).
  Future<String> encrypt(String vaultJson, String passphrase, {DateTime? now}) async {
    final salt = randomBytes(16);
    final box = await _aes.encrypt(
      utf8.encode(vaultJson),
      secretKey: await _derive(passphrase, salt, iterations),
      aad: utf8.encode(_app),
    );
    return jsonEncode({
      'app': _app,
      'version': _version,
      'exportedAt': (now ?? DateTime.now()).toUtc().toIso8601String(),
      'kdf': 'pbkdf2-sha256',
      'iterations': iterations,
      'salt': base64Encode(salt),
      'data': base64Encode(box.concatenation()),
    });
  }

  /// Throws [FormatException] for a file that is not a Vault backup, one from a newer Faelen, or a
  /// wrong passphrase (indistinguishable from a damaged file, by design of the cipher).
  Future<String> decrypt(String file, String passphrase) async {
    final Object? m;
    try {
      m = jsonDecode(file);
    } on FormatException {
      throw const FormatException('This file is not a Vault backup');
    }
    if (m is! Map || m['app'] != _app) {
      throw const FormatException('This is not a Faelen Vault backup file');
    }
    final v = m['version'], it = m['iterations'], salt = m['salt'], data = m['data'];
    if (v is! int || v > _version) {
      throw const FormatException('This backup was made by a newer version of Faelen');
    }
    if (it is! int || it < 1 || it > 5000000 || salt is! String || data is! String) {
      throw const FormatException('This Vault backup is damaged');
    }
    try {
      final box = SecretBox.fromConcatenation(base64Decode(data), nonceLength: 12, macLength: 16);
      final key = await _derive(passphrase, base64Decode(salt), it);
      final clear = await _aes.decrypt(box, secretKey: key, aad: utf8.encode(_app));
      return utf8.decode(Uint8List.fromList(clear));
    } catch (_) {
      throw const FormatException('Wrong passphrase, or the file is damaged');
    }
  }

  static String fileName(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return 'faelen-vault-${d.year}-${two(d.month)}-${two(d.day)}.fvault';
  }
}
