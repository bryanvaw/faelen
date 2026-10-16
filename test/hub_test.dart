import 'package:faelen/features/hub/hub_screen.dart';
import 'package:faelen/features/media/services/cover_service.dart';
import 'package:faelen/features/media/services/storage_service.dart';
import 'package:faelen/features/media/state/media_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpHub(WidgetTester tester) async {
    final store = MediaStore(StorageService(), covers: CoverService.disabled());
    await store.load();
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: store,
      child: const MaterialApp(home: HubScreen()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('hub lists modules; Planner, Budget and Passwords are coming soon', (tester) async {
    await pumpHub(tester);
    expect(find.text('Media'), findsOneWidget);
    expect(find.text('Planner'), findsOneWidget);
    expect(find.text('Budget'), findsOneWidget);
    expect(find.text('Passwords'), findsOneWidget);
    expect(find.text('Coming soon'), findsNWidgets(3));
  });

  testWidgets('tapping Media opens it and back returns to the hub', (tester) async {
    await pumpHub(tester);
    await tester.tap(find.text('Media'));
    await tester.pumpAndSettle();
    expect(find.text('My List'), findsOneWidget);

    await tester.tap(find.byTooltip('Back to modules'));
    await tester.pumpAndSettle();
    expect(find.text('Your personal space'), findsOneWidget);
  });

  testWidgets('tapping a coming-soon module does nothing', (tester) async {
    await pumpHub(tester);
    await tester.tap(find.text('Planner'));
    await tester.pumpAndSettle();
    expect(find.text('Your personal space'), findsOneWidget);
  });
}
