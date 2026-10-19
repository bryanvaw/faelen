import 'package:faelen/features/media/models/media_entry.dart';
import 'package:faelen/features/media/screens/media_screen.dart';
import 'package:faelen/features/media/services/cover_service.dart';
import 'package:faelen/features/media/services/storage_service.dart';
import 'package:faelen/features/media/state/media_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<MediaStore> openForm(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = MediaStore(StorageService(), covers: CoverService.disabled());
    await store.load();
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: store,
      child: const MaterialApp(home: MediaScreen()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add title'));
    await tester.pumpAndSettle();
    return store;
  }

  testWidgets('add entry with type, status, progress and star rating', (tester) async {
    final store = await openForm(tester);
    expect(find.text('Add entry'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Title'), 'Solo Leveling');
    await tester.tap(find.text('Manhwa').last);
    await tester.pump();
    await tester.tap(find.text('Watching').last);
    await tester.pump();
    await tester.tap(find.byTooltip('Increase Current Ch'));
    await tester.pump();

    // Right half of the 4th star = 4 stars = stored as 8.
    final star = tester.getCenter(find.byIcon(Icons.star_outline_rounded).at(3));
    await tester.tapAt(star + const Offset(10, 0));
    await tester.pump();
    expect(find.text('4 / 5'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final e = store.visible.single;
    expect(e.title, 'Solo Leveling');
    expect(e.type, MediaType.manhwa);
    expect(e.status, Status.watching);
    expect(e.current, 1);
    expect(e.rating, 8);
  });

  testWidgets('half star, clear, and movie hides progress', (tester) async {
    await openForm(tester);

    final first = tester.getCenter(find.byIcon(Icons.star_outline_rounded).first);
    await tester.tapAt(first - const Offset(10, 0)); // left half of star 1
    await tester.pump();
    expect(find.text('0.5 / 5'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear rating'));
    await tester.pump();
    expect(find.text('Not rated'), findsOneWidget);

    expect(find.text('Progress'), findsOneWidget);
    await tester.tap(find.text('Movie').last);
    await tester.pump();
    expect(find.text('Progress'), findsNothing);
  });
}
