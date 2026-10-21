import 'package:faelen/core/theme.dart';
import 'package:faelen/features/media/models/media_entry.dart';
import 'package:faelen/features/media/widgets/media_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, MediaEntry e, {double width = 320, double scale = 1, bool link = true, bool bump = true, bool pin = false}) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 900), textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: MediaCard(
              entry: e,
              onTap: () {},
              onLongPress: () {},
              onContinue: link ? () {} : null,
              onIncrement: bump ? () {} : null,
              onTogglePin: pin ? () {} : null,
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  final long = MediaEntry(
    id: 'a',
    title: 'As A Reincarnated Aristocrat I Ll Use My Appraisal Skill To Rise In The World',
    status: Status.watching,
    current: 4,
    season: 3,
    rating: 7,
    releaseDays: const [6, 7],
    releasedCount: 6,
    releasedOn: DateTime(2026, 10, 12).millisecondsSinceEpoch,
  );

  for (final scale in [1.0, 1.4]) {
    testWidgets('card with the pin button fits a 320dp phone at text scale $scale', (tester) async {
      await pump(tester, long, scale: scale, pin: true);
      expect(tester.takeException(), isNull);
      expect(find.bySemanticsLabel(RegExp('Pin .* to notifications')), findsOneWidget);
    });
  }

  for (final scale in [1.0, 1.4]) {
    testWidgets('busiest card fits a 320dp phone at text scale $scale', (tester) async {
      await pump(tester, long, scale: scale);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('known total shows a slim progress bar; unknown total shows none; no ring either way', (tester) async {
    await pump(tester, long);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await pump(tester, long.copyWith(total: 12));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('no cover gives a type tile on the right instead of a number', (tester) async {
    await pump(tester, long);
    // One in the "Anime · status" line, one on the placeholder tile.
    expect(find.byIcon(Icons.live_tv_rounded), findsNWidgets(2));
    expect(find.text('EP'), findsNothing);
  });

  testWidgets('with no link the +1 action still shows; with neither there is no action row', (tester) async {
    await pump(tester, long, link: false);
    expect(find.text('+1 Ep'), findsOneWidget);
    await pump(tester, long, link: false, bump: false);
    expect(find.text('+1 Ep'), findsNothing);
    expect(find.text('Continue'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
