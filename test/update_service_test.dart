import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:faelen/core/update_service.dart';

String release({String tag = 'v1.2.0', bool prerelease = false, List<Map<String, String>>? assets}) => jsonEncode({
      'tag_name': tag,
      'prerelease': prerelease,
      'html_url': 'https://github.com/bryanvaw/faelen/releases/tag/$tag',
      'body': 'Adds links',
      'assets': assets ??
          [
            {'name': 'notes.txt', 'browser_download_url': 'https://example.com/notes.txt'},
            {'name': 'faelen.apk', 'browser_download_url': 'https://github.com/bryanvaw/faelen/releases/download/$tag/faelen.apk'},
          ],
    });

void main() {
  test('isNewer compares numerically and ignores build/pre-release suffixes', () {
    expect(UpdateService.isNewer('1.10.0', '1.9.0'), isTrue);
    expect(UpdateService.isNewer('1.1.0', '1.0.0'), isTrue);
    expect(UpdateService.isNewer('2.0', '1.9.9'), isTrue);
    expect(UpdateService.isNewer('1.0.0', '1.0.0'), isFalse);
    expect(UpdateService.isNewer('1.0.0', '1.0.1'), isFalse);
    expect(UpdateService.isNewer('1.2.0+5', '1.2.0'), isFalse);
    expect(UpdateService.isNewer('1.2.0', '1.2'), isFalse);
  });

  test('parseRelease picks the APK asset and strips the v', () {
    final info = UpdateService.parseRelease(release())!;
    expect(info.version, '1.2.0');
    expect(info.apkUrl.toString(), endsWith('/v1.2.0/faelen.apk'));
    expect(info.notes, 'Adds links');
  });

  test('parseRelease ignores prereleases, missing APKs, non-https and junk', () {
    expect(UpdateService.parseRelease(release(prerelease: true)), isNull);
    expect(UpdateService.parseRelease(release(assets: [])), isNull);
    expect(
        UpdateService.parseRelease(release(assets: [
          {'name': 'a.apk', 'browser_download_url': 'http://insecure.example/a.apk'}
        ])),
        isNull);
    expect(UpdateService.parseRelease('not json'), isNull);
  });

  test('checkFor returns the update only when newer', () async {
    final svc = UpdateService(fetch: (_) async => release(tag: 'v1.2.0'));
    expect((await svc.checkFor('1.1.0'))?.version, '1.2.0');
    expect(await svc.checkFor('1.2.0'), isNull);
    expect(await svc.checkFor('1.3.0'), isNull);
  });

  test('checkFor treats "no release yet" as no update and lets errors through', () async {
    expect(await UpdateService(fetch: (_) async => null).checkFor('1.0.0'), isNull);
    final failing = UpdateService(fetch: (_) async => throw Exception('offline'));
    expect(failing.checkFor('1.0.0'), throwsException);
  });

  test('shouldAutoCheck allows one automatic check per day', () async {
    SharedPreferences.setMockInitialValues({});
    final svc = UpdateService(fetch: (_) async => null);
    final t = DateTime(2026, 10, 16, 9);
    expect(await svc.shouldAutoCheck(now: t), isTrue);
    expect(await svc.shouldAutoCheck(now: t.add(const Duration(hours: 3))), isFalse);
    expect(await svc.shouldAutoCheck(now: t.add(const Duration(hours: 25))), isTrue);
  });
}
