import 'package:faelen/core/settings_store.dart';
import 'package:faelen/features/hub/hub_screen.dart';
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

  testWidgets('settings opens from the hub and switches the theme', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settings = SettingsStore();
    final media = MediaStore(StorageService(), covers: CoverService.disabled());
    await media.load();
    await tester.pumpWidget(MultiProvider(
      providers: [ChangeNotifierProvider.value(value: settings), ChangeNotifierProvider.value(value: media)],
      child: Consumer<SettingsStore>(
        builder: (_, s, _) => MaterialApp(theme: ThemeData.light(), darkTheme: ThemeData.dark(), themeMode: s.themeMode, home: const HubScreen()),
      ),
    ));

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Backup'), findsOneWidget);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(settings.themeMode, ThemeMode.dark);
    expect(tester.takeException(), isNull);
    expect(Theme.of(tester.element(find.text('Appearance'))).brightness, Brightness.dark);
  });

  testWidgets('sort menu reorders the library', (tester) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final media = MediaStore(StorageService(), covers: CoverService.disabled());
    await media.load();
    await media.save(const MediaEntry(id: 'a', title: 'Alpha', rating: 2));
    await media.save(const MediaEntry(id: 'b', title: 'Bravo', rating: 10));
    await tester.pumpWidget(ChangeNotifierProvider.value(value: media, child: const MaterialApp(home: MediaScreen())));
    await tester.pumpAndSettle();

    double y(String t) => tester.getTopLeft(find.text(t)).dy;
    expect(y('Alpha') < y('Bravo'), isTrue);

    await tester.tap(find.text('Title (A–Z)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Highest rated').last);
    await tester.pumpAndSettle();
    expect(y('Bravo') < y('Alpha'), isTrue);
  });
}
