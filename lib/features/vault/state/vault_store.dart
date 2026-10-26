import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/vault_item.dart';
import '../services/pin_service.dart';
import '../services/secure_bridge.dart';
import '../services/vault_storage.dart';

enum VaultStatus { starting, needsSetup, locked, unlocked, failed }

/// How long a copied secret stays on the clipboard.
const clipboardClear = Duration(seconds: 30);

/// The Vault's data and lock. Entries are only in memory while unlocked; on lock they are dropped
/// and the clipboard is cleared. The encrypted file is only written after a successful read, so a
/// damaged file is never overwritten.
class VaultStore extends ChangeNotifier with WidgetsBindingObserver {
  VaultStore({
    required this.storage,
    required this.pin,
    required this.bridge,
    required this.biometrics,
    this.autoLock = const Duration(seconds: 30),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    WidgetsBinding.instance.addObserver(this);
  }

  static const _autoLockKey = 'vault_autolock_seconds';

  final VaultStorage storage;
  final PinService pin;
  final SecureBridge bridge;
  final Biometrics biometrics;
  final DateTime Function() _now;

  /// Time in the background before the Vault locks itself; zero locks at once.
  Duration autoLock;

  VaultStatus status = VaultStatus.starting;
  bool biometricReady = false;

  /// Set when the encrypted file exists but cannot be read. Saving is blocked while it is set.
  String? loadError;

  /// Why the secure store could not be opened (status is [VaultStatus.failed]).
  String? startError;
  String? saveError;

  List<VaultItem> _items = [];
  bool _readOk = false;
  DateTime? _backgroundedAt;
  int _seq = 0;

  List<VaultItem> get items => List.unmodifiable(_items);
  List<VaultItem> section(VaultSection s) => [
        for (final i in _items)
          if (i.section == s) i,
      ]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  List<VaultItem> get favorites => [
        for (final i in _items)
          if (i.favorite) i,
      ]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

  Future<void> init() async {
    try {
      final s = (await SharedPreferences.getInstance()).getInt(_autoLockKey);
      if (s != null) autoLock = Duration(seconds: s);
    } catch (_) {}
    try {
      status = await pin.hasPin() ? VaultStatus.locked : VaultStatus.needsSetup;
      biometricReady = await pin.biometricEnabled() && await biometrics.available();
      startError = null;
    } catch (e) {
      // The Keystore-backed store could not be read. Never fall back to "set up a new PIN" here:
      // that could replace a PIN that exists. Show the problem and let the user retry.
      status = VaultStatus.failed;
      startError = '$e';
    }
    notifyListeners();
  }

  Future<void> setAutoLock(Duration d) async {
    autoLock = d;
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setInt(_autoLockKey, d.inSeconds);
    } catch (_) {}
  }

  // ---- lock ----

  /// First run: the PIN is chosen and the (empty) vault opens. [useBiometric] turns on the
  /// fingerprint/face shortcut when the device has one.
  Future<void> setUp(String newPin, {bool useBiometric = false}) async {
    await pin.setPin(newPin);
    final canBio = useBiometric && await biometrics.available();
    await pin.setBiometric(canBio);
    biometricReady = canBio;
    await _open();
  }

  Future<PinResult> unlockWithPin(String attempt) async {
    final r = await pin.check(attempt);
    if (r.outcome == PinOutcome.ok) await _open();
    return r;
  }

  Future<bool> unlockWithBiometric() async {
    if (!biometricReady) return false;
    if (!await biometrics.authenticate('Unlock your Vault')) return false;
    await _open();
    return true;
  }

  Future<void> _open() async {
    _readOk = false;
    loadError = null;
    try {
      final text = await storage.read();
      _items = text == null ? [] : _parse(text);
      _readOk = true;
    } on FormatException catch (e) {
      _items = [];
      loadError = e.message;
    } catch (e) {
      _items = [];
      loadError = 'The Vault could not be read ($e)';
    }
    status = VaultStatus.unlocked;
    _backgroundedAt = null;
    notifyListeners();
  }

  List<VaultItem> _parse(String text) {
    final decoded = jsonDecode(text);
    final raw = decoded is Map ? decoded['items'] : null;
    return [
      if (raw is List)
        for (final j in raw) ?VaultItem.fromJson(j),
    ];
  }

  void lock() {
    if (status != VaultStatus.unlocked) return;
    _items = [];
    _readOk = false;
    status = VaultStatus.locked;
    bridge.clearNow();
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _backgroundedAt ??= _now();
      if (autoLock == Duration.zero) lock();
    } else if (state == AppLifecycleState.resumed) {
      final since = _backgroundedAt;
      _backgroundedAt = null;
      if (since != null && _now().difference(since) >= autoLock) lock();
    }
  }

  // ---- data ----

  Future<void> _save() async {
    if (!_readOk) {
      saveError = 'The Vault could not be read, so nothing was saved.';
      notifyListeners();
      return;
    }
    try {
      await storage.write(jsonEncode({'v': 1, 'items': [for (final i in _items) i.toJson()]}));
      saveError = null;
    } catch (_) {
      saveError = 'Could not save the Vault. Try again.';
    }
    notifyListeners();
  }

  String newId() => '${_now().microsecondsSinceEpoch}-${_seq++}';

  Future<void> add(VaultItem item) async {
    _items = [..._items, item];
    notifyListeners();
    await _save();
  }

  Future<void> update(VaultItem item) async {
    _items = [for (final i in _items) i.id == item.id ? item.copyWith(updatedAt: _now()) : i];
    notifyListeners();
    await _save();
  }

  Future<void> remove(String id) async {
    _items = [
      for (final i in _items)
        if (i.id != id) i,
    ];
    notifyListeners();
    await _save();
  }

  Future<void> toggleFavorite(VaultItem item) => update(item.copyWith(favorite: !item.favorite));

  /// Copies a field. Secrets are marked sensitive and cleared after [clipboardClear].
  Future<void> copy(VaultField f) =>
      bridge.copy(f.value, sensitive: f.secret, clearAfter: f.secret ? clipboardClear : null);

  /// IDs that expire within [days] (or already have): the hub and reminders use this.
  List<VaultItem> expiring({int days = 60}) => [
        for (final i in _items)
          if (i.daysLeft(_now()) case final d? when d <= days) i,
      ];

  /// Forgets the PIN, the key and every entry. Used when the PIN is lost; there is no recovery.
  Future<void> eraseEverything() async {
    await storage.wipe();
    await pin.reset();
    _items = [];
    _readOk = false;
    status = VaultStatus.needsSetup;
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
