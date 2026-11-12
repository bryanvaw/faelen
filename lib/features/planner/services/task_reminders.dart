import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../media/services/release_reminders.dart';
import '../models/task.dart';
import '../state/planner_store.dart' show timeLabel;

/// First notification id used for tasks. Release reminders use 0..n and pinned titles 100000..165535,
/// so each kind can be cleared without touching the others.
const taskNotificationBase = 200000;

/// Task ids stop here; 300000 and up belong to subscription reminders.
const taskNotificationEnd = 300000;

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

  /// How many coming dates of a repeating task get a reminder, so it keeps reminding even when
  /// the task is not ticked off and the app is not opened for a while.
  static int _ahead(Repeat r) => switch (r) {
    Repeat.none => 1,
    Repeat.daily => 7,
    Repeat.weekly => 4,
    Repeat.monthly => 3,
  };

  /// The reminders [tasks] call for as of [now]. Pure, so it can be tested.
  static List<TaskReminder> plan(Iterable<Task> tasks, DateTime now) {
    final out = <TaskReminder>[];
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    for (final t in tasks) {
      if (t.isDone || !t.remind || t.due == null) continue;
      final m = t.hasTime ? t.minutes : 9 * 60;
      var due = dayOf(t.due!);
      // A repeating task that is overdue starts from its first date that is today or later.
      if (t.repeat != Repeat.none && due.isBefore(yesterday)) due = nextDue(due, t.repeat, yesterday, monthDay: t.monthDay);
      var added = 0;
      for (var i = 0; i < _ahead(t.repeat) + 2 && added < _ahead(t.repeat); i++) {
        final when = DateTime(due.year, due.month, due.day, m ~/ 60, m % 60);
        if (when.isAfter(now)) {
          out.add(TaskReminder(when: when, title: t.title, body: t.hasTime ? 'Due at ${timeLabel(t.minutes)}' : 'Due today'));
          added++;
        }
        if (t.repeat == Repeat.none) break;
        due = dueAfter(due, t.repeat, monthDay: t.monthDay);
      }
    }
    out.sort((a, b) => a.when != b.when ? a.when.compareTo(b.when) : a.title.compareTo(b.title));
    return out.length > maxScheduled ? out.sublist(0, maxScheduled) : out;
  }

  Future<void>? _syncing; // null until the first sync, so no future is made ahead of its use

  /// Makes the scheduled task reminders match [tasks]. Calls run one after another: two at once
  /// could cancel what the other had just scheduled.
  Future<void> sync(Iterable<Task> tasks, {DateTime? now}) {
    if (!ReleaseReminders.supported) return Future.value();
    final before = _syncing;
    return _syncing = before == null ? _sync(tasks, now) : before.then((_) => _sync(tasks, now));
  }

  Future<void> _sync(Iterable<Task> tasks, DateTime? now) async {
    final wanted = plan(tasks, now ?? DateTime.now());
    if (listEquals(wanted, _scheduled)) return;
    try {
      final plugin = await _base.ensureReady();
      for (final r in await plugin.pendingNotificationRequests()) {
        if (r.id >= taskNotificationBase && r.id < taskNotificationEnd) await plugin.cancel(id: r.id);
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
