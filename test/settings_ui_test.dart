import 'package:faelen/core/settings_store.dart';
import 'package:faelen/features/hub/hub_screen.dart';
import 'package:faelen/features/media/models/media_entry.dart';
import 'package:faelen/features/media/screens/media_screen.dart';
import 'package:faelen/features/settings/settings_screen.dart';
import 'package:faelen/features/media/services/cover_service.dart';
import 'package:faelen/features/media/services/storage_service.dart';
import 'package:faelen/features/media/state/media_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  settingsFitTests();

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

// Regression: on a 360dp phone with larger system text, labels used to wrap mid-word
// ("Syste/m", "Downlo/ad") and buttons used to squeeze each other.
void settingsFitTests() {
  for (final scale in [1.0, 1.3]) {
    testWidgets('settings labels stay on one line at 360dp, text scale $scale', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(360, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final media = MediaStore(StorageService(), covers: CoverService.disabled());
      await media.load();
      await tester.pumpWidget(MultiProvider(
        providers: [ChangeNotifierProvider(create: (_) => SettingsStore()), ChangeNotifierProvider.value(value: media)],
        child: MaterialApp(
          builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
          home: const SettingsScreen(),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final label in ['System', 'Light', 'Dark', 'Check for updates']) {
        final h = tester.getSize(find.text(label)).height;
        // One line of 14sp text is about 20dp tall even at 1.3x; two lines would be 40+.
        expect(h, lessThan(30), reason: '"$label" wrapped onto two lines');
      }
    });
  }
}
