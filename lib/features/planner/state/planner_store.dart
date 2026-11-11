import 'package:flutter/foundation.dart';

import '../models/task.dart';
import '../services/planner_repo.dart';

/// The three lists on the Planner screen.
enum PlannerView { today, upcoming, done }

/// A run of tasks under one heading ("Overdue", "Today", "Tomorrow", "Someday", ...).
class TaskGroup {
  const TaskGroup(this.title, this.tasks, {this.overdue = false});
  final String title;
  final List<Task> tasks;
  final bool overdue;
}

class PlannerStore extends ChangeNotifier {
  PlannerStore(this._repo, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final PlannerRepo _repo;
  final DateTime Function() _now;

  List<Task> _tasks = [];
  bool loading = true;
  String? error;
  int _seq = 0;

  List<Task> get tasks => List.unmodifiable(_tasks);
  DateTime get today => dayOf(_now());

  Future<void> load() async {
    try {
      _tasks = await _repo.load();
      error = null;
    } catch (e) {
      error = 'Your tasks could not be loaded ($e)';
    }
    loading = false;
    notifyListeners();
  }

  String newId() => '${_now().microsecondsSinceEpoch}-${_seq++}';

  // ---- views ----

  bool _isOverdue(Task t) => !t.isDone && t.due != null && t.due!.isBefore(today);

  /// Overdue and due today are one list: everything that wants attention now.
  int get overdueCount => _tasks.where(_isOverdue).length;
  int get todayCount => _tasks.where((t) => !t.isDone && t.due != null && !t.due!.isAfter(today)).length;
  int get upcomingCount => _tasks.where((t) => !t.isDone && (t.due == null || t.due!.isAfter(today))).length;
  int get doneCount => _tasks.where((t) => t.isDone).length;

  int count(PlannerView v) => switch (v) {
    PlannerView.today => todayCount,
    PlannerView.upcoming => upcomingCount,
    PlannerView.done => doneCount,
  };

  /// Earlier time first, a timed task before an untimed one, then the more important, then the older.
  static int _byTime(Task a, Task b) {
    if (a.hasTime != b.hasTime) return a.hasTime ? -1 : 1;
    if (a.hasTime && a.minutes != b.minutes) return a.minutes.compareTo(b.minutes);
    if (a.priority != b.priority) return b.priority.index.compareTo(a.priority.index);
    return a.createdAt.compareTo(b.createdAt);
  }

  List<TaskGroup> groups(PlannerView view, {String query = ''}) {
    final q = query.trim().toLowerCase();
    bool match(Task t) => q.isEmpty || t.title.toLowerCase().contains(q);
    final t0 = today;
    switch (view) {
      case PlannerView.today:
        final open = _tasks.where((t) => !t.isDone && t.due != null && !t.due!.isAfter(t0) && match(t));
        final late = open.where((t) => t.due!.isBefore(t0)).toList()
          ..sort((a, b) => a.due != b.due ? a.due!.compareTo(b.due!) : _byTime(a, b));
        final now = open.where((t) => !t.due!.isBefore(t0)).toList()..sort(_byTime);
        return [
          if (late.isNotEmpty) TaskGroup('Overdue', late, overdue: true),
          if (now.isNotEmpty) TaskGroup('Today', now),
        ];
      case PlannerView.upcoming:
        final open = _tasks.where((t) => !t.isDone && (t.due == null || t.due!.isAfter(t0)) && match(t));
        final byDay = <int, List<Task>>{};
        final someday = <Task>[];
        for (final t in open) {
          if (t.due == null) {
            someday.add(t);
          } else {
            byDay.putIfAbsent(dayKey(t.due!), () => []).add(t);
          }
        }
        final keys = byDay.keys.toList()..sort();
        return [
          for (final k in keys) TaskGroup(dayLabel(parseDayKey(k)!, t0), byDay[k]!..sort(_byTime)),
          if (someday.isNotEmpty) TaskGroup('No date', someday..sort(_byTime)),
        ];
      case PlannerView.done:
        final done = _tasks.where((t) => t.isDone && match(t)).toList()..sort((a, b) => b.doneAt!.compareTo(a.doneAt!));
        final byDay = <int, List<Task>>{};
        for (final t in done) {
          byDay.putIfAbsent(dayKey(t.doneAt!), () => []).add(t);
        }
        return [for (final e in byDay.entries) TaskGroup(dayLabel(parseDayKey(e.key)!, t0), e.value)];
    }
  }

  // ---- changes ----

  Future<void> _put(Task t) async {
    final i = _tasks.indexWhere((x) => x.id == t.id);
    if (i < 0) {
      _tasks = [..._tasks, t];
    } else {
      _tasks = [..._tasks]..[i] = t;
    }
    error = null;
    notifyListeners();
    try {
      await _repo.put(t);
    } catch (_) {
      error = 'Could not save your task. Try again.';
      notifyListeners();
    }
  }

  Future<void> add(Task t) => _put(t);

  Future<void> update(Task t) => _put(t.copyWith(updatedAt: _now()));

  Future<void> remove(String id) async {
    _tasks = [
      for (final t in _tasks)
        if (t.id != id) t,
    ];
    notifyListeners();
    try {
      await _repo.delete(id);
    } catch (_) {
      error = 'Could not delete your task. Try again.';
      notifyListeners();
    }
  }

  /// Puts a task back exactly as it was (Undo after a delete or a completion).
  Future<void> restore(Task t) => _put(t);

  /// Finishes [t], or brings a finished task back. A repeating task does not go to Done: its day moves
  /// to the next one. Returns the task as it was before, for Undo.
  Future<Task> toggle(Task t) async {
    final now = _now();
    final Task next;
    if (t.isDone) {
      next = t.copyWith(clearDone: true, updatedAt: now);
    } else if (t.repeat != Repeat.none) {
      final from = t.due ?? today;
      // Remember the day a monthly task belongs on, so the 31st does not become the 28th for good.
      final day = t.repeat != Repeat.monthly ? 0 : (t.monthDay > 0 ? t.monthDay : from.day);
      next = t.copyWith(due: nextDue(from, t.repeat, today, monthDay: day), monthDay: day, updatedAt: now);
    } else {
      next = t.copyWith(doneAt: now, updatedAt: now);
    }
    await _put(next);
    return t;
  }

  /// What a completed repeating task moved to, for the "Next Sat" message. Null for a one-off.
  DateTime? movedTo(String id) {
    for (final t in _tasks) {
      if (t.id == id && !t.isDone && t.repeat != Repeat.none) return t.due;
    }
    return null;
  }

  Future<void> clearDone() async {
    final gone = _tasks.where((t) => t.isDone).map((t) => t.id).toList();
    _tasks = [
      for (final t in _tasks)
        if (!t.isDone) t,
    ];
    notifyListeners();
    for (final id in gone) {
      try {
        await _repo.delete(id);
      } catch (_) {}
    }
  }

  // ---- backup ----

  List<Map<String, Object?>> exportData() => [for (final t in _tasks) t.toJson()];

  /// Reads the `planner` part of a backup; damaged rows are skipped. Merge keeps the newer copy of a
  /// task that is in both. Throws [FormatException] if [raw] is not a list of tasks.
  Future<int> importData(Object? raw, {required bool replace}) async {
    if (raw is! List) throw const FormatException('Backup has no planner data');
    final incoming = [for (final j in raw) ?Task.fromJson(j)];
    final List<Task> out;
    if (replace) {
      out = incoming;
    } else {
      final byId = {for (final t in _tasks) t.id: t};
      for (final t in incoming) {
        final old = byId[t.id];
        if (old == null || t.updatedAt.isAfter(old.updatedAt)) byId[t.id] = t;
      }
      out = byId.values.toList();
    }
    await _repo.replaceAll(out);
    _tasks = out;
    notifyListeners();
    return incoming.length;
  }
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "Today", "Tomorrow", "Yesterday", otherwise "Sat, Nov 14" (with the year when it is not this one).
String dayLabel(DateTime d, DateTime today) {
  final diff = dayOf(d).difference(dayOf(today)).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff == -1) return 'Yesterday';
  final base = '${_weekdays[d.weekday - 1]}, ${_months[d.month - 1]} ${d.day}';
  return d.year == today.year ? base : '$base, ${d.year}';
}

/// `9:00 AM`, `12:30 PM`.
String timeLabel(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:${m.toString().padLeft(2, '0')} ${h < 12 ? 'AM' : 'PM'}';
}
