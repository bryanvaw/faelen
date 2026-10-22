import '../models/media_entry.dart';

/// Where a weekly release schedule stands today. Pure date maths, no network.
class ReleaseStatus {
  const ReleaseStatus({required this.released, required this.behind, required this.nextRelease});

  /// Chapters/episodes out so far (capped at the total when it is known).
  final int released;

  /// Out but not yet read/watched.
  final int behind;

  /// Date of the next release after today, or null once the whole series is out.
  final DateTime? nextRelease;
}

const weekdayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// "Sat", "Sat & Sun" or "Mon, Wed & Fri".
String describeDays(List<int> days) {
  final names = [for (final d in days) weekdayShort[d - 1]];
  if (names.length < 2) return names.join();
  return '${names.sublist(0, names.length - 1).join(', ')} & ${names.last}';
}

/// Only ongoing shows you are following have a schedule worth showing.
bool tracksReleases(MediaEntry e) =>
    e.releaseDays.isNotEmpty &&
    e.type != MediaType.movie &&
    (e.status == Status.watching || e.status == Status.onHold);

/// [entry]'s release count on [now]: the user said [MediaEntry.releasedCount] were out on
/// [MediaEntry.releasedOn], and one more comes out on each of [MediaEntry.releaseDays] after that.
ReleaseStatus? releaseStatus(MediaEntry entry, DateTime now) {
  if (!tracksReleases(entry)) return null;
  // Whole days between calendar dates, in UTC so daylight saving never shifts the count.
  DateTime day(DateTime d) => DateTime.utc(d.year, d.month, d.day);
  final today = day(now);
  final anchor = day(DateTime.fromMillisecondsSinceEpoch(entry.releasedOn));
  final days = today.difference(anchor).inDays;
  final weekdays = entry.releaseDays.toSet();

  var fresh = 0;
  if (days > 0) {
    fresh = (days ~/ 7) * weekdays.length;
    for (var i = 1; i <= days % 7; i++) {
      if (weekdays.contains(anchor.add(Duration(days: i)).weekday)) fresh++;
    }
  }
  var released = entry.releasedCount + fresh;
  if (entry.total > 0 && released > entry.total) released = entry.total;

  final finished = entry.total > 0 && released >= entry.total;
  DateTime? next;
  if (!finished) {
    for (var i = 1; i <= 7; i++) {
      final d = today.add(Duration(days: i));
      if (weekdays.contains(d.weekday)) {
        next = d;
        break;
      }
    }
  }
  final behind = released - entry.current;
  return ReleaseStatus(released: released, behind: behind < 0 ? 0 : behind, nextRelease: next);
}

/// Keeps a release schedule from counting while a show is not being followed. Call it with the
/// entry as it was and as it is about to be saved:
///
/// * leaving Watching/On Hold freezes the count at what was out that day;
/// * coming back starts counting again from today, so a hiatus or a stretch as Completed or
///   Dropped does not show up as a pile of "new" chapters.
MediaEntry settleSchedule(MediaEntry? before, MediaEntry after, DateTime now) {
  if (before == null || after.releaseDays.isEmpty) return after;
  final was = tracksReleases(before), will = tracksReleases(after);
  final today = now.millisecondsSinceEpoch;
  if (was && !will) {
    final out = releaseStatus(before, now)?.released ?? before.releasedCount;
    return after.copyWith(releasedCount: out, releasedOn: today);
  }
  if (!was && will && before.releaseDays.isNotEmpty && after.releasedOn == before.releasedOn && after.releasedCount == before.releasedCount) {
    return after.copyWith(releasedOn: today); // resumed, and the numbers were not edited meanwhile
  }
  return after;
}
