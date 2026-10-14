import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_tracker_flutter/models/media_entry.dart';
import 'package:media_tracker_flutter/screens/home_screen.dart';
import 'package:media_tracker_flutter/services/storage_service.dart';
import 'package:media_tracker_flutter/state/media_store.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final size in const [Size(320, 640), Size(390, 844), Size(768, 1024), Size(1280, 800)]) {
    for (final brightness in Brightness.values) {
      testWidgets('no overflow at ${size.width.toInt()}x${size.height.toInt()} $brightness', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final store = MediaStore(StorageService());
        await store.load();
        await store.save(const MediaEntry(
            id: '1', title: 'A very long title that should wrap onto several lines nicely', type: MediaType.anime,
            status: Status.watching, current: 3, total: 24, rating: 9));
        await store.save(const MediaEntry(id: '2', title: 'Movie', type: MediaType.movie, status: Status.completed, rating: 8));
        await store.save(const MediaEntry(id: '3', title: 'Manhwa', type: MediaType.manhwa, status: Status.watching, current: 5));

        await tester.pumpWidget(ChangeNotifierProvider.value(
          value: store,
          child: MaterialApp(theme: ThemeData(brightness: brightness), home: const HomeScreen()),
        ));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('My List'), findsOneWidget);
        expect(find.byType(NavigationRail), size.width >= 720 ? findsOneWidget : findsNothing);
        expect(find.byKey(const ValueKey('bottom-nav')), size.width >= 720 ? findsNothing : findsOneWidget);
      });
    }
  }
}
