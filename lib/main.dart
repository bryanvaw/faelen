import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/settings_store.dart';
import 'core/theme.dart';
import 'features/hub/hub_screen.dart';
import 'features/media/services/link_preview_service.dart';
import 'features/media/services/storage_service.dart';
import 'features/media/state/media_store.dart';

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider(create: (_) => LinkPreviewService()),
        ChangeNotifierProvider(create: (_) => SettingsStore()..load()),
        ChangeNotifierProvider(create: (_) => MediaStore(StorageService())..load()),
      ],
      child: Consumer<SettingsStore>(
        builder: (_, settings, _) => MaterialApp(
          title: 'Faelen',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: settings.themeMode,
          home: const HubScreen(checkForUpdates: true),
        ),
      ),
    );
  }
}
