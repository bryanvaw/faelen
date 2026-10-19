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

  Future<MediaStore> open(WidgetTester tester, {double width = 390}) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = MediaStore(StorageService(), covers: CoverService.disabled());
    await store.load();
    await store.save(const MediaEntry(id: '1', title: 'Solo Leveling', type: MediaType.manhwa));
    await store.save(const MediaEntry(id: '2', title: 'Frieren'));
    await tester.pumpWidget(ChangeNotifierProvider.value(value: store, child: const MaterialApp(home: MediaScreen())));
    await tester.pumpAndSettle();
    return store;
  }

  testWidgets('phones show only a search button until it is tapped, and closing clears the filter', (tester) async {
    final store = await open(tester);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('My List'), findsOneWidget);

    await tester.tap(find.byTooltip('Search titles'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('My List'), findsNothing); // the field takes the title's place

    await tester.enterText(find.byType(TextField), 'solo');
    await tester.pump();
    expect(store.visible.map((e) => e.title), ['Solo Leveling']);

    await tester.tap(find.byTooltip('Close search'));
    await tester.pumpAndSettle();
    expect(store.query, '');
    expect(store.visible, hasLength(2));
    expect(find.byType(TextField), findsNothing);
    expect(find.text('My List'), findsOneWidget);
  });

  testWidgets('wide screens keep the field open beside the title', (tester) async {
    await open(tester, width: 900);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('My List'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
