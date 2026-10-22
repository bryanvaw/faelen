import 'dart:math';

enum MediaType {
  manhwa('Webtoon'),
  anime('Anime'),
  movie('Movie'),
  drama('Drama');

  const MediaType(this.label);
  final String label;

  String get unit => this == manhwa ? 'Ch' : 'Ep';

  static MediaType parse(String? s) =>
      MediaType.values.firstWhere((e) => e.name == s, orElse: () => MediaType.anime);
}

enum Status {
  planToWatch('Plan to Watch'),
  watching('Currently Watching'),
  completed('Completed'),
  onHold('On Hold'),
  dropped('Dropped');

  const Status(this.label);
  final String label;

  static Status parse(String? s) =>
      Status.values.firstWhere((e) => e.name == s, orElse: () => Status.planToWatch);
}

String newId() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${Random().nextInt(1 << 30).toRadixString(36)}';

class MediaEntry {
  final String id;
  final String title;
  final MediaType type;
  final Status status;
  final int current; // current episode/chapter
  final int total; // 0 = unknown
  final int rating; // 0 = unrated, else 1-10
  final String notes;
  final int updatedAt; // ms since epoch; 0 = unknown (older entries)
  final String? cover; // file name inside the covers folder, null = no cover
  final String url; // where to continue reading/watching; '' = none
  final int season; // 0 = none/unknown
  final List<int> releaseDays; // weekdays new chapters/episodes come out (1 = Monday ... 7 = Sunday); empty = no schedule
  final int releaseMinutes; // reminder time as minutes after midnight; -1 = use the default time
  final int releasedCount; // how many were out on [releasedOn]
  final int releasedOn; // ms since epoch of the day [releasedCount] was true; counting continues weekly from there

  const MediaEntry({
    required this.id,
    required this.title,
    this.type = MediaType.anime,
    this.status = Status.planToWatch,
    this.current = 0,
    this.total = 0,
    this.rating = 0,
    this.notes = '',
    this.updatedAt = 0,
    this.cover,
    this.url = '',
    this.season = 0,
    this.releaseDays = const [],
    this.releaseMinutes = -1,
    this.releasedCount = 0,
    this.releasedOn = 0,
  });

  MediaEntry copyWith({
    String? title,
    MediaType? type,
    Status? status,
    int? current,
    int? total,
    int? rating,
    String? notes,
    int? updatedAt,
    String? cover,
    String? url,
    int? season,
    List<int>? releaseDays,
    int? releaseMinutes,
    int? releasedCount,
    int? releasedOn,
  }) =>
      MediaEntry(
        id: id,
        title: title ?? this.title,
        type: type ?? this.type,
        status: status ?? this.status,
        current: current ?? this.current,
        total: total ?? this.total,
        rating: rating ?? this.rating,
        notes: notes ?? this.notes,
        updatedAt: updatedAt ?? this.updatedAt,
        cover: cover ?? this.cover,
        url: url ?? this.url,
        season: season ?? this.season,
        releaseDays: releaseDays ?? this.releaseDays,
        releaseMinutes: releaseMinutes ?? this.releaseMinutes,
        releasedCount: releasedCount ?? this.releasedCount,
        releasedOn: releasedOn ?? this.releasedOn,
      );

  double get progress => total > 0 ? (current / total).clamp(0.0, 1.0) : 0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'type': type.name,
        'status': status.name,
        'current': current,
        'total': total,
        'rating': rating,
        'notes': notes,
        'updatedAt': updatedAt,
        if (cover != null) 'cover': cover,
        if (url.isNotEmpty) 'url': url,
        if (season > 0) 'season': season,
        if (releaseDays.isNotEmpty) ...{
          'releaseDays': releaseDays,
          'releasedCount': releasedCount,
          'releasedOn': releasedOn,
          if (releaseMinutes >= 0) 'releaseMinutes': releaseMinutes,
        },
      };

  /// Reads an entry from saved or imported JSON. Values that cannot be right (negative counts, a
  /// rating above 10, progress past the total, a link that is not a web address) are corrected, so
  /// a hand-edited or damaged backup cannot put the app in a state the form would never allow.
  factory MediaEntry.fromJson(Map<String, dynamic> j) {
    int whole(String key, [int min = 0]) => max((j[key] as num?)?.toInt() ?? 0, min);
    final total = whole('total');
    final current = whole('current');
    final link = ((j['url'] as String?) ?? '').trim();
    final scheme = Uri.tryParse(link)?.scheme.toLowerCase();
    final minutes = (j['releaseMinutes'] as num?)?.toInt() ?? -1;
    return MediaEntry(
      id: j['id'] as String,
      title: j['title'] as String,
      type: MediaType.parse(j['type'] as String?),
      status: Status.parse(j['status'] as String?),
      current: total > 0 ? min(current, total) : current,
      total: total,
      rating: whole('rating').clamp(0, 10),
      notes: (j['notes'] as String?) ?? '',
      updatedAt: whole('updatedAt'),
      cover: j['cover'] as String?,
      url: scheme == 'http' || scheme == 'https' ? link : '',
      season: whole('season').clamp(0, 99),
      releaseDays: _parseDays(j),
      releaseMinutes: minutes >= 0 && minutes < 24 * 60 ? minutes : -1,
      releasedCount: whole('releasedCount'),
      releasedOn: whole('releasedOn'),
    );
  }

  /// Reads `releaseDays`, or the single `releaseDay` that 1.3 backups used.
  static List<int> _parseDays(Map<String, dynamic> j) {
    final raw = j['releaseDays'];
    final days = raw is List
        ? raw.whereType<num>().map((n) => n.toInt())
        : [if ((j['releaseDay'] as num?)?.toInt() case final d? when d != 0) d];
    return (days.where((d) => d >= 1 && d <= 7).toSet().toList()..sort());
  }
}
