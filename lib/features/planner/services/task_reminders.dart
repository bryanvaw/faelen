import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../media/services/release_reminders.dart';
import '../models/task.dart';
import '../state/planner_store.dart' show timeLabel;

/// First notification id used for tasks. Release reminders use 0..n and pinned titles 100000..165535,
/// so each kind can be cleared without touching the others.
const taskNotificationBase = 200000;

/// One notification for one task, at one moment.
class TaskReminder {
  const TaskReminder({required this.when, required this.title, required this.body});
  final DateTime when;
  final String title;
  final String body;

  @override
  bool operator ==(Object other) => other is TaskReminder && other.when == when && other.title == title && other.body == body;

  @override
  int get hashCode => Object.hash(when, title, body);
}

/// A notification at the due time of every open task that asked for one (9:00 when it has a day but
/// no time). Everything is local. A repeating task has only its next date scheduled; finishing it
/// moves the date and the next sync schedules the new one.
class TaskReminders {
  TaskReminders(this._base);
  final ReleaseReminders _base;

  /// Android keeps a limited number of pending alarms; the soonest ones matter most.
  static const maxScheduled = 50;

  List<TaskReminder>? _scheduled;

  /// The reminders [tasks] call for as of [now]. Pure, so it can be tested.
  static List<TaskReminder> plan(Iterable<Task> tasks, DateTime now) {
    final out = <TaskReminder>[
      for (final t in tasks)
        if (!t.isDone && t.remind && t.remindAt != null && t.remindAt!.isAfter(now))
          TaskReminder(
            when: t.remindAt!,
            title: t.title,
            body: t.hasTime ? 'Due at ${timeLabel(t.minutes)}' : 'Due today',
          ),
    ]..sort((a, b) => a.when != b.when ? a.when.compareTo(b.when) : a.title.compareTo(b.title));
    return out.length > maxScheduled ? out.sublist(0, maxScheduled) : out;
  }

  Future<void> sync(Iterable<Task> tasks, {DateTime? now}) async {
    if (!ReleaseReminders.supported) return;
    final wanted = plan(tasks, now ?? DateTime.now());
    if (listEquals(wanted, _scheduled)) return;
    try {
      final plugin = await _base.ensureReady();
      for (final r in await plugin.pendingNotificationRequests()) {
        if (r.id >= taskNotificationBase) await plugin.cancel(id: r.id);
      }
      var id = taskNotificationBase;
      for (final r in wanted) {
        await plugin.zonedSchedule(
          id: id++,
          title: r.title,
          body: r.body,
          scheduledDate: tz.TZDateTime.from(r.when, tz.local),
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'tasks',
              'Task reminders',
              channelDescription: 'A reminder when a task you set one for is due',
              importance: Importance.high,
            ),
            iOS: DarwinNotificationDetails(),
          ),
          // Inexact, so no "alarms & reminders" permission is needed; a few minutes late is fine.
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
      _scheduled = wanted;
    } catch (_) {
      // Leave _scheduled alone so the next change tries again.
    }
  }
}
