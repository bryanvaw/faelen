import 'package:faelen/features/media/models/media_entry.dart';
import 'package:faelen/features/media/services/release_reminders.dart';
import 'package:faelen/features/media/services/release_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

MediaEntry entry({List<int> days = const [2], int count = 10, int current = 8, int total = 0, DateTime? on, Status status = Status.watching, MediaType type = MediaType.anime}) =>
    MediaEntry(
      id: 'a',
      title: 'A',
      type: type,
      status: status,
      current: current,
      total: total,
      releaseDays: days,
      releasedCount: count,
      releasedOn: (on ?? DateTime(2026, 10, 12)).millisecondsSinceEpoch, // a Monday
    );

void main() {
  test('same day as the anchor adds nothing', () {
    final s = releaseStatus(entry(), DateTime(2026, 10, 12))!;
    expect(s.released, 10);
    expect(s.behind, 2);
  });

  test('one more arrives each scheduled weekday', () {
    expect(releaseStatus(entry(), DateTime(2026, 10, 13))!.released, 11); // Tuesday
    expect(releaseStatus(entry(), DateTime(2026, 10, 19))!.released, 11); // next Monday
    expect(releaseStatus(entry(), DateTime(2026, 10, 20))!.released, 12); // next Tuesday
  });

  test('anchor on the release day does not count that day twice', () {
    final s = releaseStatus(entry(on: DateTime(2026, 10, 13)), DateTime(2026, 10, 13))!;
    expect(s.released, 10);
    expect(releaseStatus(entry(on: DateTime(2026, 10, 13)), DateTime(2026, 10, 20))!.released, 11);
  });

  test('next release is strictly after today', () {
    final s = releaseStatus(entry(), DateTime(2026, 10, 13))!; // Tuesday
    expect(s.nextRelease, DateTime.utc(2026, 10, 20));
  });

  test('capped at the total; finished series has no next release', () {
    final s = releaseStatus(entry(total: 12, current: 12), DateTime(2026, 12, 1))!;
    expect(s.released, 12);
    expect(s.behind, 0);
    expect(s.nextRelease, isNull);
  });

  test('ahead of the schedule is never negative', () {
    expect(releaseStatus(entry(current: 20), DateTime(2026, 10, 12))!.behind, 0);
  });

  test('only followed manhwa/anime with a schedule', () {
    expect(releaseStatus(entry(status: Status.completed), DateTime(2026, 10, 12)), isNull);
    expect(releaseStatus(entry(type: MediaType.movie), DateTime(2026, 10, 12)), isNull);
    expect(releaseStatus(entry(days: const []), DateTime(2026, 10, 12)), isNull);
  });

  test('schedule survives a JSON round trip; unscheduled entries stay lean', () {
    final back = MediaEntry.fromJson(entry().toJson());
    expect(back.releaseDays, [2]);
    expect(back.releasedCount, 10);
    expect(entry(days: const []).toJson().containsKey('releaseDays'), isFalse);
  });

  group('several days a week', () {
    // Dramas often air Sat + Sun. Anchor: Monday 12 Oct with 10 out.
    final drama = entry(days: const [6, 7], type: MediaType.drama);

    test('each listed day adds one', () {
      expect(releaseStatus(drama, DateTime(2026, 10, 16))!.released, 10); // Friday
      expect(releaseStatus(drama, DateTime(2026, 10, 17))!.released, 11); // Saturday
      expect(releaseStatus(drama, DateTime(2026, 10, 18))!.released, 12); // Sunday
      expect(releaseStatus(drama, DateTime(2026, 10, 19))!.released, 12); // Monday
      expect(releaseStatus(drama, DateTime(2026, 10, 24))!.released, 13); // next Saturday
      expect(releaseStatus(drama, DateTime(2026, 11, 2))!.released, 16); // three weekends later
    });

    test('next release is the nearest listed day', () {
      expect(releaseStatus(drama, DateTime(2026, 10, 14))!.nextRelease, DateTime.utc(2026, 10, 17));
      expect(releaseStatus(drama, DateTime(2026, 10, 17))!.nextRelease, DateTime.utc(2026, 10, 18));
      expect(releaseStatus(drama, DateTime(2026, 10, 18))!.nextRelease, DateTime.utc(2026, 10, 24));
    });

    test('describeDays reads naturally', () {
      expect(describeDays(const [6]), 'Sat');
      expect(describeDays(const [6, 7]), 'Sat & Sun');
      expect(describeDays(const [1, 3, 5]), 'Mon, Wed & Fri');
    });

    test('one reminder per day, at the entry time or the default', () {
      final plan = ReleaseReminders.plan([drama, drama.copyWith(releaseMinutes: 20 * 60 + 30)], DateTime(2026, 10, 13));
      expect(plan.map((r) => '${r.weekday}@${r.minutes}'), ['6@540', '6@1230', '7@540', '7@1230']);
    });

    test('old single-day backups still load', () {
      final j = entry().toJson()..remove('releaseDays')..['releaseDay'] = 3;
      expect(MediaEntry.fromJson(j).releaseDays, [3]);
    });
  });

  group('reminder plan', () {
    final now = DateTime(2026, 10, 13);

    test('one weekly reminder per followed entry, ordered by weekday', () {
      final plan = ReleaseReminders.plan([entry(days: const [5]), entry(days: const [2], type: MediaType.manhwa)], now);
      expect(plan.map((r) => r.weekday), [2, 5]);
      expect(plan.first.body, 'A new chapter is out today.');
      expect(plan.last.body, 'A new episode is out today.');
    });

    test('skips completed, unscheduled and fully released series', () {
      final plan = ReleaseReminders.plan([
        entry(status: Status.completed),
        entry(days: const []),
        entry(total: 10, count: 10, current: 10),
      ], now);
      expect(plan, isEmpty);
    });
  });
}
