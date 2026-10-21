import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/media_entry.dart';
import 'storage_service.dart';

/// Where the ids of the entries pinned to the notification shade are kept.
const pinnedIdsKey = 'pinned_media_v1';

/// +1 chapter/episode. Starts a planned entry and completes it when the total is reached.
MediaEntry bumpEntry(MediaEntry e) {
  final next = e.current + 1;
  final done = e.total > 0 && next >= e.total;
  return e.copyWith(
    current: done ? e.total : next,
    status: done ? Status.completed : (e.status == Status.planToWatch ? Status.watching : e.status),
  );
}

/// Marks the entry as finished (all chapters/episodes done when the total is known).
MediaEntry finishEntry(MediaEntry e) => e.copyWith(current: e.total > 0 ? e.total : e.current, status: Status.completed);

/// Whether the entry can sit in the notification shade: a series that is not finished or dropped.
bool canPin(MediaEntry e) => e.type != MediaType.movie && e.status != Status.completed && e.status != Status.dropped;

/// A stable notification id for an entry (String.hashCode is not guaranteed to survive restarts).
int pinnedNotificationId(String entryId) {
  var h = 0;
  for (final c in entryId.codeUnits) {
    h = (h * 31 + c) & 0xffff;
  }
  return 100000 + h;
}

const _incPrefix = 'inc|';
const _donePrefix = 'done|';

class PinnedResult {
  const PinnedResult(this.items, this.entry);
  final List<MediaEntry> items;
  final MediaEntry entry;
}

/// Applies a notification button ([actionId] is `inc|<entry id>` or `done|<entry id>`) to [items].
/// Null when the id is not one of ours or the entry no longer exists.
PinnedResult? applyPinnedAction(List<MediaEntry> items, String actionId, {required int now}) {
  final inc = actionId.startsWith(_incPrefix);
  if (!inc && !actionId.startsWith(_donePrefix)) return null;
  final id = actionId.substring(inc ? _incPrefix.length : _donePrefix.length);
  final i = items.indexWhere((e) => e.id == id);
  if (i < 0) return null;
  final updated = (inc ? bumpEntry(items[i]) : finishEntry(items[i])).copyWith(updatedAt: now);
  return PinnedResult([...items]..[i] = updated, updated);
}

String pinnedBody(MediaEntry e) =>
    '${e.season > 0 ? 'S${e.season} · ' : ''}${e.type.unit} ${e.current} / ${e.total > 0 ? e.total : '?'}';

/// Shows (or refreshes) the quiet, ongoing notification for [e]. Tapping the body opens its link.
Future<void> showPinned(FlutterLocalNotificationsPlugin plugin, MediaEntry e) {
  return plugin.show(
    id: pinnedNotificationId(e.id),
    title: e.title,
    body: pinnedBody(e),
    payload: e.url,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        'pinned',
        'Now reading and watching',
        channelDescription: 'Pinned titles with buttons to update your progress',
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true,
        autoCancel: false,
        onlyAlertOnce: true,
        playSound: false,
        enableVibration: false,
        actions: [
          AndroidNotificationAction('$_incPrefix${e.id}', '+1 ${e.type.unit}', showsUserInterface: false, cancelNotification: false),
          AndroidNotificationAction('$_donePrefix${e.id}', 'Done', showsUserInterface: false, cancelNotification: false),
        ],
      ),
    ),
  );
}

/// Runs when a button on a pinned notification is tapped, usually with the app closed.
/// Updates the saved list directly and refreshes (or removes) the notification.
@pragma('vm:entry-point')
Future<void> pinnedActionBackground(NotificationResponse response) async {
  final actionId = response.actionId;
  if (actionId == null || actionId.isEmpty) return;
  DartPluginRegistrant.ensureInitialized();
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // the app may have saved since this isolate last looked
    final storage = StorageService();
    final out = applyPinnedAction(await storage.load(), actionId, now: DateTime.now().millisecondsSinceEpoch);
    if (out == null) return;
    await storage.save(out.items);

    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
    );
    if (canPin(out.entry)) {
      await showPinned(plugin, out.entry);
    } else {
      await plugin.cancel(id: pinnedNotificationId(out.entry.id));
      final ids = prefs.getStringList(pinnedIdsKey) ?? const <String>[];
      await prefs.setStringList(pinnedIdsKey, [for (final x in ids) if (x != out.entry.id) x]);
    }
  } catch (_) {
    // Nothing useful to do from a background tap; the next time the app opens it re-syncs.
  }
}
