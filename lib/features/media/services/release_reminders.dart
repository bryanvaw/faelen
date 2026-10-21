import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';

import '../models/media_entry.dart';
import 'pinned_actions.dart';
import 'release_schedule.dart';

/// One weekly reminder: [weekday] (1 = Monday ... 7 = Sunday) at [minutes] after midnight.
class Reminder {
  const Reminder({required this.weekday, required this.minutes, required this.title, required this.body, this.url = ''});
  final int weekday;
  final int minutes;
  final String title;
  final String body;
  final String url; // opened when the notification is tapped; '' = just open the app

  @override
  bool operator ==(Object other) =>
      other is Reminder &&
      other.weekday == weekday &&
      other.minutes == minutes &&
      other.title == title &&
      other.body == body &&
      other.url == url;

  @override
  int get hashCode => Object.hash(weekday, minutes, title, body, url);
}

/// Schedules a weekly "new chapter/episode is out" notification for every followed entry
/// that has a release day. Everything is local; nothing is fetched.
class ReleaseReminders {
  /// Used when an entry has no reminder time of its own.
  static const defaultMinutes = 9 * 60;

  /// The notification plugin; call [ensureReady] before using it.
  final plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// True when the phone's timezone could not be read, so reminder times may be off.
  bool timezoneFailed = false;
  List<Reminder>? _scheduled; // last plan sent to the system, so unchanged plans are not rebuilt

  /// Whether this platform can show scheduled notifications at all.
  static bool get supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// The reminders [entries] call for as of [now]. Pure, so it can be tested.
  static List<Reminder> plan(Iterable<MediaEntry> entries, DateTime now, {int defaultMinutes = ReleaseReminders.defaultMinutes}) {
    final out = <Reminder>[];
    for (final e in entries) {
      final s = releaseStatus(e, now);
      if (s == null || s.nextRelease == null) continue; // not followed, or the series is complete
      final noun = e.type == MediaType.manhwa ? 'chapter' : 'episode';
      final minutes = e.releaseMinutes >= 0 ? e.releaseMinutes : defaultMinutes;
      for (final d in e.releaseDays) {
        out.add(Reminder(weekday: d, minutes: minutes, title: e.title, body: 'A new $noun is out today.', url: e.url));
      }
    }
    out.sort((a, b) {
      if (a.weekday != b.weekday) return a.weekday.compareTo(b.weekday);
      return a.minutes != b.minutes ? a.minutes.compareTo(b.minutes) : a.title.compareTo(b.title);
    });
    return out;
  }

  /// Sets up timezones and the plugin once, and returns the plugin.
  Future<FlutterLocalNotificationsPlugin> ensureReady() async {
    if (_ready) return plugin;
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier));
    } catch (_) {
      // Unknown zone: fall back to UTC, which only shifts the reminder time.
      timezoneFailed = true;
    }
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
            requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
      ),
      onDidReceiveNotificationResponse: (response) => _openPayload(response.payload),
      onDidReceiveBackgroundNotificationResponse: pinnedActionBackground,
    );
    _ready = true;
    // The app may have been started by tapping a notification while it was closed.
    final launch = await plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) _openPayload(launch?.notificationResponse?.payload);
    return plugin;
  }

  /// Opens the entry's link when its notification is tapped.
  static Future<void> _openPayload(String? payload) async {
    final uri = payload == null || payload.isEmpty ? null : Uri.tryParse(payload);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // The app is already in front; nothing more to do.
    }
  }

  /// Asks the system for notification permission. Returns whether reminders can be shown.
  Future<bool> requestPermission() async {
    if (!supported) return false;
    try {
      await ensureReady();
      if (Platform.isAndroid) {
        final android = plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        return await android?.requestNotificationsPermission() ?? false;
      }
      final ios = plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      return await ios?.requestPermissions(alert: true) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Makes the scheduled notifications match [entries]. With [enabled] false, clears them all.
  /// Shows a notification right now, so the user can check that reminders get through.
  Future<bool> showTest() async {
    if (!supported) return false;
    try {
      await ensureReady();
      await plugin.show(
        id: 9999,
        title: 'Faelen reminders work',
        body: 'You will get a note like this when a new chapter or episode is out.',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails('releases', 'New releases',
              channelDescription: 'A morning reminder when a chapter or episode you follow comes out'),
          iOS: DarwinNotificationDetails(),
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> sync(Iterable<MediaEntry> entries, {required bool enabled, int defaultMinutes = ReleaseReminders.defaultMinutes}) async {
    if (!supported) return;
    final wanted = enabled ? plan(entries, DateTime.now(), defaultMinutes: defaultMinutes) : const <Reminder>[];
    if (listEquals(wanted, _scheduled)) return;
    try {
      await ensureReady();
      await plugin.cancelAll();
      final now = tz.TZDateTime.now(tz.local);
      var id = 0;
      for (final r in wanted) {
        var when = tz.TZDateTime(tz.local, now.year, now.month, now.day, r.minutes ~/ 60, r.minutes % 60);
        while (when.weekday != r.weekday || !when.isAfter(now)) {
          when = when.add(const Duration(days: 1));
        }
        await plugin.zonedSchedule(
          id: id++,
          title: r.title,
          body: r.body,
          scheduledDate: when,
          payload: r.url,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails('releases', 'New releases',
                channelDescription: 'A morning reminder when a chapter or episode you follow comes out',
                importance: Importance.defaultImportance),
            iOS: DarwinNotificationDetails(),
          ),
          // Inexact, so no "alarms & reminders" permission is needed; a few minutes late is fine.
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        );
      }
      _scheduled = wanted;
    } catch (_) {
      // Leave _scheduled alone so the next change tries again.
    }
  }
}
