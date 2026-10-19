import '../models/media_entry.dart';

/// Reads the chapter/episode number out of a reading/watching link.
///
/// Works on the address text only (no network). Sites that use opaque ids
/// (`/viewer/839201`) have no number to find, so [detect] returns null for them.
class UrlProgress {
  const UrlProgress._();

  // Keyword followed by a number: chapter-45, ep_12, episode/7, chap.3, ch45, ?ep=3.
  static final _keyword = RegExp(
    r'(?:chapter|chap|ch|episode|ep|eps)(?:[-_./=\s]|%20)*0*(\d{1,5})(?:[-_.]\d{1,2})?(?![0-9a-z])',
    caseSensitive: false,
  );

  static final _bareKeyword = RegExp(r'^(?:chapter|chap|ch|episode|ep|eps)$', caseSensitive: false);

  /// The chapter/episode number found in [url], or null.
  static int? detect(String url) {
    final uri = normalize(url);
    if (uri == null) return null;
    // Path first (last segment wins), then the query string.
    final parts = [
      ...uri.pathSegments.reversed,
      ...uri.queryParameters.entries.map((e) => '${e.key}=${e.value}'),
    ];
    // /chapter/45 or /ep/3: keyword and number in neighbouring path segments.
    final segs = uri.pathSegments;
    for (var i = segs.length - 1; i > 0; i--) {
      final n = int.tryParse(segs[i]);
      if (n != null && n > 0 && _bareKeyword.hasMatch(segs[i - 1])) return n;
    }
    for (final part in parts) {
      final m = _keyword.allMatches(part).lastOrNull;
      if (m != null) {
        final n = int.tryParse(m.group(1)!);
        if (n != null && n > 0) return n;
      }
    }
    return null;
  }

  /// Adds https:// when a bare address was pasted. Null if it is not a usable web link.
  static Uri? normalize(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final uri = Uri.tryParse(s.contains('://') ? s : 'https://$s');
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https') || !uri.host.contains('.')) return null;
    return uri;
  }
}

/// Finds a season number ("Season 2", "2nd season", "s02", "S1E5") in a link or a title.
/// Address/title text only, no network. Returns null when there is none.
class SeasonDetect {
  const SeasonDetect._();

  static const _words = {
    'first': 1, 'second': 2, 'third': 3, 'fourth': 4, 'fifth': 5, 'sixth': 6, 'seventh': 7, 'eighth': 8,
  };

  static final _season = RegExp(r'season(?:[\s\-_.=]|%20)*0*(\d{1,2})(?!\d)', caseSensitive: false);
  static final _ordinal = RegExp(r'(?<!\d)(\d{1,2})(?:st|nd|rd|th)(?:[\s\-_.]|%20)*season', caseSensitive: false);
  static final _word = RegExp(r'\b(first|second|third|fourth|fifth|sixth|seventh|eighth)(?:[\s\-_.]|%20)*season', caseSensitive: false);
  static final _short = RegExp(r'(?<![a-z0-9])s0*(\d{1,2})(?=(?:[\s\-_.]*e(?:p)?\d)|(?![a-z0-9]))', caseSensitive: false);

  /// The season in free text such as a page title.
  static int? fromText(String text) {
    int? ok(int? n) => (n != null && n >= 1 && n <= 30) ? n : null;
    var m = _season.firstMatch(text);
    if (m != null) return ok(int.tryParse(m.group(1)!));
    m = _ordinal.firstMatch(text);
    if (m != null) return ok(int.tryParse(m.group(1)!));
    m = _word.firstMatch(text);
    if (m != null) return _words[m.group(1)!.toLowerCase()];
    m = _short.firstMatch(text);
    return m == null ? null : ok(int.tryParse(m.group(1)!));
  }

  /// The season in a link: path segments (last wins), `/season/2`, then the query string.
  static int? fromUrl(String url) {
    final uri = UrlProgress.normalize(url);
    if (uri == null) return null;
    final segs = uri.pathSegments;
    for (var i = segs.length - 1; i > 0; i--) {
      final n = int.tryParse(segs[i]);
      if (n != null && n >= 1 && n <= 30 && segs[i - 1].toLowerCase() == 'season') return n;
    }
    for (final part in [...segs.reversed, ...uri.queryParameters.entries.map((e) => '${e.key}=${e.value}')]) {
      final n = fromText(part);
      if (n != null) return n;
    }
    return null;
  }
}

/// Guesses the media type from a link, so pasting a reading link does not leave the form on Anime.
/// Only reading sites are recognised: "episode" links could be anime or a drama, so they return null.
class TypeGuess {
  const TypeGuess._();

  static final _readingWord = RegExp(r'^(?:manga|manhwa|manhua|comic|comics|webtoon|webtoons|series-comic)$', caseSensitive: false);
  static final _chapter = RegExp(r'(?:^|[-_/.=])(?:chapter|chap)(?:[-_./=]|%20)*\d', caseSensitive: false);
  static final _readingHost = RegExp(r'(manga|manhwa|manhua|webtoon|comic|scans?|asura)', caseSensitive: false);

  static MediaType? fromUrl(String url) {
    final uri = UrlProgress.normalize(url);
    if (uri == null) return null;
    final host = uri.host.replaceFirst(RegExp(r'^(www|m)\.'), '').split('.').first;
    if (_readingHost.hasMatch(host)) return MediaType.manhwa;
    if (uri.pathSegments.any(_readingWord.hasMatch)) return MediaType.manhwa;
    final path = Uri.decodeComponent(uri.path);
    if (_chapter.hasMatch(path) || uri.queryParameters.keys.any((k) => k.toLowerCase().startsWith('chap'))) {
      return MediaType.manhwa;
    }
    return null;
  }
}
