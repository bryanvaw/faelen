import 'package:flutter_test/flutter_test.dart';
import 'package:faelen/features/media/models/media_entry.dart';
import 'package:faelen/features/media/services/url_progress.dart';

void main() {
  group('UrlProgress.detect', () {
    final cases = {
      'https://site.com/series/solo-leveling/chapter-45': 45,
      'https://site.com/read/solo-leveling-chapter-45/': 45,
      'https://site.com/manga/x/chapter_012': 12,
      'https://site.com/watch/frieren/episode-7': 7,
      'https://site.com/watch/frieren-episode-7-english-sub': 7,
      'https://site.com/anime/x/ep/3': 3,
      'site.com/x/ep-3': 3,
      'https://site.com/watch?v=abc&ep=9': 9,
      'https://site.com/x/chapter-45.5': 45,
      'https://site.com/x/ch45': 45,
    };
    cases.forEach((url, n) => test(url, () => expect(UrlProgress.detect(url), n)));

    for (final url in [
      'https://site.com/viewer/839201',
      'https://site.com/series/solo-leveling',
      'https://site.com/watch/deep-sea-chess', // "ch" inside a word must not match
      'https://site.com/season-2',
      'not a url',
      '',
    ]) {
      test('no number: $url', () => expect(UrlProgress.detect(url), isNull));
    }
  });

  test('normalize adds https and rejects junk', () {
    expect(UrlProgress.normalize('site.com/a')?.toString(), 'https://site.com/a');
    expect(UrlProgress.normalize('javascript:alert(1)'), isNull);
    expect(UrlProgress.normalize('hello'), isNull);
  });

  test('url survives a JSON round trip and is omitted when empty', () {
    const e = MediaEntry(id: '1', title: 'T', url: 'https://a.com/chapter-2');
    expect(MediaEntry.fromJson(e.toJson()).url, 'https://a.com/chapter-2');
    expect(const MediaEntry(id: '2', title: 'T').toJson().containsKey('url'), isFalse);
    expect(MediaEntry.fromJson({'id': '3', 'title': 'Old'}).url, '');
  });
}
