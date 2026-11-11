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
      biometricReady =
          await pin.biometricEnabled() && await biometrics.available();
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
      await (await SharedPreferences.getInstance()).setInt(
        _autoLockKey,
        d.inSeconds,
      );
    } catch (_) {}
  }

  // ---- lock ----

  /// First run: the PIN is chosen and the (empty) vault opens. [useBiometric] turns on the
  /// fingerprint/face shortcut when the device has one.
  Future<void> setUp(String newPin, {bool useBiometric = false}) async {
    // A vault file that cannot be read is never cleared here: the Vault opens with the "could not
    // be read" banner, and erasing it is the user's choice ("Erase and start over").
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
      _unread = [];
      _items = text == null ? [] : _parse(text, keepUnread: true);
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

  /// Entries of the stored file this build cannot read (damaged, or a kind a newer Faelen added).
  /// They are not shown, but every save writes them back so they are never lost.
  List<Object?> _unread = [];

  List<VaultItem> _parse(String text, {bool keepUnread = false}) {
    final decoded = jsonDecode(text);
    final raw = decoded is Map ? decoded['items'] : null;
    final out = <VaultItem>[];
    if (raw is List) {
      for (final j in raw) {
        final item = VaultItem.fromJson(j);
        if (item != null) {
          out.add(item);
        } else if (keepUnread) {
          _unread.add(j);
        }
      }
    }
    return out;
  }

  String _text() => jsonEncode({
    'v': 1,
    'items': [for (final i in _items) i.toJson(), ..._unread],
  });

  void lock() {
    if (status != VaultStatus.unlocked) return;
    _items = [];
    _unread = [];
    _readOk = false;
    status = VaultStatus.locked;
    bridge.clearNow();
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _backgroundedAt ??= _now();
      if (autoLock == Duration.zero) lock();
    } else if (state == AppLifecycleState.resumed) {
      final since = _backgroundedAt;
      _backgroundedAt = null;
      if (since != null && _now().difference(since) >= autoLock) lock();
    }
  }

  // ---- data ----

  /// Writes run one after another, each with the text as it was when the change was made, so two
  /// quick changes can neither collide on the temp file nor land in the wrong order, and a lock
  /// right after a change cannot drop it.
  Future<void>?
  _writing; // null until the first write, so no future is made ahead of its use

  Future<void> _save() {
    if (!_readOk) {
      saveError = 'The Vault could not be read, so nothing was saved.';
      notifyListeners();
      return Future.value();
    }
    final text = _text();
    final before = _writing;
    return _writing = before == null
        ? _write(text)
        : before.then((_) => _write(text));
  }

  Future<void> _write(String text) async {
    try {
      await storage.write(text);
      saveError = null;
    } catch (_) {
      saveError = 'Could not save the Vault. Try again.';
    }
    notifyListeners();
  }

  String newId() => '${_now().microsecondsSinceEpoch}-${_seq++}';

  Future<void> add(VaultItem item) async {
    if (status != VaultStatus.unlocked) {
      return; // e.g. Undo after the Vault locked
    }
    _items = [..._items, item];
    notifyListeners();
    await _save();
  }

  Future<void> update(VaultItem item) async {
    if (status != VaultStatus.unlocked) return;
    _items = [
      for (final i in _items)
        i.id == item.id ? item.copyWith(updatedAt: _now()) : i,
    ];
    notifyListeners();
    await _save();
  }

  Future<void> remove(String id) async {
    if (status != VaultStatus.unlocked) return;
    _items = [
      for (final i in _items)
        if (i.id != id) i,
    ];
    notifyListeners();
    await _save();
  }

  Future<void> toggleFavorite(VaultItem item) =>
      update(item.copyWith(favorite: !item.favorite));

  /// Copies a field. Secrets are marked sensitive and cleared after [clipboardClear].
  Future<void> copy(VaultField f) => bridge.copy(
    f.value,
    sensitive: f.secret,
    clearAfter: f.secret ? clipboardClear : null,
  );

  /// The Vault text for a backup. Null while locked or when the stored data could not be read
  /// (a backup of nothing would look like a good one).
  String? backupText() {
    if (status != VaultStatus.unlocked || !_readOk) return null;
    return _text();
  }

  /// Brings a backup's entries in. Merge keeps the newer copy of any entry that is in both;
  /// replace swaps the whole Vault for the backup. Returns how many entries the backup held.
  /// Throws [FormatException] if the text is not a Vault; nothing changes then.
  Future<int> restoreBackup(String text, {required bool replace}) async {
    if (status != VaultStatus.unlocked || !_readOk) {
      throw const FormatException('Unlock the Vault first');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw const FormatException('The backup could not be read');
    }
    if (decoded is! Map || decoded['items'] is! List) {
      throw const FormatException('The backup could not be read');
    }
    final incoming = _parse(text);
    if (replace) {
      _items = incoming;
      _unread = [];
    } else {
      final byId = {for (final i in _items) i.id: i};
      for (final i in incoming) {
        final old = byId[i.id];
        if (old == null || i.updatedAt.isAfter(old.updatedAt)) byId[i.id] = i;
      }
      _items = byId.values.toList();
    }
    notifyListeners();
    await _save();
    return incoming.length;
  }

  /// IDs that expire within [days] (or already have): the hub and reminders use this.
  List<VaultItem> expiring({int days = 60}) => [
    for (final i in _items)
      if (i.daysLeft(_now()) case final d? when d <= days) i,
  ];

  /// Forgets the PIN, the key and every entry. Used when the PIN is lost; there is no recovery.
  Future<void> eraseEverything() async {
    await _writing; // let a save in flight finish first so it cannot bring the file back
    await storage.wipe();
    await pin.reset();
    _items = [];
    _unread = [];
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
