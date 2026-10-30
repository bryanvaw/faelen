import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'link_opener.dart';

/// App-wide preferences (currently just the theme).
class SettingsStore extends ChangeNotifier {
  static const _themeKey = 'theme_mode_v1';

  static const _autoKey = 'url_auto_progress_v1';
  static const _remindKey = 'release_reminders_v1';
  static const _remindTimeKey = 'default_reminder_minutes_v1';
  static const _backupKey = 'last_backup_ms_v1';

  ThemeMode themeMode = ThemeMode.system;

  /// When true, saving a link updates progress straight away; otherwise the form asks first.
  bool autoUrlProgress = false;

  /// When true, Continue and reminder taps show Android's app picker instead of the default browser.
  bool askBrowser = false;

  /// Morning notification on the day a followed manhwa/anime gets a new chapter/episode.
  bool releaseReminders = false;

  /// Reminder time for shows without their own, in minutes after midnight (default 9:00).
  int defaultReminderMinutes = 9 * 60;

  /// When the user last exported a backup (ms since epoch); 0 = never.
  int lastBackup = 0;

  Future<void> load() async {
    try {
      final name = (await SharedPreferences.getInstance()).getString(_themeKey);
      themeMode = ThemeMode.values.firstWhere((m) => m.name == name, orElse: () => ThemeMode.system);
      autoUrlProgress = (await SharedPreferences.getInstance()).getBool(_autoKey) ?? false;
      releaseReminders = (await SharedPreferences.getInstance()).getBool(_remindKey) ?? false;
      defaultReminderMinutes = (await SharedPreferences.getInstance()).getInt(_remindTimeKey) ?? 9 * 60;
      lastBackup = (await SharedPreferences.getInstance()).getInt(_backupKey) ?? 0;
      askBrowser = (await SharedPreferences.getInstance()).getBool(LinkOpener.askKey) ?? false;
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

  Future<void> setAskBrowser(bool v) async {
    askBrowser = v;
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setBool(LinkOpener.askKey, v);
    } catch (_) {
      // Not being able to remember the choice is not worth an error.
    }
  }

  Future<void> setReleaseReminders(bool v) async {
    releaseReminders = v;
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setBool(_remindKey, v);
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

  Future<void> setDefaultReminderMinutes(int m) async {
    defaultReminderMinutes = m;
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setInt(_remindTimeKey, m);
    } catch (_) {
      // Not being able to remember the choice is not worth an error.
    }
  }

  Future<void> markBackedUp([DateTime? now]) async {
    lastBackup = (now ?? DateTime.now()).millisecondsSinceEpoch;
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setInt(_backupKey, lastBackup);
    } catch (_) {
      // Only the reminder to back up is affected.
    }
  }
}
