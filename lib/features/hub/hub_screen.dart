import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/link_opener.dart';
import '../../core/theme.dart';
import '../../core/update_service.dart';
import '../media/media_theme.dart';
import '../media/models/media_entry.dart';
import '../media/screens/media_screen.dart';
import '../media/services/pinned_store.dart';
import '../media/services/release_schedule.dart';
import '../media/state/media_store.dart';
import '../settings/settings_screen.dart';
import '../vault/screens/vault_screen.dart';

class _Module {
  const _Module({required this.title, required this.subtitle, required this.cat, required this.color, this.builder});
  final String title;
  final String subtitle;

  /// The module's cat illustration in `assets/cats/`. Each module gets its own.
  final String cat;

  /// The tile colour behind the cat; it gives the cat's black outline something light to sit on.
  final Color color;
  final WidgetBuilder? builder; // null = not built yet
}

final _media = _Module(
  title: 'Media',
  subtitle: 'Webtoons, anime, movies & K-dramas',
  cat: 'assets/cats/media.png',
  color: const Color(0xFFFF8A65),
  builder: (_) => const MediaScreen(),
);

final _vault = _Module(
  title: 'Vault',
  subtitle: 'Logins, numbers & IDs, locked on this phone',
  cat: 'assets/cats/passwords.png',
  color: const Color(0xFFB99BFF),
  builder: (_) => const VaultFlow(),
);

const _soon = <_Module>[
  _Module(title: 'Planner', subtitle: 'Tasks, goals & reminders', cat: 'assets/cats/planner.png', color: Color(0xFF7BD389)),
  _Module(title: 'Budget', subtitle: 'Income, expenses & monthly limits', cat: 'assets/cats/budget.png', color: Color(0xFFFFD166)),
];

/// App home: Media is the live module (large card plus a way back to what you were following);
/// the others sit below as "Soon" tiles.
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
    final service = UpdateService();
    try {
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
      // Offline or GitHub unreachable: stay quiet, Settings has a manual check. The attempt does
      // not count, so the next launch tries again instead of waiting a day.
      await service.forgetAutoCheck();
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
                  const SizedBox(height: 22),
                  const _MediaHero(),
                  const _ContinueStrip(),
                  const SizedBox(height: 26),
                  Text('More modules', style: heading(15, weight: FontWeight.w700, color: p.subText)),
                  const SizedBox(height: 12),
                  LayoutBuilder(builder: (context, c) {
                    const gap = 12.0;
                    final w = (c.maxWidth - gap * 2 - 4) / 3; // a little room for the hard shadow
                    return Wrap(spacing: gap, runSpacing: gap, children: [
                      for (final m in [_vault, ..._soon]) SizedBox(width: w, child: _SoonTile(module: m)),
                    ]);
                  }),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A card that sinks onto its shadow while pressed, like the buttons in Settings.
class _Pressable extends StatefulWidget {
  const _Pressable({required this.onTap, required this.builder, this.lift = 4});
  final VoidCallback onTap;
  final Widget Function(bool pressed) builder;
  final double lift;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      child: Padding(
        padding: EdgeInsets.only(bottom: widget.lift),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          transform: Matrix4.translationValues(0, _down ? widget.lift : 0, 0),
          child: widget.builder(_down),
        ),
      ),
    );
  }
}

/// The cat on its colour tile.
class _CatTile extends StatelessWidget {
  const _CatTile({required this.module, required this.size});
  final _Module module;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.08),
      decoration: brutal(p, color: module.color, radius: size * 0.26, shadow: 3),
      child: Image.asset(module.cat, fit: BoxFit.contain, excludeFromSemantics: true),
    );
  }
}

/// Media is the one live module, so it is the large card and shows where the list stands.
class _MediaHero extends StatelessWidget {
  const _MediaHero();

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final store = context.watch<MediaStore>();
    final now = DateTime.now();
    final watching = store.items.where((e) => e.status == Status.watching).length;
    final fresh = store.items.fold<int>(0, (a, e) => a + (releaseStatus(e, now)?.behind ?? 0));
    final parts = [if (watching > 0) '$watching watching', if (fresh > 0) '$fresh new'];
    final line = parts.isEmpty ? _media.subtitle : parts.join(' · ');
    return Semantics(
      button: true,
      label: 'Media. $line',
      child: ExcludeSemantics(
        child: _Pressable(
          onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: _media.builder!)),
          builder: (pressed) => Container(
            padding: const EdgeInsets.all(16),
            decoration: brutal(p, color: p.card, radius: 20, shadow: pressed ? 0 : 4),
            child: Row(children: [
              _CatTile(module: _media, size: 76),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Media', style: heading(22, weight: FontWeight.w700, color: p.text)),
                  const SizedBox(height: 3),
                  Text(line, style: TextStyle(color: p.subText, fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.3)),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, color: p.text, size: 28),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The title you touched last that you are still following, with a one-tap way back to it.
class _ContinueStrip extends StatelessWidget {
  const _ContinueStrip();

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final items = context.watch<MediaStore>().items.where((e) => e.status == Status.watching && e.type != MediaType.movie).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (items.isEmpty) return const SizedBox.shrink();
    final e = items.first;
    final progress = '${e.season > 0 ? 'S${e.season} · ' : ''}${e.type.unit} ${e.current} / ${e.total > 0 ? e.total : '?'}';
    final uri = e.url.isEmpty ? null : Uri.tryParse(e.url);
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        decoration: BoxDecoration(
          color: p.field,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: p.outline, width: 1.5),
        ),
        child: Row(children: [
          Icon(typeIcon(e.type), size: 22, color: p.subText),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Pick up where you left off', style: TextStyle(color: p.subText, fontSize: 11.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: heading(15, weight: FontWeight.w700, color: p.text)),
              Text(progress, style: TextStyle(color: p.subText, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ]),
          ),
          if (uri != null) ...[
            const SizedBox(width: 10),
            _ContinueButton(onTap: () async {
              await context.read<PinnedStore?>()?.pinForContinue(e); // same as Continue on a card
              try {
                await LinkOpener.open(uri);
              } catch (_) {
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open that link')));
              }
            }),
          ],
        ]),
      ),
    );
  }
}

class _ContinueButton extends StatelessWidget {
  const _ContinueButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      button: true,
      label: 'Continue',
      child: ExcludeSemantics(
        child: _Pressable(
          lift: 2,
          onTap: onTap,
          builder: (pressed) => Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.center,
            decoration: brutal(p, color: p.primary, radius: 14, shadow: pressed ? 0 : 2),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.open_in_new_rounded, size: 16, color: p.onPrimary),
              const SizedBox(width: 6),
              Text('Continue', style: heading(13.5, weight: FontWeight.w700, color: p.onPrimary)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// A small module tile: its cat, its name and a badge. Unbuilt modules say "Soon" and explain themselves when
/// tapped; the Vault opens (its badge says Locked, and the hub never shows what is inside).
class _SoonTile extends StatelessWidget {
  const _SoonTile({required this.module});
  final _Module module;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      button: true,
      label: module.builder == null ? '${module.title}, coming soon. ${module.subtitle}' : '${module.title}. ${module.subtitle}',
      child: ExcludeSemantics(
        child: _Pressable(
          lift: 3,
          onTap: () {
            final open = module.builder;
            if (open != null) {
              Navigator.push(context, MaterialPageRoute<void>(builder: open));
              return;
            }
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text('${module.title} is coming soon: ${module.subtitle}')));
          },
          builder: (pressed) => Container(
            padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
            decoration: brutal(p, color: p.card, radius: 16, shadow: pressed ? 0 : 3, border: 1.5),
            child: Column(children: [
              _CatTile(module: module, size: 60),
              const SizedBox(height: 10),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(module.title, maxLines: 1, style: heading(14, weight: FontWeight.w700, color: p.text)),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: p.field, borderRadius: BorderRadius.circular(8)),
                child: module.builder == null
                    ? Text('Soon', style: TextStyle(color: p.subText, fontSize: 11, fontWeight: FontWeight.w800))
                    : FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.lock_rounded, size: 11, color: p.text),
                          const SizedBox(width: 3),
                          Text('Locked', maxLines: 1, style: TextStyle(color: p.text, fontSize: 11, fontWeight: FontWeight.w800)),
                        ]),
                      ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
