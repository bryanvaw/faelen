/// How often a task comes back after it is done.
enum Repeat {
  none('Never'),
  daily('Daily'),
  weekly('Weekly'),
  monthly('Monthly');

  const Repeat(this.label);
  final String label;
}

enum Priority {
  low('Low'),
  normal('Normal'),
  high('High');

  const Priority(this.label);
  final String label;
}

/// The calendar day of [d] at midnight, local time.
DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

/// One task. [due] is a calendar day (or null for "no date"); [minutes] is the time of day as
/// minutes after midnight, or -1 for "no time". A repeating task never sits in Done: finishing it
/// moves [due] to the next day it falls on.
class Task {
  const Task({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.due,
    this.minutes = -1,
    this.priority = Priority.normal,
    this.repeat = Repeat.none,
    this.remind = false,
    this.doneAt,
  });

  final String id;
  final String title;
  final DateTime? due;
  final int minutes;
  final Priority priority;
  final Repeat repeat;
  final bool remind;
  final DateTime? doneAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isDone => doneAt != null;
  bool get hasTime => minutes >= 0;

  /// When a reminder fires: the due time, or 9:00 for a task with a day but no time.
  DateTime? get remindAt {
    final d = due;
    if (d == null) return null;
    final m = hasTime ? minutes : 9 * 60;
    return DateTime(d.year, d.month, d.day, m ~/ 60, m % 60);
  }

  Task copyWith({
    String? title,
    DateTime? due,
    bool clearDue = false,
    int? minutes,
    Priority? priority,
    Repeat? repeat,
    bool? remind,
    DateTime? doneAt,
    bool clearDone = false,
    DateTime? updatedAt,
  }) => Task(
    id: id,
    title: title ?? this.title,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    due: clearDue ? null : (due ?? this.due),
    minutes: minutes ?? this.minutes,
    priority: priority ?? this.priority,
    repeat: repeat ?? this.repeat,
    remind: remind ?? this.remind,
    doneAt: clearDone ? null : (doneAt ?? this.doneAt),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    't': title,
    if (due != null) 'd': dayKey(due!),
    if (hasTime) 'm': minutes,
    if (priority != Priority.normal) 'p': priority.index,
    if (repeat != Repeat.none) 'r': repeat.index,
    if (remind) 'n': true,
    if (doneAt != null) 'x': doneAt!.millisecondsSinceEpoch,
    'c': createdAt.millisecondsSinceEpoch,
    'u': updatedAt.millisecondsSinceEpoch,
  };

  /// Null when the task is unreadable, so one bad row cannot hide the rest.
  static Task? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], t = j['t'];
    if (id is! String || id.isEmpty || t is! String || t.trim().isEmpty) return null;
    DateTime? ms(Object? v) => v is int ? DateTime.fromMillisecondsSinceEpoch(v) : null;
    final m = j['m'];
    final p = j['p'], r = j['r'];
    final created = ms(j['c']) ?? DateTime.fromMillisecondsSinceEpoch(0);
    return Task(
      id: id,
      title: t.trim(),
      due: parseDayKey(j['d']),
      minutes: m is int && m >= 0 && m < 1440 ? m : -1,
      priority: p is int && p >= 0 && p < Priority.values.length ? Priority.values[p] : Priority.normal,
      repeat: r is int && r >= 0 && r < Repeat.values.length ? Repeat.values[r] : Repeat.none,
      remind: j['n'] == true,
      doneAt: ms(j['x']),
      createdAt: created,
      updatedAt: ms(j['u']) ?? created,
    );
  }
}

/// `20261104` for 4 November 2026: sortable, and it has no time zone to go wrong.
int dayKey(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

DateTime? parseDayKey(Object? v) {
  if (v is! int) return null;
  final y = v ~/ 10000, m = (v ~/ 100) % 100, d = v % 100;
  if (y < 1900 || y > 2200 || m < 1 || m > 12 || d < 1 || d > 31) return null;
  final out = DateTime(y, m, d);
  return out.month == m ? out : null;
}

/// The day a repeating task falls on next, strictly after [today] (so finishing a task that is days
/// overdue does not leave it overdue again).
DateTime nextDue(DateTime due, Repeat repeat, DateTime today) {
  var d = dayOf(due);
  final t = dayOf(today);
  switch (repeat) {
    case Repeat.none:
      return d;
    case Repeat.daily:
    case Repeat.weekly:
      final step = repeat == Repeat.daily ? 1 : 7;
      // Jump in whole steps instead of looping, so a task from last year is still instant.
      final gap = t.difference(d).inDays;
      if (gap >= 0) d = DateTime(d.year, d.month, d.day + ((gap ~/ step) + 1) * step);
      return d;
    case Repeat.monthly:
      final day = d.day;
      while (!d.isAfter(t)) {
        final first = DateTime(d.year, d.month + 1, 1);
        final last = DateTime(first.year, first.month + 1, 0).day;
        d = DateTime(first.year, first.month, day > last ? last : day);
      }
      return d;
  }
}
