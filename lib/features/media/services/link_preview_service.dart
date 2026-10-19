import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/media_entry.dart';

/// What a web page says about itself (its Open Graph "link preview" tags).
class LinkPreview {
  const LinkPreview({required this.title, this.imageUrl, this.siteName = ''});
  final String title; // cleaned up: site name and chapter/episode suffix removed
  final Uri? imageUrl;
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

  static const maxImageBytes = 2 * 1024 * 1024;
  static const _maxPageBytes = 400 * 1024;
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
    // If the page title shares no word with the address, trust the address.
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
      var s = Uri.decodeComponent(seg).trim();
      if (s.isEmpty || _stopSegments.hasMatch(s)) continue;
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
  /// Anime and manhwa come from AniList, dramas from TVmaze; movies have no keyless source yet.
  Future<CatalogMatch?> findInCatalog(String title, MediaType type) async {
    try {
      return await _searchCatalog(title, type).timeout(const Duration(seconds: 15));
    } catch (_) {
      return null;
    }
  }

  static Future<CatalogMatch?> _catalog(String title, MediaType type) async {
    // "Make Me Tingle (2026)" searches better as "Make Me Tingle".
    final q = title.replaceAll(RegExp(r'\s*\((?:19|20)\d{2}\)\s*$'), '').trim();
    if (q.isEmpty) return null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      switch (type) {
        case MediaType.anime:
        case MediaType.manhwa:
          final req = await client.postUrl(Uri.parse('https://graphql.anilist.co'));
          req.headers
            ..set(HttpHeaders.contentTypeHeader, 'application/json')
            ..set(HttpHeaders.acceptHeader, 'application/json');
          req.add(utf8.encode(jsonEncode({
            'query': aniListQuery,
            'variables': {
              's': q,
              't': type == MediaType.anime ? 'ANIME' : 'MANGA',
              if (type == MediaType.manhwa) 'c': 'KR',
            },
          })));
          final res = await req.close().timeout(const Duration(seconds: 12));
          if (res.statusCode != 200) return null;
          final body = utf8.decode(await _readLimited(res, 256 * 1024), allowMalformed: true);
          return parseAniList(jsonDecode(body), manga: type == MediaType.manhwa);
        case MediaType.drama:
          final res = await _open(client, Uri.https('api.tvmaze.com', '/search/shows', {'q': q}), 'application/json');
          if (res.statusCode != 200) return null;
          final body = utf8.decode(await _readLimited(res, 256 * 1024), allowMalformed: true);
          return parseTvMaze(jsonDecode(body));
        case MediaType.movie:
          return null;
      }
    } finally {
      client.close(force: true);
    }
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

  /// The image bytes, or null if it isn't an image or is too big.
  Future<Uint8List?> downloadImage(Uri url) async {
    try {
      return await (_customImage ?? (u) => _getImage(u, referer: _lastPage))(url);
    } catch (_) {
      return null; // blocked, offline or timed out: the caller falls back
    }
  }

  // --- Parsing ---------------------------------------------------------------

  static final _metaTag = RegExp(r'<meta\s[^>]*>', caseSensitive: false);
  static final _attr = RegExp(r'''([a-zA-Z:_-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')''');
  static final _titleTag = RegExp(r'<title[^>]*>(.*?)</title>', caseSensitive: false, dotAll: true);

  static LinkPreview? parse(String html, Uri pageUrl) {
    final meta = <String, String>{};
    for (final tag in _metaTag.allMatches(html)) {
      String? key, content;
      for (final a in _attr.allMatches(tag.group(0)!)) {
        final name = a.group(1)!.toLowerCase();
        final value = a.group(2) ?? a.group(3) ?? '';
        if (name == 'property' || name == 'name') key = value.toLowerCase();
        if (name == 'content') content = value;
      }
      if (key != null && content != null && content.trim().isNotEmpty) meta.putIfAbsent(key, () => _decode(content!.trim()));
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

    Uri? image;
    final rawImage = meta['og:image'] ?? meta['og:image:url'] ?? meta['twitter:image'] ?? meta['twitter:image:src'];
    if (rawImage != null) {
      final resolved = pageUrl.resolve(rawImage);
      final generic = RegExp(r'twitter-card|logo|favicon|default|placeholder|/icon', caseSensitive: false).hasMatch(resolved.path);
      if ((resolved.scheme == 'http' || resolved.scheme == 'https') && !generic) image = resolved;
    }
    return LinkPreview(title: title, imageUrl: image, siteName: siteName);
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
      final res = await _open(client, url, 'image/*', referer: referer);
      if (res.statusCode != 200) return null;
      if (!(res.headers.contentType?.mimeType ?? '').startsWith('image/')) return null;
      if (res.contentLength > maxImageBytes) return null;
      final bytes = await _readLimited(res, maxImageBytes + 1);
      return bytes.isEmpty || bytes.length > maxImageBytes ? null : bytes;
    } finally {
      client.close(force: true);
    }
  }
}
