import 'package:faelen/core/settings_store.dart';
import 'package:faelen/features/media/services/cover_service.dart';
import 'package:faelen/features/media/services/storage_service.dart';
import 'package:faelen/features/media/state/media_store.dart';
import 'package:faelen/features/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<SettingsStore> open(WidgetTester tester, {required Size size}) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final media = MediaStore(StorageService(), covers: CoverService.disabled());
    await media.load();
    final settings = SettingsStore();
    await tester.pumpWidget(MultiProvider(
      providers: [ChangeNotifierProvider.value(value: settings), ChangeNotifierProvider.value(value: media)],
      child: const MaterialApp(home: SettingsScreen()),
    ));
    await tester.pumpAndSettle();
    return settings;
  }

  testWidgets('the whole screen fits a 360x800 phone (a 1080x2400 screen) without scrolling', (tester) async {
    await open(tester, size: const Size(360, 800));
    expect(tester.takeException(), isNull);
    final export = tester.getBottomLeft(find.text('Export')).dy;
    expect(export, lessThan(800), reason: 'Backup buttons should be visible without scrolling');
  });

  testWidgets('the links switch changes the setting and its description', (tester) async {
    final settings = await open(tester, size: const Size(360, 740));
    expect(settings.autoUrlProgress, isFalse);
    expect(find.textContaining('asks before'), findsOneWidget);
    await tester.tap(find.text('Progress from links'));
    await tester.pumpAndSettle();
    expect(settings.autoUrlProgress, isTrue);
    expect(find.textContaining('updates progress'), findsOneWidget);
  });
}
