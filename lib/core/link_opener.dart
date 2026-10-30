import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a media link in a browser. By default that is the phone's default browser; with
/// "Ask every time" (Settings) Android shows its app picker so any installed browser can be chosen.
/// It reads the saved choice itself, so it also works from a notification tap with no screen.
class LinkOpener {
  static const askKey = 'link_ask_browser_v1';
  static const _channel = MethodChannel('faelen/links');

  /// True when the link was handed to a browser (or to the picker).
  static Future<bool> open(Uri uri) async {
    if (!kIsWeb && Platform.isAndroid && await _ask()) {
      try {
        if (await _channel.invokeMethod<bool>('chooser', {'url': uri.toString()}) == true) return true;
      } on PlatformException {
        // Falls back to the default browser.
      } on MissingPluginException {
        // Falls back to the default browser.
      }
    }
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static Future<bool> _ask() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(askKey) ?? false;
    } catch (_) {
      return false;
    }
  }
}
