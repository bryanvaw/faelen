import 'package:faelen/features/media/models/media_entry.dart';
import 'package:faelen/features/media/services/pinned_actions.dart';
import 'package:flutter_test/flutter_test.dart';

MediaEntry entry({String id = 'a', int current = 4, int total = 0, Status status = Status.watching, MediaType type = MediaType.manhwa}) =>
    MediaEntry(id: id, title: 'T', type: type, status: status, current: current, total: total);

void main() {
  notificationText();
  test('+1 button adds one and starts a planned entry', () {
    final out = applyPinnedAction([entry(status: Status.planToWatch)], 'inc|a', now: 5)!;
    expect(out.entry.current, 5);
    expect(out.entry.status, Status.watching);
    expect(out.entry.updatedAt, 5);
    expect(out.items.single, out.entry);
  });

  test('+1 on the last chapter completes the entry and drops it from the shade', () {
    final out = applyPinnedAction([entry(current: 9, total: 10)], 'inc|a', now: 1)!;
    expect(out.entry.current, 10);
    expect(out.entry.status, Status.completed);
    expect(canPin(out.entry), isFalse);
  });

  test('Done fills the progress when the total is known', () {
    final out = applyPinnedAction([entry(current: 3, total: 12), entry(id: 'b')], 'done|a', now: 1)!;
    expect(out.entry.current, 12);
    expect(out.entry.status, Status.completed);
    expect(out.items.last.id, 'b'); // the other entry is untouched
  });

  test('unknown ids and actions change nothing', () {
    expect(applyPinnedAction([entry()], 'inc|missing', now: 1), isNull);
    expect(applyPinnedAction([entry()], 'other|a', now: 1), isNull);
  });

  test('only unfinished series can be pinned', () {
    expect(canPin(entry()), isTrue);
    expect(canPin(entry(status: Status.dropped)), isFalse);
    expect(canPin(entry(type: MediaType.movie)), isFalse);
  });

  test('notification body shows season and progress', () {
    expect(pinnedBody(entry(current: 74, total: 120)), 'Ch 74 / 120');
    expect(pinnedBody(entry(total: 0).copyWith(season: 2)), 'S2 · Ch 4 / ?');
  });

  test('notification ids are stable and stay clear of reminder ids', () {
    expect(pinnedNotificationId('abc'), pinnedNotificationId('abc'));
    expect(pinnedNotificationId('abc'), greaterThanOrEqualTo(100000));
  });
}

void notificationText() {
  test('button names the exact chapter or episode a tap records', () {
    expect(pinnedBumpLabel(entry(current: 34)), 'Read Ch 35');
    expect(pinnedBumpLabel(entry(current: 2, type: MediaType.anime)), 'Watched Ep 3');
  });

  test('release line says what is waiting, or when the next one lands', () {
    final e = entry(current: 8).copyWith(
      releaseDays: const [2],
      releasedCount: 10,
      releasedOn: DateTime(2026, 10, 12).millisecondsSinceEpoch, // a Monday
    );
    expect(pinnedReleaseLine(e, DateTime(2026, 10, 12)), '2 new waiting');
    expect(pinnedReleaseLine(e.copyWith(current: 10), DateTime(2026, 10, 12)), 'Caught up · Next Tue');
    expect(pinnedReleaseLine(entry(), DateTime(2026, 10, 12)), isNull);
  });

  test('signature changes whenever the notification text would', () {
    final now = DateTime(2026, 10, 12);
    expect(pinnedSignature(entry(), now), pinnedSignature(entry(), now));
    expect(pinnedSignature(entry(current: 5), now), isNot(pinnedSignature(entry(current: 4), now)));
  });
}
