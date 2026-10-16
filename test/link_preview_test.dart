import 'dart:typed_data';

import 'package:faelen/core/settings_store.dart';
import 'package:faelen/features/media/screens/media_screen.dart';
import 'package:faelen/features/media/services/cover_service.dart';
import 'package:faelen/features/media/services/link_preview_service.dart';
import 'package:faelen/features/media/services/storage_service.dart';
import 'package:faelen/features/media/state/media_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

String page({String? ogTitle, String? image, String? site, String? title}) => '''
<html><head>
${title != null ? '<title>$title</title>' : ''}
${ogTitle != null ? '<meta property="og:title" content="$ogTitle">' : ''}
${site != null ? '<meta property="og:site_name" content="$site">' : ''}
${image != null ? "<meta property='og:image' content='$image'>" : ''}
</head><body>x</body></html>''';

void main() {
  final url = Uri.parse('https://www.mangasite.com/series/solo-leveling/chapter-45');

  group('parse', () {
    test('reads og:title, site name and resolves a relative image', () {
      final p = LinkPreviewService.parse(page(ogTitle: 'Solo Leveling', site: 'MangaSite', image: '/img/cover.jpg'), url)!;
      expect(p.title, 'Solo Leveling');
      expect(p.siteName, 'MangaSite');
      expect(p.imageUrl.toString(), 'https://www.mangasite.com/img/cover.jpg');
    });

    test('falls back to <title>, decodes entities', () {
      final p = LinkPreviewService.parse(page(title: 'Tom &amp; Jerry &#39;99'), url)!;
      expect(p.title, "Tom & Jerry '99");
      expect(p.imageUrl, isNull);
    });

    test('handles reversed attribute order and rejects non-http images', () {
      final p = LinkPreviewService.parse(
          '<meta content="Frieren" property="og:title"><meta content="javascript:alert(1)" property="og:image">', url)!;
      expect(p.title, 'Frieren');
      expect(p.imageUrl, isNull);
    });

    test('a page that only repeats its site name has no title; site logos are not covers', () {
      expect(LinkPreviewService.parse(page(ogTitle: 'AniList', site: 'AniList'), Uri.parse('https://anilist.co/anime/1')), isNull);
      final p = LinkPreviewService.parse(page(ogTitle: 'Frieren', image: 'https://cdn.x.net/img/sp/icon/twitter-card.png'), url)!;
      expect(p.imageUrl, isNull);
    });

    test('no title -> null', () => expect(LinkPreviewService.parse('<html></html>', url), isNull));
  });

  group('cleanTitle', () {
    final cases = {
      'Solo Leveling - Chapter 45 | MangaSite': 'Solo Leveling',
      'Read Solo Leveling Chapter 45 Online': 'Solo Leveling',
      'Frieren: Beyond Journey\'s End Episode 7 English Sub': "Frieren: Beyond Journey's End",
      'Parasite (2019) - IMDb': 'Parasite (2019)',
      'Crash Landing on You': 'Crash Landing on You',
      'MangaSite - Tower of God': 'Tower of God',
      'Watch Oppenheimer Online Free': 'Oppenheimer',
      'free Spider-Man: Brand New Day 2026 movie on Moviesjoy': 'Spider-Man: Brand New Day',
      'Free Guy': 'Free Guy',
    };
    cases.forEach((raw, want) => test(raw, () {
          expect(LinkPreviewService.cleanTitle(raw, siteName: raw.contains('IMDb') ? 'IMDb' : 'MangaSite', host: 'www.mangasite.com'), want);
        }));
  });

  group('titleFromUrl and generic page titles', () {
    final cases = {
      'https://kisskh.do/Drama/Make-Me-Tingle--2026-/Episode-4?id=13792&ep=227125': 'Make Me Tingle (2026)',
      'https://asurascans.com/comics/crimson-reset-1bb35e56/chapter/65': 'Crimson Reset',
      'https://anikoto.cz/watch/the-exiled-heavy-knight/ep-16': 'The Exiled Heavy Knight',
      'https://www.crunchyroll.com/series/GG5H5XQ7D/jujutsu-kaisen': 'Jujutsu Kaisen',
      'https://kitsu.app/anime/sousou-no-frieren': 'Sousou No Frieren',
    };
    cases.forEach((u, want) => test(u, () => expect(LinkPreviewService.titleFromUrl(Uri.parse(u)), want)));

    for (final u in [
      'https://www.netflix.com/title/81040344',
      'https://site.com/watch/12345',
      'https://site.com/x',
      'https://site.com/',
    ]) {
      test('no slug: $u', () => expect(LinkPreviewService.titleFromUrl(Uri.parse(u)), isNull));
    }

    test('a site-wide title is replaced by the one in the address', () async {
      final svc = LinkPreviewService(fetchPage: (_) async => page(title: 'kisskh | Asian Dramas &amp; Movies'));
      final p = await svc.preview(Uri.parse('https://kisskh.do/Drama/Make-Me-Tingle--2026-/Episode-4'));
      expect(p!.title, 'Make Me Tingle (2026)');
    });

    test('a real page title is kept when it matches the address', () async {
      final svc = LinkPreviewService(fetchPage: (_) async => page(ogTitle: 'Spider-Man: Brand New Day'));
      final p = await svc.preview(Uri.parse('https://x.com/movies/spider-man-brand-new-day'));
      expect(p!.title, 'Spider-Man: Brand New Day');
    });

    test('unreadable page (error or blocked) falls back to the address', () async {
      final blocked = LinkPreviewService(fetchPage: (_) async => null);
      expect((await blocked.preview(Uri.parse('https://x.com/anime/frieren-beyond-journeys-end')))!.title, 'Frieren Beyond Journeys End');
      final failing = LinkPreviewService(fetchPage: (_) async => throw Exception('boom'));
      expect((await failing.preview(Uri.parse('https://x.com/anime/frieren-beyond-journeys-end')))!.title, 'Frieren Beyond Journeys End');
    });
  });

  group('form', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<void> open(WidgetTester tester, LinkPreviewService svc) async {
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = MediaStore(StorageService(), covers: CoverService.disabled());
      await store.load();
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: store),
          ChangeNotifierProvider(create: (_) => SettingsStore()),
          Provider.value(value: svc),
        ],
        child: const MaterialApp(home: MediaScreen()),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add title'));
      await tester.pumpAndSettle();
    }

    final svc = LinkPreviewService(
      fetchPage: (u) async => page(ogTitle: 'Solo Leveling - Chapter 45 | MangaSite', site: 'MangaSite', image: 'https://x.com/c.jpg'),
      fetchImage: (u) async => Uint8List(0),
    );

    testWidgets('pasting a link fills an empty title', (tester) async {
      await open(tester, svc);
      await tester.enterText(find.widgetWithText(TextFormField, 'Where you read/watch (optional)'), 'https://www.mangasite.com/series/solo/chapter-45');
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Title')).controller!.text, 'Solo Leveling');
    });

    testWidgets('a title the user typed is kept and the found one is offered', (tester) async {
      await open(tester, svc);
      await tester.enterText(find.widgetWithText(TextFormField, 'Title'), 'My own name');
      await tester.enterText(find.widgetWithText(TextFormField, 'Where you read/watch (optional)'), 'https://www.mangasite.com/series/solo/chapter-45');
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Title')).controller!.text, 'My own name');
      expect(find.text('Use title'), findsOneWidget);
      await tester.tap(find.text('Use title'));
      await tester.pump();
      expect(tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Title')).controller!.text, 'Solo Leveling');
    });

    testWidgets('an unreadable site shows a quiet note and changes nothing', (tester) async {
      await open(tester, LinkPreviewService(fetchPage: (u) async => null, fetchImage: (u) async => null));
      await tester.enterText(find.widgetWithText(TextFormField, 'Where you read/watch (optional)'), 'https://blocked.example.com/x');
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.textContaining("Couldn't read details"), findsOneWidget);
      expect(tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Title')).controller!.text, '');
    });
  });
}
