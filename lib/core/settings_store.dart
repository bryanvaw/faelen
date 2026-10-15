import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide preferences (currently just the theme).
class SettingsStore extends ChangeNotifier {
  static const _themeKey = 'theme_mode_v1';

  static const _autoKey = 'url_auto_progress_v1';

  ThemeMode themeMode = ThemeMode.system;

  /// When true, saving a link updates progress straight away; otherwise the form asks first.
  bool autoUrlProgress = false;

  Future<void> load() async {
    try {
      final name = (await SharedPreferences.getInstance()).getString(_themeKey);
      themeMode = ThemeMode.values.firstWhere((m) => m.name == name, orElse: () => ThemeMode.system);
      autoUrlProgress = (await SharedPreferences.getInstance()).getBool(_autoKey) ?? false;
      notifyListeners();
    } catch (_) {
      // Fall back to the system theme.
    }
  }

  Future<void> setThemeMode(ThemeMode m) async {
    themeMode = m;
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setString(_themeKey, m.name);
    } catch (_) {
      // Not being able to remember the choice is not worth an error.
    }
  }

  Future<void> setAutoUrlProgress(bool v) async {
    autoUrlProgress = v;
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setBool(_autoKey, v);
    } catch (_) {
      // Not being able to remember the choice is not worth an error.
    }
  }
}
