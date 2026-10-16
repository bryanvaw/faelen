import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

/// A newer release published on GitHub.
class UpdateInfo {
  const UpdateInfo({required this.version, required this.apkUrl, required this.pageUrl, this.notes = ''});
  final String version; // without the leading "v"
  final Uri apkUrl;
  final Uri pageUrl;
  final String notes;
}

/// Looks for a newer Faelen release on GitHub. Release flow: bump `version:` in pubspec.yaml,
/// build the APK, then publish a release tagged `v<version>` with the APK attached.
class UpdateService {
  UpdateService({this.owner = 'bryanvaw', this.repo = 'faelen', Future<String?> Function(Uri url)? fetch})
      : _fetch = fetch ?? _httpGet;

  final String owner;
  final String repo;
  final Future<String?> Function(Uri url) _fetch;

  static const _lastCheckKey = 'update_last_check_v1';
  static const _autoCheckEvery = Duration(hours: 24);

  Uri get _latestUrl => Uri.https('api.github.com', '/repos/$owner/$repo/releases/latest');

  /// The newest release if it is newer than [currentVersion] and has an APK attached, else null.
  /// Throws on network or server errors.
  Future<UpdateInfo?> checkFor(String currentVersion) async {
    final body = await _fetch(_latestUrl);
    if (body == null) return null; // no release published yet
    final info = parseRelease(body);
    if (info == null || !isNewer(info.version, currentVersion)) return null;
    return info;
  }

  /// True at most once per day, so the automatic check at launch stays quiet. Records the attempt.
  Future<bool> shouldAutoCheck({DateTime? now}) async {
    now ??= DateTime.now();
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getInt(_lastCheckKey) ?? 0;
      if (now.millisecondsSinceEpoch - last < _autoCheckEvery.inMilliseconds) return false;
      await prefs.setInt(_lastCheckKey, now.millisecondsSinceEpoch);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Reads GitHub's "latest release" JSON. Null if it has no usable APK or tag.
  static UpdateInfo? parseRelease(String json) {
    try {
      final m = jsonDecode(json) as Map<String, dynamic>;
      final tag = (m['tag_name'] as String?)?.trim() ?? '';
      if (tag.isEmpty || m['draft'] == true || m['prerelease'] == true) return null;
      final assets = (m['assets'] as List?) ?? const [];
      for (final a in assets) {
        final name = (a as Map)['name'] as String? ?? '';
        final url = Uri.tryParse(a['browser_download_url'] as String? ?? '');
        if (name.toLowerCase().endsWith('.apk') && url != null && url.scheme == 'https') {
          return UpdateInfo(
            version: tag.replaceFirst(RegExp(r'^[vV]'), ''),
            apkUrl: url,
            pageUrl: Uri.tryParse(m['html_url'] as String? ?? '') ?? url,
            notes: ((m['body'] as String?) ?? '').trim(),
          );
        }
      }
    } catch (_) {
      // Unexpected shape: treat as "no update".
    }
    return null;
  }

  /// Compares dotted versions numerically (1.10.0 > 1.9.0). Build suffixes (+3) and pre-release
  /// tags (-beta) are ignored.
  static bool isNewer(String latest, String current) {
    List<int> parts(String v) =>
        v.split(RegExp(r'[+-]')).first.split('.').map((p) => int.tryParse(p.trim()) ?? 0).toList();
    final a = parts(latest), b = parts(current);
    for (var i = 0; i < (a.length > b.length ? a.length : b.length); i++) {
      final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  static Future<String?> _httpGet(Uri url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(url);
      req.headers
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
        ..set(HttpHeaders.userAgentHeader, 'faelen-app');
      final res = await req.close().timeout(const Duration(seconds: 15));
      if (res.statusCode == 404) {
        await res.drain<void>();
        return null;
      }
      if (res.statusCode != 200) {
        await res.drain<void>();
        throw HttpException('GitHub answered ${res.statusCode}', uri: url);
      }
      return await res.transform(utf8.decoder).join();
    } finally {
      client.close(force: true);
    }
  }
}
