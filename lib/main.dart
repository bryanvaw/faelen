import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/settings_store.dart';
import 'core/theme.dart';
import 'features/hub/hub_screen.dart';
import 'features/media/services/link_preview_service.dart';
import 'features/media/services/pinned_store.dart';
import 'features/media/services/release_reminders.dart';
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
        Provider(create: (_) => ReleaseReminders()),
        ChangeNotifierProvider(create: (c) => PinnedStore(c.read<ReleaseReminders>())..load()),
        ChangeNotifierProvider(create: (_) => SettingsStore()..load()),
        ChangeNotifierProvider(create: (_) => MediaStore(StorageService.forApp())..load()),
      ],
      child: Consumer<SettingsStore>(
        builder: (_, settings, _) => MaterialApp(
          title: 'Faelen',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: settings.themeMode,
          builder: (context, child) => _ReminderSync(child: child!),
          home: const HubScreen(checkForUpdates: true),
        ),
      ),
    );
  }
}

/// Keeps the scheduled release reminders in step with the library and the Settings switch,
/// and re-plans when the app comes back to the foreground (a new day can finish a series).
class _ReminderSync extends StatefulWidget {
  const _ReminderSync({required this.child});
  final Widget child;

  @override
  State<_ReminderSync> createState() => _ReminderSyncState();
}

class _ReminderSyncState extends State<_ReminderSync> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    // A notification button may have changed the list or the pins while the app was away.
    context.read<MediaStore>().refresh();
    context.read<PinnedStore?>()?.load(reload: true);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final media = context.watch<MediaStore>();
    final settings = context.watch<SettingsStore>();
    if (!media.loading) {
      final reminders = context.read<ReleaseReminders>();
      final items = media.items;
      final enabled = settings.releaseReminders;
      final minutes = settings.defaultReminderMinutes;
      final pinned = context.watch<PinnedStore?>();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        reminders.sync(items, enabled: enabled, defaultMinutes: minutes);
        pinned?.sync(items);
      });
    }
    return widget.child;
  }
}
