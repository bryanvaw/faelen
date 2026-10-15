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
