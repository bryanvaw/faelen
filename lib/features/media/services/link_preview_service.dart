import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../../core/secrets.dart';
import '../models/media_entry.dart';

/// What a web page says about itself (its Open Graph "link preview" tags).
class LinkPreview {
  const LinkPreview({required this.title, this.images = const [], this.siteName = ''});
  final String title; // cleaned up: site name and chapter/episode suffix removed

  /// Every picture the page offers as its cover, best first (link-preview tags, then the page's
  /// structured data). The first one that downloads is used.
  final List<Uri> images;
  Uri? get imageUrl => images.isEmpty ? null : images.first;
  final String siteName;
}

/// A show found by title in a public catalogue (AniList, TVmaze), for pages that carry no cover.
class CatalogMatch {
  const CatalogMatch({this.image, this.total = 0});
  final Uri? image;
  final int total; // episodes or chapters when the catalogue knows them, else 0
}

/// Reads the title and cover image of a manhwa/anime/movie page from its link, the same
/// information chat apps use for link previews. Only the page head is read.
class LinkPreviewService {
  LinkPreviewService({
    Future<String?> Function(Uri url)? fetchPage,
    Future<Uint8List?> Function(Uri url)? fetchImage,
    Future<CatalogMatch?> Function(String title, MediaType type)? searchCatalog,
  })  : _fetchPage = fetchPage ?? _getPage,
        _customImage = fetchImage,
        _searchCatalog = searchCatalog ?? _catalog;

  final Future<String?> Function(Uri url) _fetchPage;
  final Future<Uint8List?> Function(Uri url)? _customImage;
  Uri? _lastPage; // sent as the Referer when downloading the cover, which some image hosts insist on
  final Future<CatalogMatch?> Function(String title, MediaType type) _searchCatalog;

  static const maxImageBytes = 5 * 1024 * 1024;
  static const _maxPageBytes = 1024 * 1024; // some pages put megabytes of script before their tags
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36';

  /// Null when the page can't be read or has no usable title.
  Future<LinkPreview?> preview(Uri url) async {
    _lastPage = url;
    LinkPreview? found;
    try {
      final html = await _fetchPage(url);
      if (html != null) found = parse(html, url);
    } catch (_) {
      // Handled below: the address itself usually still names the title.
    }
    final fromUrl = titleFromUrl(url);
    if (fromUrl == null) return found;
    if (found == null) return LinkPreview(title: fromUrl);
    // Single-page apps answer every address with the same site-wide title ("Asian Dramas & Movies").
    // If the page title shares no word with the address, trust the address (and not the page's
    // picture either: it is as site-wide as the title).
    return _sharesWord(found.title, fromUrl) ? found : LinkPreview(title: fromUrl, siteName: found.siteName);
  }

  static Set<String> _words(String s) =>
      RegExp(r'[a-z0-9]{3,}').allMatches(s.toLowerCase()).map((m) => m.group(0)!).toSet();

  static bool _sharesWord(String a, String b) => _words(a).intersection(_words(b)).isNotEmpty;

  static final _stopSegments = RegExp(
      r'^(watch|drama|dramas|movie|movies|film|films|anime|series|show|shows|tv|title|titles|comic|comics|manga|manhwa|manhua|'
      r'detail|details|view|read|reader|play|stream|episode|episodes|ep|chapter|chapters|season|browse|home|en|[a-z]{2}-[a-z]{2})$',
      caseSensitive: false);

  /// A readable title taken from the address slug: ".../Drama/Make-Me-Tingle--2026-/Episode-4" ->
  /// "Make Me Tingle (2026)". Null when no segment looks like a title.
  static String? titleFromUrl(Uri url) {
    for (final seg in url.pathSegments) {
      var s = seg.trim(); // pathSegments are already decoded; decoding twice throws on a literal %
      if (s.isEmpty || _stopSegments.hasMatch(s)) continue;
      // An id such as MangaDex's "32d76d19-8a05-4db0-9fc2-e0b0648fe9d0" is not a title; the slug follows it.
      if (RegExp(r'^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$', caseSensitive: false).hasMatch(s)) continue;
      if (RegExp(r'^(?:chapter|chap|ch|episode|ep|eps|season|s)[-_ ]?\d+', caseSensitive: false).hasMatch(s)) continue;
      s = s.replaceAll(RegExp(r'\.(html?|php)$', caseSensitive: false), '');
      // Trailing id such as "-1bb35e56" or "-81040344".
      s = s.replaceFirst(RegExp(r'[-_](?=[a-z0-9]*\d)[a-z0-9]{6,10}$', caseSensitive: false), '');
      final year = RegExp(r'[-_ ]+((?:19|20)\d{2})[-_ ]*$').firstMatch(s);
      if (year != null) s = s.substring(0, year.start);
      final words = s.split(RegExp(r'[-_+ ]+')).where((w) => w.isNotEmpty).toList();
      if (words.length < 2 || words.every((w) => RegExp(r'^\d+$').hasMatch(w))) continue;
      final title = words.map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');
      return year == null ? title : '$title (${year.group(1)})';
    }
    return null;
  }

  /// Looks [title] up by name when the page itself had no cover (single-page apps like Anikoto).
  /// Anime and manhwa come from AniList, dramas from TVmaze, movies from TMDB (needs the key in secrets.dart).
  Future<CatalogMatch?> findInCatalog(String title, MediaType type) async {
    try {
      return await _searchCatalog(title, type).timeout(const Duration(seconds: 30));
    } catch (_) {
      return null;
    }
  }

  /// The names worth searching a catalogue for, best first: the title without its year, then also
  /// without a season or part ("Solo Leveling Season 2" is often listed as "Solo Leveling").
  static List<String> searchTitles(String title) {
    // "Make Me Tingle (2026)" searches better as "Make Me Tingle".
    final base = title.replaceAll(RegExp(r'\s*\((?:19|20)\d{2}\)\s*$'), '').trim();
    final plain = base
        .replaceFirst(
          RegExp(r'\s*[-:–—,]?\s*\(?\b(?:season\s*\d+|\d+(?:st|nd|rd|th)\s+season|s\d{1,2}|part\s*\d+|cour\s*\d+)\b.*$', caseSensitive: false),
          '',
        )
        .trim();
    return [if (base.isNotEmpty) base, if (plain.isNotEmpty && plain != base) plain];
  }

  static Future<CatalogMatch?> _catalog(String title, MediaType type) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    // Each search is tried in turn; one that fails (offline, rate limit) does not stop the next.
    Future<CatalogMatch?> attempt(Future<CatalogMatch?> Function() search) async {
      try {
        return await search();
      } catch (_) {
        return null;
      }
    }

    try {
      CatalogMatch? partial; // a match that knows the total but has no picture
      for (final q in searchTitles(title)) {
        final searches = <Future<CatalogMatch?> Function()>[
          switch (type) {
            MediaType.anime => () => _aniList(client, q, manga: false),
            // Korean first (most webtoons), then any country: manhua and manga are read the same way.
            MediaType.manhwa => () => _aniList(client, q, manga: true, country: 'KR'),
            MediaType.drama => () => _tvMaze(client, q),
            MediaType.movie => () => _tmdb(client, 'movie', q, title),
          },
          if (type == MediaType.manhwa) () => _aniList(client, q, manga: true),
          // TVmaze misses some Asian dramas that TMDB has.
          if (type == MediaType.drama) () => _tmdb(client, 'tv', q, title),
        ];
        for (final search in searches) {
          final m = await attempt(search);
          if (m?.image != null) return CatalogMatch(image: m!.image, total: m.total > 0 ? m.total : (partial?.total ?? 0));
          if (m != null && m.total > 0) partial ??= m;
        }
      }
      return partial;
    } finally {
      client.close(force: true);
    }
  }

  static Future<CatalogMatch?> _aniList(HttpClient client, String q, {required bool manga, String? country}) async {
    final req = await client.postUrl(Uri.parse('https://graphql.anilist.co'));
    req.headers
      ..set(HttpHeaders.contentTypeHeader, 'application/json')
      ..set(HttpHeaders.acceptHeader, 'application/json');
    req.add(utf8.encode(jsonEncode({
      'query': aniListQuery,
      'variables': {'s': q, 't': manga ? 'MANGA' : 'ANIME', 'c': ?country},
    })));
    final res = await req.close().timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) {
      await res.drain<void>();
      return null; // 404 = nothing by that name
    }
    final body = utf8.decode(await _readLimited(res, 256 * 1024), allowMalformed: true);
    return parseAniList(jsonDecode(body), manga: manga);
  }

  static Future<CatalogMatch?> _tvMaze(HttpClient client, String q) async {
    final res = await _open(client, Uri.https('api.tvmaze.com', '/search/shows', {'q': q}), 'application/json');
    if (res.statusCode != 200) {
      await res.drain<void>();
      return null;
    }
    final body = utf8.decode(await _readLimited(res, 256 * 1024), allowMalformed: true);
    return parseTvMaze(jsonDecode(body));
  }

  /// [kind] is `movie` or `tv`. Needs the key in secrets.dart; without it there is nothing to ask.
  static Future<CatalogMatch?> _tmdb(HttpClient client, String kind, String q, String title) async {
    if (tmdbApiKey.isEmpty) return null;
    final year = kind == 'movie' ? RegExp(r'\((19|20)(\d{2})\)\s*$').firstMatch(title) : null;
    final res = await _open(
      client,
      Uri.https('api.themoviedb.org', '/3/search/$kind', {
        'api_key': tmdbApiKey,
        'query': q,
        if (year != null) 'year': '${year.group(1)}${year.group(2)}',
      }),
      'application/json',
    );
    if (res.statusCode != 200) {
      await res.drain<void>();
      return null;
    }
    final body = utf8.decode(await _readLimited(res, 256 * 1024), allowMalformed: true);
    return parseTmdb(jsonDecode(body));
  }

  static const aniListQuery = r'query($s:String,$t:MediaType,$c:CountryCode){Media(search:$s,type:$t,countryOfOrigin:$c,sort:SEARCH_MATCH)'
      r'{title{english romaji}coverImage{extraLarge large}episodes chapters}}';

  /// The cover and size from an AniList `Media(search:)` response, or null when nothing matched.
  static CatalogMatch? parseAniList(Object? json, {required bool manga}) {
    Object? media;
    if (json is Map) {
      final data = json['data'];
      if (data is Map) media = data['Media'];
    }
    if (media is! Map) return null;
    final cover = media['coverImage'];
    final url = (cover is Map) ? (cover['extraLarge'] ?? cover['large']) : null;
    final total = media[manga ? 'chapters' : 'episodes'];
    return CatalogMatch(
      image: (url is String) ? Uri.tryParse(url) : null,
      total: total is int && total > 0 ? total : 0,
    );
  }

  /// The first TMDB movie search result that has a poster.
  static CatalogMatch? parseTmdb(Object? json) {
    final results = (json is Map) ? json['results'] : null;
    if (results is! List) return null;
    for (final r in results) {
      final path = (r is Map) ? r['poster_path'] : null;
      if (path is String && path.startsWith('/')) {
        return CatalogMatch(image: Uri.parse('https://image.tmdb.org/t/p/w500$path'));
      }
    }
    return null;
  }

  /// The first TVmaze search result that has a poster.
  static CatalogMatch? parseTvMaze(Object? json) {
    if (json is! List) return null;
    for (final hit in json) {
      final show = (hit is Map) ? hit['show'] : null;
      final img = (show is Map) ? show['image'] : null;
      final url = (img is Map) ? (img['original'] ?? img['medium']) : null;
      if (url is String) {
        final uri = Uri.tryParse(url);
        // TVmaze serves http addresses; the https twin works and Android blocks cleartext.
        return CatalogMatch(image: uri?.scheme == 'http' ? uri!.replace(scheme: 'https') : uri);
      }
    }
    return null;
  }

  /// The image bytes, or null if it isn't a picture the app can show or is too big.
  Future<Uint8List?> downloadImage(Uri url) async {
    final custom = _customImage;
    if (custom != null) {
      try {
        return await custom(url);
      } catch (_) {
        return null;
      }
    }
    // Android refuses plain http, and nearly every image host also answers on https.
    final secure = url.scheme == 'http' ? url.replace(scheme: 'https') : url;
    // Some hosts want the page as Referer, others refuse any Referer that is not their own site.
    for (final (target, referer) in [(secure, _lastPage), (secure, null), if (secure != url) (url, _lastPage)]) {
      try {
        final bytes = await _getImage(target, referer: referer);
        if (bytes != null && looksLikeImage(bytes)) return bytes;
      } catch (_) {
        // blocked, offline or timed out: try the next way, then the caller falls back
      }
    }
    return null;
  }

  /// True for the formats the app can draw (JPEG, PNG, GIF, WebP, BMP), judged by the first bytes
  /// because servers often mislabel pictures ("application/octet-stream") or send an error page
  /// labelled as one. AVIF and SVG are left out: they would save but show as a blank cover.
  static bool looksLikeImage(List<int> b) {
    bool at(int i, List<int> sig) {
      if (b.length < i + sig.length) return false;
      for (var k = 0; k < sig.length; k++) {
        if (b[i + k] != sig[k]) return false;
      }
      return true;
    }

    return at(0, const [0xFF, 0xD8, 0xFF]) || // JPEG
        at(0, const [0x89, 0x50, 0x4E, 0x47]) || // PNG
        at(0, const [0x47, 0x49, 0x46, 0x38]) || // GIF
        (at(0, const [0x52, 0x49, 0x46, 0x46]) && at(8, const [0x57, 0x45, 0x42, 0x50])) || // WebP
        at(0, const [0x42, 0x4D]); // BMP
  }

  // --- Parsing ---------------------------------------------------------------

  static final _metaTag = RegExp(r'<meta\s[^>]*>', caseSensitive: false);
  static final _attr = RegExp(r'''([a-zA-Z:_-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))''');
  static final _linkTag = RegExp(r'<link\s[^>]*>', caseSensitive: false);
  static final _jsonLd = RegExp(r'<script[^>]*application/ld\+json[^>]*>(.*?)</script>', caseSensitive: false, dotAll: true);

  static Map<String, String> _attrs(String tag) => {
        for (final a in _attr.allMatches(tag)) a.group(1)!.toLowerCase(): a.group(2) ?? a.group(3) ?? a.group(4) ?? '',
      };

  /// Pictures named in the page's structured data (`"image"` / `"thumbnailUrl"` in JSON-LD), which
  /// many sites fill in even when they have no link-preview tags.
  static List<String> _jsonLdImages(String html) {
    final out = <String>[];
    void take(Object? v) {
      if (v is String) {
        out.add(v);
      } else if (v is List) {
        v.forEach(take);
      } else if (v is Map) {
        take(v['url'] ?? v['contentUrl']);
      }
    }

    void walk(Object? node, int depth) {
      if (depth > 6) return;
      if (node is List) {
        for (final n in node) {
          walk(n, depth + 1);
        }
      } else if (node is Map) {
        take(node['image']);
        take(node['thumbnailUrl']);
        for (final e in node.entries) {
          if (e.key != 'image' && e.key != 'thumbnailUrl' && (e.value is Map || e.value is List)) walk(e.value, depth + 1);
        }
      }
    }

    for (final m in _jsonLd.allMatches(html)) {
      try {
        walk(jsonDecode(m.group(1)!.trim()), 0);
      } catch (_) {
        // not valid JSON: skip this block
      }
    }
    return out;
  }

  // A site-wide picture (logo, icon, "no image" placeholder) is not this title's cover.
  static final _genericImage = RegExp(
    r'twitter-card|logo|favicon|/icon|(?:^|/)(?:default|placeholder|no[-_]?(?:image|cover|poster)|blank)[^/]*$',
    caseSensitive: false,
  );
  static final _titleTag = RegExp(r'<title[^>]*>(.*?)</title>', caseSensitive: false, dotAll: true);

  static LinkPreview? parse(String html, Uri pageUrl) {
    final meta = <String, String>{};
    for (final tag in _metaTag.allMatches(html)) {
      final a = _attrs(tag.group(0)!);
      final key = (a['property'] ?? a['name'] ?? a['itemprop'])?.toLowerCase();
      final content = a['content'];
      if (key != null && content != null && content.trim().isNotEmpty) meta.putIfAbsent(key, () => _decode(content.trim()));
    }

    final siteName = meta['og:site_name'] ?? '';
    final rawTitle = meta['og:title'] ??
        meta['twitter:title'] ??
        _decode(_titleTag.firstMatch(html)?.group(1)?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '');
    final title = cleanTitle(rawTitle, siteName: siteName, host: pageUrl.host);
    if (title.isEmpty) return null;
    // A page that only says its own site name (apps that render in JavaScript) has no real title.
    final hostCore = pageUrl.host.replaceFirst(RegExp(r'^(www|m)\.'), '').split('.').first.toLowerCase();
    final flat = title.toLowerCase().replaceAll(' ', '');
    if (flat == siteName.toLowerCase().replaceAll(' ', '') || flat == hostCore) return null;

    final raw = <String>[
      for (final k in const ['og:image:secure_url', 'og:image', 'og:image:url', 'twitter:image', 'twitter:image:src', 'image', 'thumbnailurl', 'thumbnail']) ?meta[k],
      for (final tag in _linkTag.allMatches(html))
        if (_attrs(tag.group(0)!) case final a when (a['rel'] ?? '').toLowerCase().contains('image_src') && (a['href'] ?? '').isNotEmpty) _decode(a['href']!.trim()),
      ..._jsonLdImages(html),
    ];
    final images = <Uri>[];
    for (final r in raw) {
      final Uri resolved;
      try {
        resolved = pageUrl.resolve(r.trim());
      } catch (_) {
        continue; // not an address
      }
      if (resolved.scheme != 'http' && resolved.scheme != 'https') continue;
      if (_genericImage.hasMatch(resolved.path) || images.contains(resolved)) continue;
      images.add(resolved);
    }
    return LinkPreview(title: title, images: images, siteName: siteName);
  }

  static final _separators = RegExp(r'\s+[|\-–—:·»]+\s+|\s*\|\s*');
  static final _chapterSuffix = RegExp(r'\s*[-–—:|]?\s*\b(?:chapter|chap|ch|episode|ep)\.?\s*\d+(?:\.\d+)?\b.*$', caseSensitive: false);
  static final _noise = RegExp(r'\b(read|watch|online|free|stream|streaming|english|sub|dub|raw|manga|manhwa|manhua|anime|drama|movie)\b', caseSensitive: false);

  /// "Read Solo Leveling Chapter 45 | MangaSite" -> "Solo Leveling".
  static String cleanTitle(String raw, {String siteName = '', String host = ''}) {
    var t = raw.trim();
    final parts = t.split(_separators).where((p) => p.trim().isNotEmpty).toList();
    if (parts.length > 1) {
      final hostCore = host.replaceFirst(RegExp(r'^(www|m)\.'), '').split('.').first.toLowerCase();
      bool isSite(String p) {
        final low = p.toLowerCase().replaceAll(' ', '');
        return (siteName.isNotEmpty && low.contains(siteName.toLowerCase().replaceAll(' ', ''))) ||
            (hostCore.length > 2 && low.contains(hostCore));
      }

      // Keep the first part; drop later parts that name the site or are just "read online" noise.
      final kept = <String>[parts.first];
      for (final p in parts.skip(1)) {
        if (isSite(p) || _noise.hasMatch(p)) continue;
        kept.add(p);
      }
      // A leading site name ("MangaSite - Solo Leveling") means the real title comes next.
      if (kept.length > 1 && isSite(kept.first)) kept.removeAt(0);
      t = kept.first;
    }
    // "free Spider-Man: Brand New Day 2026 movie on Moviesjoy" -> "Spider-Man: Brand New Day"
    final onSite = RegExp(r'\s+(?:(?:19|20)\d{2}\s+)?(?:movie|film|series|show|drama|anime)\s+on\s+.+$', caseSensitive: false);
    if (onSite.hasMatch(t)) {
      t = t.replaceFirst(onSite, '').replaceFirst(RegExp(r'^(?:watch\s+)?free\s+', caseSensitive: false), '');
    }
    t = t.replaceAll(_chapterSuffix, '');
    t = t.replaceFirst(RegExp(r'^(read|watch)\s+', caseSensitive: false), '');
    t = t.replaceFirst(RegExp(r'(\s+(online|free))+$', caseSensitive: false), '');
    return t.trim();
  }

  static String _decode(String s) {
    const named = {'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'", 'nbsp': ' ', 'rsquo': '’', 'lsquo': '‘', 'ndash': '–', 'mdash': '—'};
    return s.replaceAllMapped(RegExp(r'&(#x[0-9a-fA-F]+|#\d+|[a-zA-Z]+);'), (m) {
      final e = m.group(1)!;
      if (e.startsWith('#x')) return _char(int.tryParse(e.substring(2), radix: 16)) ?? m.group(0)!;
      if (e.startsWith('#')) return _char(int.tryParse(e.substring(1))) ?? m.group(0)!;
      return named[e] ?? m.group(0)!;
    });
  }

  static String? _char(int? code) => (code == null || code <= 0 || code > 0x10FFFF) ? null : String.fromCharCode(code);

  // --- Network ---------------------------------------------------------------

  static Future<HttpClientResponse> _open(HttpClient client, Uri url, String accept, {Uri? referer}) async {
    final req = await client.getUrl(url);
    req.headers
      ..set(HttpHeaders.userAgentHeader, _userAgent)
      ..set(HttpHeaders.acceptHeader, accept)
      ..set(HttpHeaders.acceptLanguageHeader, 'en-US,en;q=0.9');
    if (referer != null) req.headers.set(HttpHeaders.refererHeader, referer.toString());
    return req.close().timeout(const Duration(seconds: 12));
  }

  static Future<Uint8List> _readLimited(HttpClientResponse res, int limit) async {
    final out = BytesBuilder(copy: false);
    await for (final chunk in res.timeout(const Duration(seconds: 15))) {
      out.add(chunk);
      if (out.length > limit) break; // cancels the download
    }
    return out.takeBytes();
  }

  static Future<String?> _getPage(Uri url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final res = await _open(client, url, 'text/html,application/xhtml+xml');
      if (res.statusCode != 200) return null;
      final type = res.headers.contentType?.mimeType ?? 'text/html';
      if (!type.contains('html')) return null;
      return utf8.decode(await _readLimited(res, _maxPageBytes), allowMalformed: true);
    } finally {
      client.close(force: true);
    }
  }

  static Future<Uint8List?> _getImage(Uri url, {Uri? referer}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      // No AVIF in the list on purpose: a host that picks the format from this header then sends one we can show.
      final res = await _open(client, url, 'image/webp,image/png,image/jpeg,image/*;q=0.8', referer: referer);
      // The label is not trusted (the bytes are checked by the caller), but a text answer is an error page.
      final mime = res.headers.contentType?.mimeType ?? '';
      if (res.statusCode != 200 || mime.startsWith('text/') || res.contentLength > maxImageBytes) {
        await res.drain<void>().catchError((_) {});
        return null;
      }
      final bytes = await _readLimited(res, maxImageBytes + 1);
      return bytes.isEmpty || bytes.length > maxImageBytes ? null : bytes;
    } finally {
      client.close(force: true);
    }
  }
}
