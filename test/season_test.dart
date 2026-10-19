import 'package:faelen/features/media/models/media_entry.dart';
import 'package:faelen/features/media/services/url_progress.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SeasonDetect.fromUrl', () {
    final cases = <String, int?>{
      'https://anikoto.cz/watch/frieren-season-2-episode-5': 2,
      'https://site.com/anime/slime-s3/episode-4': 3,
      'https://site.com/watch/my-show-s02e05': 2,
      'https://site.com/watch/one-piece-2nd-season-ep-1': 2,
      'https://site.com/anime/third-season-of-x/ep-1': 3,
      'https://site.com/series/some-drama/season/2/episode/6': 2,
      'https://site.com/watch?title=x&season=4&ep=2': 4,
      'https://site.com/watch/as-a-reincarnated-aristocrat-i-ll-use-my-appraisal-skill': null,
      'https://site.com/manga/solo-leveling/chapter-45': null,
      'https://site.com/watch/chainsaw-man': null,
      'https://site.com/watch/cats-2024': null, // "s" at the end of a word is not a season
      'https://site.com/watch/season-0-nothing': null, // season 0 is not a season
    };
    cases.forEach((u, want) => test(u, () => expect(SeasonDetect.fromUrl(u), want)));
  });

  group('SeasonDetect.fromText', () {
    test('page titles', () {
      expect(SeasonDetect.fromText('Frieren: Beyond Journey\'s End Season 2'), 2);
      expect(SeasonDetect.fromText('My Hero Academia 6th Season'), 6);
      expect(SeasonDetect.fromText('Crash Landing on You'), isNull);
      expect(SeasonDetect.fromText('Mr. Sunshine'), isNull);
    });
  });

  test('season survives a JSON round trip and is omitted when none', () {
    const e = MediaEntry(id: 'a', title: 'A', season: 3);
    expect(MediaEntry.fromJson(e.toJson()).season, 3);
    expect(const MediaEntry(id: 'a', title: 'A').toJson().containsKey('season'), isFalse);
  });

  group('TypeGuess.fromUrl', () {
    final cases = <String, MediaType?>{
      'https://asurascans.com/comics/the-margrave-s-worthless-mage-11fe7da3/chapter/32': MediaType.manhwa,
      'https://mangadex.org/title/abc/solo-leveling': MediaType.manhwa,
      'https://webtoons.com/en/fantasy/tower-of-god/list': MediaType.manhwa,
      'https://example.com/series/some-title/chapter-45': MediaType.manhwa,
      'https://example.com/read?title=x&chapter=9': MediaType.manhwa,
      'https://anikoto.cz/watch/frieren-season-2-episode-5': null,
      'https://kisskh.co/Drama/Make-Me-Tingle/Episode-4': null,
      'https://example.com/watch/chainsaw-man': null,
    };
    cases.forEach((u, want) => test(u, () => expect(TypeGuess.fromUrl(u), want)));
  });
}
