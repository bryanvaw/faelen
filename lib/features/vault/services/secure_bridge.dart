import 'dart:async';

import 'package:flutter/services.dart';

/// The few things Flutter cannot do alone: block screenshots on Vault screens, and copy to the
/// clipboard marked as sensitive with a timed clear (Android, `MainActivity.kt`). Elsewhere it
/// falls back to the plain clipboard and a Dart timer.
abstract class SecureBridge {
  Future<void> setSecure(bool on);

  /// Copies [text]. A sensitive copy is hidden from the clipboard preview and cleared after
  /// [clearAfter], but only if the clipboard still holds our copy.
  Future<void> copy(String text, {bool sensitive = false, Duration? clearAfter});
  Future<void> clearNow();
}

class PlatformSecureBridge implements SecureBridge {
  static const _channel = MethodChannel('faelen/secure');
  Timer? _fallbackTimer;
  String? _fallbackText;

  @override
  Future<void> setSecure(bool on) async {
    try {
      await _channel.invokeMethod<void>('setSecure', {'on': on});
    } on MissingPluginException {
      // Not Android: nothing to block.
    } on PlatformException {
      // Best effort.
    }
  }

  @override
  Future<void> copy(String text, {bool sensitive = false, Duration? clearAfter}) async {
    try {
      await _channel.invokeMethod<void>('copy', {
        'text': text,
        'sensitive': sensitive,
        'clearAfterMs': clearAfter?.inMilliseconds ?? 0,
      });
      return;
    } on MissingPluginException {
      // Fall through to the plain clipboard.
    } on PlatformException {
      // Fall through as well.
    }
    await Clipboard.setData(ClipboardData(text: text));
    _fallbackTimer?.cancel();
    _fallbackText = text;
    if (clearAfter != null) _fallbackTimer = Timer(clearAfter, clearNow);
  }

  @override
  Future<void> clearNow() async {
    _fallbackTimer?.cancel();
    try {
      await _channel.invokeMethod<void>('clear');
      return;
    } on MissingPluginException {
      // Fall through.
    } on PlatformException {
      // Fall through.
    }
    final current = await Clipboard.getData(Clipboard.kTextPlain);
    if (_fallbackText != null && current?.text == _fallbackText) {
      await Clipboard.setData(const ClipboardData(text: ''));
    }
    _fallbackText = null;
  }
}

class FakeSecureBridge implements SecureBridge {
  bool secure = false;
  final copies = <({String text, bool sensitive, Duration? clearAfter})>[];
  int clears = 0;

  @override
  Future<void> setSecure(bool on) async => secure = on;
  @override
  Future<void> copy(String text, {bool sensitive = false, Duration? clearAfter}) async =>
      copies.add((text: text, sensitive: sensitive, clearAfter: clearAfter));
  @override
  Future<void> clearNow() async => clears++;
}
