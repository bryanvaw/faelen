import 'dart:convert';
import 'dart:isolate';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:local_auth/local_auth.dart';

import 'vault_crypto.dart';

enum PinOutcome { ok, wrong, locked }

class PinResult {
  const PinResult(this.outcome, {this.triesLeft = 0, this.wait = Duration.zero});
  final PinOutcome outcome;
  final int triesLeft;
  final Duration wait;
}

/// The Vault's 6-digit PIN. Only a salted hash is kept (in the Keystore-backed store); it cannot
/// be recovered, by design. Five wrong tries in a row lock the pad for 30s, then 1 min, then 5 min.
class PinService {
  PinService(this._kv, {DateTime Function()? now, this.iterations = 30000}) : _now = now ?? DateTime.now;
  final SecureKv _kv;
  final DateTime Function() _now;
  final int iterations;

  static const length = 6;
  static const freeTries = 5;
  static const _hashKey = 'vault_pin_hash_v1';
  static const _saltKey = 'vault_pin_salt_v1';
  static const _failsKey = 'vault_pin_fails_v1';
  static const _untilKey = 'vault_pin_until_v1';
  static const _bioKey = 'vault_bio_v1';

  // Salt and hash live in one value ("salt.hash"), so a crash can never leave a new salt next to an
  // old hash. The two older keys are still read so a PIN made by an earlier build keeps working.
  static const _pinKey = 'vault_pin_v2';

  Future<bool> hasPin() async => await _kv.read(_pinKey) != null || await _kv.read(_hashKey) != null;

  Future<({String salt, String hash})?> _stored() async {
    final v = await _kv.read(_pinKey);
    if (v != null) {
      final i = v.indexOf('.');
      if (i > 0) return (salt: v.substring(0, i), hash: v.substring(i + 1));
    }
    final hash = await _kv.read(_hashKey);
    final salt = await _kv.read(_saltKey);
    return hash == null || salt == null ? null : (salt: salt, hash: hash);
  }

  /// Runs on a background isolate: the key stretching is slow in debug builds and would freeze the pad.
  Future<String> _hash(String pin, List<int> salt) {
    final rounds = iterations;
    // The browser has no isolates; there it runs inline (about 0.1s).
    if (kIsWeb) return _pbkdf2(pin, salt, rounds);
    return Isolate.run(() => _pbkdf2(pin, salt, rounds));
  }

  Future<void> setPin(String pin) async {
    final salt = randomBytes(16);
    await _kv.write(_pinKey, '${base64Encode(salt)}.${await _hash(pin, salt)}');
    await _kv.delete(_hashKey);
    await _kv.delete(_saltKey);
    await _kv.delete(_failsKey);
    await _kv.delete(_untilKey);
  }

  /// How long the pad stays locked after too many wrong tries; zero when it is open.
  Future<Duration> lockedFor() async {
    final until = int.tryParse(await _kv.read(_untilKey) ?? '');
    if (until == null) return Duration.zero;
    final left = DateTime.fromMillisecondsSinceEpoch(until).difference(_now());
    return left.isNegative ? Duration.zero : left;
  }

  Future<PinResult> check(String pin) async {
    final wait = await lockedFor();
    if (wait > Duration.zero) return PinResult(PinOutcome.locked, wait: wait);
    final stored = await _stored();
    if (stored == null) return const PinResult(PinOutcome.wrong);
    if (await _hash(pin, base64Decode(stored.salt)) == stored.hash) {
      await _kv.delete(_failsKey);
      await _kv.delete(_untilKey);
      return const PinResult(PinOutcome.ok);
    }
    final fails = (int.tryParse(await _kv.read(_failsKey) ?? '') ?? 0) + 1;
    await _kv.write(_failsKey, '$fails');
    if (fails >= freeTries) {
      final step = fails - freeTries; // 0 -> 30s, 1 -> 1 min, 2+ -> 5 min
      final delay = step == 0 ? const Duration(seconds: 30) : (step == 1 ? const Duration(minutes: 1) : const Duration(minutes: 5));
      await _kv.write(_untilKey, '${_now().add(delay).millisecondsSinceEpoch}');
      return PinResult(PinOutcome.locked, wait: delay);
    }
    return PinResult(PinOutcome.wrong, triesLeft: freeTries - fails);
  }

  /// Forgets the PIN and its counters (the vault is wiped separately).
  Future<void> reset() async {
    for (final k in [_pinKey, _hashKey, _saltKey, _failsKey, _untilKey, _bioKey]) {
      await _kv.delete(k);
    }
  }

  Future<bool> biometricEnabled() async => await _kv.read(_bioKey) == '1';
  Future<void> setBiometric(bool on) => on ? _kv.write(_bioKey, '1') : _kv.delete(_bioKey);
}

/// Fingerprint / face / device lock. A fake replaces it in tests.
abstract class Biometrics {
  Future<bool> available();
  Future<bool> authenticate(String reason);
}

class DeviceBiometrics implements Biometrics {
  final _auth = LocalAuthentication();

  @override
  Future<bool> available() async {
    try {
      return await _auth.isDeviceSupported() && (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(localizedReason: reason, biometricOnly: true);
    } catch (_) {
      return false; // cancelled, locked out or not enrolled: the PIN pad stays
    }
  }
}

Future<String> _pbkdf2(String pin, List<int> salt, int iterations) async {
  final pbkdf2 = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256);
  final key = await pbkdf2.deriveKeyFromPassword(password: pin, nonce: salt);
  return base64Encode(await key.extractBytes());
}
