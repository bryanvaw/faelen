import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/media_entry.dart';
import 'pinned_actions.dart';
import 'release_reminders.dart';

/// The titles pinned to the notification shade, each with +1 and Done buttons (Android only).
/// The ids live in their own preference so the buttons can change them with the app closed.
class PinnedStore extends ChangeNotifier {
  PinnedStore(this._reminders);
  final ReleaseReminders _reminders;

  static const maxPinned = 3;

  static bool get supported => !kIsWeb && Platform.isAndroid;

  List<String> _ids = [];
  final _shown = <String, String>{}; // entry id -> what the notification currently says

  bool isPinned(String id) => _ids.contains(id);
  bool get full => _ids.length >= maxPinned;

  /// Reads the pinned ids. With [reload], picks up changes made by a notification button.
  Future<void> load({bool reload = false}) async {
    if (!supported) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (reload) await prefs.reload();
      final ids = prefs.getStringList(pinnedIdsKey) ?? [];
      if (!listEquals(ids, _ids)) {
        _ids = ids;
        notifyListeners();
      }
    } catch (_) {
      // Pinning is optional; a failed read just means nothing is pinned.
    }
  }

  /// Pins or unpins [id]. Returns an explanation when it could not be pinned, otherwise null.
  Future<String?> toggle(String id) async {
    if (isPinned(id)) {
      await _save([for (final x in _ids) if (x != id) x]);
      return null;
    }
    if (full) return 'You can pin up to $maxPinned titles. Unpin one first.';
    if (!await _reminders.requestPermission()) return 'Allow notifications for Faelen to pin titles.';
    await _save([..._ids, id]);
    return null;
  }

  Future<void> _save(List<String> ids) async {
    _ids = ids;
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setStringList(pinnedIdsKey, ids);
    } catch (_) {
      // Keep the in-memory pins; the next change tries again.
    }
  }

  /// Makes the notifications match [entries]: drops pins for deleted or finished titles, shows the
  /// rest with their current progress, and removes the notification of anything unpinned.
  Future<void> sync(Iterable<MediaEntry> entries) async {
    if (!supported) return;
    final byId = {for (final e in entries) e.id: e};
    final keep = [for (final id in _ids) if (byId[id] != null && canPin(byId[id]!)) id];
    if (!listEquals(keep, _ids)) await _save(keep);
    try {
      final plugin = await _reminders.ensureReady();
      for (final id in _shown.keys.where((id) => !keep.contains(id)).toList()) {
        await plugin.cancel(id: pinnedNotificationId(id));
        _shown.remove(id);
      }
      for (final id in keep) {
        final e = byId[id]!;
        final signature = '${e.title}|${pinnedBody(e)}|${e.url}';
        if (_shown[id] == signature) continue;
        await showPinned(plugin, e);
        _shown[id] = signature;
      }
    } catch (_) {
      // Notifications blocked or unavailable; the next change tries again.
    }
  }
}
