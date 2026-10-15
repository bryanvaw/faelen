import 'dart:math';

enum MediaType {
  manhwa('Manhwa'),
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
      };

  factory MediaEntry.fromJson(Map<String, dynamic> j) => MediaEntry(
        id: j['id'] as String,
        title: j['title'] as String,
        type: MediaType.parse(j['type'] as String?),
        status: Status.parse(j['status'] as String?),
        current: (j['current'] as num?)?.toInt() ?? 0,
        total: (j['total'] as num?)?.toInt() ?? 0,
        rating: (j['rating'] as num?)?.toInt() ?? 0,
        notes: (j['notes'] as String?) ?? '',
        updatedAt: (j['updatedAt'] as num?)?.toInt() ?? 0,
        cover: j['cover'] as String?,
        url: (j['url'] as String?) ?? '',
      );
}
