import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class Browser {
  const Browser(this.package, this.label, {this.icon});
  final String package;
  final String label;

  /// The app's own icon as PNG bytes, when the phone could provide it.
  final Uint8List? icon;
}

/// Opens a media link in a browser, following Settings > Open links with: the phone's default
/// browser, Android's app picker every time, or one chosen browser. It reads the saved choice
/// itself, so it also works from a notification tap with no screen.
class LinkOpener {
  /// Saved choice: [ask], or a browser's package name; absent means the default browser.
  static const choiceKey = 'link_browser_v1';
  static const choiceLabelKey = 'link_browser_label_v1';

  /// The "Ask every time" value of [choiceKey].
  static const ask = 'ask';

  /// Older builds saved "ask every time" as a yes/no switch under this key.
  static const legacyAskKey = 'link_ask_browser_v1';

  static const _channel = MethodChannel('faelen/links');

  static bool get supported => !kIsWeb && Platform.isAndroid;

  /// True when the link was handed to a browser (or to the picker).
  static Future<bool> open(Uri uri) async {
    if (supported) {
      final choice = await savedChoice();
      if (choice != null) {
        try {
          final handled = await _channel.invokeMethod<bool>(
            choice == ask ? 'chooser' : 'open',
            {'url': uri.toString(), if (choice != ask) 'package': choice},
          );
          if (handled == true) return true;
        } on PlatformException {
          // Falls back to the default browser.
        } on MissingPluginException {
          // Falls back to the default browser.
        }
      }
    }
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Null means the default browser.
  static Future<String?> savedChoice() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(choiceKey) ?? (prefs.getBool(legacyAskKey) == true ? ask : null);
    } catch (_) {
      return null;
    }
  }

  /// Browsers installed on the phone (empty when the list cannot be read).
  static Future<List<Browser>> browsers() async {
    if (!supported) return const [];
    try {
      final raw = await _channel.invokeListMethod<Map<Object?, Object?>>('browsers') ?? const [];
      return [
        for (final b in raw)
          if (b['package'] is String && b['label'] is String)
            Browser(b['package'] as String, b['label'] as String, icon: b['icon'] is Uint8List ? b['icon'] as Uint8List : null),
      ];
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }
}
