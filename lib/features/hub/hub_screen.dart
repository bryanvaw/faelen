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
import '../budget/screens/budget_screen.dart';
import '../vault/screens/vault_screen.dart';
import '../planner/screens/planner_screen.dart';
import '../planner/state/planner_store.dart';
import '../budget/models/budget_models.dart';
import '../budget/state/budget_store.dart';

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

final _budget = _Module(
  title: 'Budget',
  subtitle: 'Cards, spending & monthly limits',
  cat: 'assets/cats/budget.png',
  color: const Color(0xFFFFD166),
  builder: (_) => const BudgetScreen(),
);

final _planner = _Module(
  title: 'Planner',
  subtitle: 'Tasks, due dates & reminders',
  cat: 'assets/cats/planner.png',
  color: const Color(0xFF8FB0E0),
  builder: (_) => const PlannerScreen(),
);

/// App home: the four modules as equal tiles, each saying what it has for today, then a way back
/// to the title you were following.
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
    final planner = context.watch<PlannerStore?>();
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
                  // Two by two; each row's tiles are as tall as the taller one.
                  for (final row in [
                    [
                      _ModuleTile(module: _media, line: _mediaLine(context.watch<MediaStore>())),
                      _ModuleTile(module: _planner, line: _plannerLine(planner), alert: (planner?.overdueCount ?? 0) > 0),
                    ],
                    [
                      _ModuleTile(module: _budget, line: _budgetLine(context.watch<BudgetStore?>())),
                      _ModuleTile(module: _vault, line: 'Locked', locked: true),
                    ],
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: IntrinsicHeight(
                        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Expanded(child: row[0]),
                          const SizedBox(width: 12),
                          Expanded(child: row[1]),
                        ]),
                      ),
                    ),
                  const _ContinueStrip(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Something that dips a little while pressed.
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
      decoration: brutal(p, color: module.color, radius: size * 0.26, shadow: 3, strong: true),
      child: Image.asset(module.cat, fit: BoxFit.contain, excludeFromSemantics: true),
    );
  }
}

/// What each module has to say today, shown on its tile. Never an amount or anything from inside
/// the Vault: the hub can be seen over a shoulder.
String _mediaLine(MediaStore store) {
  final now = DateTime.now();
  final watching = store.items.where((e) => e.status == Status.watching).length;
  final fresh = store.items.fold<int>(0, (a, e) => a + (releaseStatus(e, now)?.behind ?? 0));
  final parts = [if (watching > 0) '$watching watching', if (fresh > 0) '$fresh new'];
  return parts.isEmpty ? _media.subtitle : parts.join(' · ');
}

String _plannerLine(PlannerStore? store) {
  if (store == null || store.loading) return _planner.subtitle;
  final overdue = store.overdueCount, today = store.todayCount - store.overdueCount;
  final parts = [if (today > 0) '$today due today', if (overdue > 0) '$overdue overdue'];
  if (parts.isNotEmpty) return parts.join(' · ');
  return store.upcomingCount > 0 ? 'Nothing due today' : _planner.subtitle;
}

String _budgetLine(BudgetStore? store) {
  if (store == null || store.loading || store.accounts.isEmpty) return _budget.subtitle;
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  Bill? next;
  for (final b in store.bills) {
    if (store.account(b.accountId) == null) continue;
    if (next == null || store.nextDue(b).isBefore(store.nextDue(next))) next = b;
  }
  if (next != null) {
    final d = store.nextDue(next);
    return '${next.name} due ${months[d.month - 1]} ${d.day}';
  }
  final n = store.accounts.length;
  return '$n ${n == 1 ? 'card' : 'cards'}';
}

/// One module: its cat, its name and what it has to say today. All four are the same size, so the
/// hub reads as a home screen rather than one module and some extras.
class _ModuleTile extends StatelessWidget {
  const _ModuleTile({required this.module, required this.line, this.locked = false, this.alert = false});
  final _Module module;
  final String line;

  /// Shows a lock beside [line] (the Vault never says what is inside).
  final bool locked;

  /// The line is something that wants attention (overdue tasks): it is drawn in the text colour
  /// instead of the quieter one.
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      button: true,
      label: '${module.title}. $line',
      child: ExcludeSemantics(
        child: _Pressable(
          lift: 2,
          onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: module.builder!)),
          builder: (pressed) => Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
            decoration: brutal(p, color: pressed ? quiet(p, 0.1) : null, radius: 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _CatTile(module: module, size: 54),
              const SizedBox(height: 14),
              Text(module.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: heading(18, weight: FontWeight.w700, color: p.text)),
              const SizedBox(height: 3),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (locked) ...[
                  Padding(padding: const EdgeInsets.only(top: 2), child: Icon(Icons.lock_rounded, size: 13, color: p.subText)),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Text(
                    line,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: alert ? p.text : p.subText, fontSize: 13, fontWeight: alert ? FontWeight.w700 : FontWeight.w600, height: 1.3),
                  ),
                ),
              ]),
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
      padding: const EdgeInsets.only(top: 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        decoration: brutal(p, radius: 18),
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
