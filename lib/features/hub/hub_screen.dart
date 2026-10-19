import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../core/update_service.dart';
import '../media/screens/media_screen.dart';
import '../settings/settings_screen.dart';

class _Module {
  const _Module({required this.title, required this.subtitle, required this.icon, required this.color, this.builder});
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final WidgetBuilder? builder; // null = not built yet
}

final _modules = <_Module>[
  _Module(
    title: 'Media',
    subtitle: 'Webtoons, anime, movies & K-dramas',
    icon: Icons.movie_filter_rounded,
    color: const Color(0xFFFF6B5E),
    builder: (_) => const MediaScreen(),
  ),
  const _Module(
    title: 'Planner',
    subtitle: 'Tasks, goals & reminders',
    icon: Icons.checklist_rounded,
    color: Color(0xFF7BD389),
  ),
  const _Module(
    title: 'Budget',
    subtitle: 'Income, expenses & monthly limits',
    icon: Icons.account_balance_wallet_rounded,
    color: Color(0xFFFFD166),
  ),
  const _Module(
    title: 'Passwords',
    subtitle: 'Accounts & logins, kept on this device',
    icon: Icons.key_rounded,
    color: Color(0xFFB99BFF),
  ),
];

/// App home: pick a module. Modules without a [builder] show as "Coming soon".
class HubScreen extends StatefulWidget {
  const HubScreen({super.key, this.checkForUpdates = false});

  /// Look for a newer release on GitHub (at most once a day) and offer it in a snackbar.
  final bool checkForUpdates;

  @override
  State<HubScreen> createState() => _HubScreenState();
}

class _HubScreenState extends State<HubScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.checkForUpdates) _checkForUpdate();
  }

  Future<void> _checkForUpdate() async {
    try {
      final service = UpdateService();
      if (!await service.shouldAutoCheck()) return;
      final current = (await PackageInfo.fromPlatform()).version;
      final update = await service.checkFor(current);
      if (update == null || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Faelen ${update.version} is available'),
        duration: const Duration(seconds: 10),
        action: SnackBarAction(
          label: 'Download',
          onPressed: () => launchUrl(update.apkUrl, mode: LaunchMode.externalApplication),
        ),
      ));
    } catch (_) {
      // Offline or GitHub unreachable: stay quiet, Settings has a manual check.
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return ColoredBox(
      color: p.bg,
      child: Scaffold(
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                children: [
                  Row(children: [
                    Expanded(child: Text('Faelen', style: heading(32, weight: FontWeight.w700, color: p.text, height: 1.15))),
                    IconButton(
                      tooltip: 'Settings',
                      onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
                      icon: Icon(Icons.settings_rounded, color: p.text),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Text('Your personal space', style: TextStyle(color: p.subText, fontSize: 14, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 24),
                  for (final m in _modules)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: _ModuleCard(module: m),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({required this.module});
  final _Module module;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final builder = module.builder;
    final enabled = builder != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: enabled ? module.title : '${module.title}, coming soon',
      child: GestureDetector(
        onTap: enabled ? () => Navigator.push(context, MaterialPageRoute<void>(builder: builder)) : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.6,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: brutal(p, color: p.card, radius: 18, shadow: enabled ? 4 : 0),
            child: Row(children: [
              Container(
                width: 56,
                height: 56,
                decoration: brutal(p, color: module.color, radius: 16, shadow: 3),
                child: Icon(module.icon, color: onTile, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(module.title, style: heading(20, weight: FontWeight.w700, color: p.text)),
                  const SizedBox(height: 2),
                  Text(enabled ? module.subtitle : 'Coming soon',
                      style: TextStyle(color: p.subText, fontSize: 13, fontWeight: FontWeight.w500)),
                ]),
              ),
              if (enabled) Icon(Icons.chevron_right_rounded, color: p.text),
            ]),
          ),
        ),
      ),
    );
  }
}
