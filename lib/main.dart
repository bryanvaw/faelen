import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'services/storage_service.dart';
import 'state/media_store.dart';
import 'theme.dart';

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => MediaStore(StorageService())..load(),
      child: MaterialApp(
        title: 'Media Tracker',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: ThemeMode.light, // light only for now; dark theme is ready (use ThemeMode.system)
        home: const HomeScreen(),
      ),
    );
  }
}
