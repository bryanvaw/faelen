import 'package:faelen/core/link_opener.dart';
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

  test('links open normally off Android (no browser list, nothing to ask)', () async {
    expect(LinkOpener.supported, isFalse);
    expect(await LinkOpener.browsers(), isEmpty);
  });
}
