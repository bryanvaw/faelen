import 'package:faelen/features/media/models/media_entry.dart';
import 'package:faelen/features/media/screens/stats_screen.dart';
import 'package:faelen/features/media/services/cover_service.dart';
import 'package:faelen/features/media/services/storage_service.dart';
import 'package:faelen/features/media/state/media_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final dark in [false, true]) {
    testWidgets('stats fit a 360x740 phone without scrolling (${dark ? 'dark' : 'light'})', (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = MediaStore(StorageService(), covers: CoverService.disabled());
      await store.load();
      await store.save(const MediaEntry(id: '1', title: 'A', type: MediaType.manhwa, status: Status.watching, current: 32, rating: 9));
      await store.save(const MediaEntry(id: '2', title: 'B', type: MediaType.anime, status: Status.planToWatch, current: 4));
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(
          theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
          home: const StatsScreen(),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Avg rating'), findsOneWidget);
      // The last row (Drama) is on screen, so nothing needs scrolling.
      expect(tester.getBottomLeft(find.text('Drama')).dy, lessThan(740));
    });
  }
}
