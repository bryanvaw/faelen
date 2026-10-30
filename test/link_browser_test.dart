import 'package:faelen/core/browser_picker.dart';
import 'package:faelen/core/link_opener.dart';
import 'package:faelen/core/theme.dart';
import 'package:flutter/material.dart';
import 'package:faelen/core/settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('no saved choice means the default browser', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await LinkOpener.savedChoice(), isNull);
  });

  test('a chosen browser and "ask every time" are remembered', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsStore();
    await s.setBrowser('com.brave.browser', label: 'Brave');
    expect(await LinkOpener.savedChoice(), 'com.brave.browser');

    final again = SettingsStore();
    await again.load();
    expect(again.browserChoice, 'com.brave.browser');
    expect(again.browserLabel, 'Brave');

    await again.setBrowser(LinkOpener.ask);
    expect(await LinkOpener.savedChoice(), LinkOpener.ask);
    expect(again.browserLabel, isNull);

    await again.setBrowser(null);
    expect(await LinkOpener.savedChoice(), isNull);
  });

  test('the earlier "choose each time" switch carries over as "ask every time"', () async {
    SharedPreferences.setMockInitialValues({LinkOpener.legacyAskKey: true});
    expect(await LinkOpener.savedChoice(), LinkOpener.ask);
    final s = SettingsStore();
    await s.load();
    expect(s.browserChoice, LinkOpener.ask);
  });

  test('screenshot blocking is on by default and the switch is remembered', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsStore();
    await s.load();
    expect(s.blockScreenshots, isTrue);
    await s.setBlockScreenshots(false);
    final again = SettingsStore();
    await again.load();
    expect(again.blockScreenshots, isFalse);
  });

  testWidgets('"Ask every time" shows Faelen\'s own list and returns the browser tapped', (t) async {
    final browsers = [const Browser('com.a.browser', 'Alpha'), const Browser('com.b.browser', 'Beta')];
    Browser? picked;
    var done = false;
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Builder(
        builder: (c) => Scaffold(
          body: TextButton(
            onPressed: () async {
              picked = await showBrowserPicker(c, browsers);
              done = true;
            },
            child: const Text('go'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    await t.tap(find.text('Beta'));
    await t.pumpAndSettle();
    expect(done, isTrue);
    expect(picked?.package, 'com.b.browser');
  });

  testWidgets('dismissing the list picks nothing', (t) async {
    Browser? picked = const Browser('x', 'x');
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Builder(
        builder: (c) => Scaffold(
          body: TextButton(
            onPressed: () async => picked = await showBrowserPicker(c, [const Browser('com.a.browser', 'Alpha')]),
            child: const Text('go'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    await t.tapAt(const Offset(5, 5)); // outside the sheet
    await t.pumpAndSettle();
    expect(picked, isNull);
  });

  test('links open normally off Android (no browser list, nothing to ask)', () async {
    expect(LinkOpener.supported, isFalse);
    expect(await LinkOpener.browsers(), isEmpty);
  });
}
