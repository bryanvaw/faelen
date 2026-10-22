import 'dart:ui' show Color, DartPluginRegistrant;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/media_entry.dart';
import 'cover_service.dart';
import 'release_schedule.dart';
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
  final changed = inc ? bumpEntry(items[i]) : finishEntry(items[i]);
  final updated = settleSchedule(items[i], changed, DateTime.fromMillisecondsSinceEpoch(now)).copyWith(updatedAt: now);
  return PinnedResult([...items]..[i] = updated, updated);
}

String pinnedBody(MediaEntry e) =>
    '${e.season > 0 ? 'S${e.season} · ' : ''}${e.type.unit} ${e.current} / ${e.total > 0 ? e.total : '?'}';

/// The status-bar icon (a white cat silhouette in `res/drawable`) and the colour Android tints it with.
const notificationIcon = 'ic_stat_faelen';
const notificationColor = Color(0xFFF26B50); // the app's coral

/// Second line of the expanded notification: what is waiting, or when the next one lands.
String? pinnedReleaseLine(MediaEntry e, DateTime now) {
  final s = releaseStatus(e, now);
  if (s == null) return null;
  if (s.behind > 0) return '${s.behind} new waiting';
  final next = s.nextRelease;
  return next == null ? null : 'Caught up · Next ${weekdayShort[next.weekday - 1]}';
}

/// "Read Ch 35" / "Watched Ep 4": the button says exactly what a tap will record.
String pinnedBumpLabel(MediaEntry e) => '${e.type == MediaType.manhwa ? 'Read' : 'Watched'} ${e.type.unit} ${e.current + 1}';

/// Everything the notification shows, so [PinnedStore] can tell when it needs refreshing.
String pinnedSignature(MediaEntry e, DateTime now) =>
    '${e.title}|${pinnedBody(e)}|${e.status.name}|${e.cover}|${e.url}|${pinnedReleaseLine(e, now)}';

/// Path of the entry's cover file when it has one on disk (used as the large icon).
Future<String?> pinnedCoverPath(MediaEntry e) async {
  if (e.cover == null || e.cover!.isEmpty) return null;
  try {
    final covers = CoverService();
    await covers.init();
    final f = covers.fileFor(e.cover);
    return f != null && await f.exists() ? f.path : null;
  } catch (_) {
    return null;
  }
}

/// Shows (or refreshes) the quiet, ongoing notification for [e]: cover, title, progress bar and
/// two buttons. Tapping the body opens its link.
Future<void> showPinned(FlutterLocalNotificationsPlugin plugin, MediaEntry e) async {
  final now = DateTime.now();
  final cover = await pinnedCoverPath(e);
  final release = pinnedReleaseLine(e, now);
  final known = e.total > 0;
  final big = '<b>${e.season > 0 ? 'S${e.season} · ' : ''}${e.type.unit} ${e.current}</b>${known ? ' of ${e.total}' : ''}'
      '${release == null ? '' : '<br>$release'}';
  return plugin.show(
    id: pinnedNotificationId(e.id),
    title: e.title,
    body: release == null ? pinnedBody(e) : '${pinnedBody(e)} · $release',
    payload: e.url,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        'pinned',
        'Now reading and watching',
        channelDescription: 'Pinned titles with buttons to update your progress',
        icon: notificationIcon,
        color: notificationColor,
        largeIcon: cover != null ? FilePathAndroidBitmap(cover) : const DrawableResourceAndroidBitmap('cat_media'),
        subText: '${e.type.label} · ${e.status.label}',
        showWhen: false,
        showProgress: known,
        maxProgress: known ? e.total : 0,
        progress: known ? e.current : 0,
        styleInformation: BigTextStyleInformation(big, htmlFormatBigText: true),
        category: AndroidNotificationCategory.status,
        visibility: NotificationVisibility.public,
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true,
        autoCancel: false,
        onlyAlertOnce: true,
        playSound: false,
        enableVibration: false,
        actions: [
          AndroidNotificationAction('$_incPrefix${e.id}', pinnedBumpLabel(e), showsUserInterface: false, cancelNotification: false),
          AndroidNotificationAction('$_donePrefix${e.id}', 'Mark done', showsUserInterface: false, cancelNotification: false),
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
    final storage = StorageService.forApp();
    final out = applyPinnedAction(await storage.load(), actionId, now: DateTime.now().millisecondsSinceEpoch);
    if (out == null) return;
    await storage.save(out.items);

    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings(notificationIcon)),
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
