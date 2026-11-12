import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../media/services/release_reminders.dart';
import '../models/budget_models.dart';

/// First notification id used for subscriptions. Release reminders use 0..n, pinned titles
/// 100000..165535 and task reminders 200000.., so each kind can be cleared without touching the others.
const subscriptionNotificationBase = 300000;

/// One notification for one subscription, at one moment.
class SubscriptionReminder {
  const SubscriptionReminder({required this.when, required this.title, required this.body});
  final DateTime when;
  final String title;
  final String body;

  @override
  bool operator ==(Object other) => other is SubscriptionReminder && other.when == when && other.title == title && other.body == body;

  @override
  int get hashCode => Object.hash(when, title, body);
}

/// A notification at 9:00, [Subscription.remindDays] days before each active subscription's next charge
/// (the same morning when the charge is today or tomorrow and the reminder time has passed is skipped).
/// Only the next charge is scheduled; once it is added the next sync schedules the one after.
/// Everything is local, and a free trial gets a different wording so it is not missed.
class SubscriptionReminders {
  SubscriptionReminders(this._base);
  final ReleaseReminders _base;

  static const maxScheduled = 40;
  static const _hour = 9;

  List<SubscriptionReminder>? _scheduled;

  /// The reminders [subs] call for as of [now]. Pure, so it can be tested.
  static List<SubscriptionReminder> plan(Iterable<Subscription> subs, DateTime now) {
    final out = <SubscriptionReminder>[];
    for (final s in subs) {
      if (!s.active || s.remindDays <= 0) continue;
      final day = DateTime(s.next.year, s.next.month, s.next.day - s.remindDays, _hour);
      if (!day.isAfter(now)) continue;
      final amount = peso(s.cents, compact: true);
      final when = s.remindDays == 1 ? 'tomorrow' : 'in ${s.remindDays} days';
      out.add(SubscriptionReminder(
        when: day,
        title: s.trial ? '${s.name} trial ends $when' : '${s.name} renews $when',
        body: s.trial ? 'Cancel before then if you do not want to pay $amount.' : '$amount will be charged.',
      ));
    }
    out.sort((a, b) => a.when != b.when ? a.when.compareTo(b.when) : a.title.compareTo(b.title));
    return out.length > maxScheduled ? out.sublist(0, maxScheduled) : out;
  }

  Future<void>? _syncing;

  /// Makes the scheduled subscription reminders match [subs]. Calls run one after another: two at once
  /// could cancel what the other had just scheduled.
  Future<void> sync(Iterable<Subscription> subs, {DateTime? now}) {
    if (!ReleaseReminders.supported) return Future.value();
    final before = _syncing;
    return _syncing = before == null ? _sync(subs, now) : before.then((_) => _sync(subs, now));
  }

  Future<void> _sync(Iterable<Subscription> subs, DateTime? now) async {
    final wanted = plan(subs, now ?? DateTime.now());
    if (listEquals(wanted, _scheduled)) return;
    try {
      final plugin = await _base.ensureReady();
      for (final r in await plugin.pendingNotificationRequests()) {
        if (r.id >= subscriptionNotificationBase) await plugin.cancel(id: r.id);
      }
      var id = subscriptionNotificationBase;
      for (final r in wanted) {
        await plugin.zonedSchedule(
          id: id++,
          title: r.title,
          body: r.body,
          scheduledDate: tz.TZDateTime.from(r.when, tz.local),
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'subscriptions',
              'Subscription renewals',
              channelDescription: 'A heads-up before a subscription renews or a free trial ends',
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
