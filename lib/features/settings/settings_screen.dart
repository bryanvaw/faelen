import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/link_opener.dart';
import '../../core/settings_store.dart';
import '../../core/theme.dart';
import '../../core/update_service.dart';
import '../media/media_theme.dart';
import '../media/models/media_entry.dart';
import '../media/services/release_reminders.dart';
import '../media/state/media_store.dart';
import 'backup_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  void _toast(BuildContext context, String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _export(BuildContext context) async {
    final media = context.read<MediaStore>();
    try {
      final now = DateTime.now();
      final json = await BackupService().build(media, now: now);
      final name = BackupService.fileName(now);
      final result = await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(utf8.encode(json), mimeType: 'application/json', name: name)],
        fileNameOverrides: [name],
        subject: 'Faelen backup',
      ));
      if (result.status != ShareResultStatus.dismissed && context.mounted) {
        await context.read<SettingsStore>().markBackedUp(now);
      }
    } catch (e) {
      if (context.mounted) _toast(context, 'Could not export: $e');
    }
  }

  Future<void> _import(BuildContext context) async {
    final media = context.read<MediaStore>();
    try {
      final files = await FilePicker.pickFiles(type: FileType.any);
      if (files.isEmpty) return;
      final json = utf8.decode(await files.first.readAsBytes());
      if (!context.mounted) return;

      final replace = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Import backup'),
          content: const Text('Merge adds the backup to your current list (the newer copy of any duplicate wins). '
              'Replace deletes your current list first.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Replace')),
            FilledButton(onPressed: () => Navigator.pop(d, false), child: const Text('Merge')),
          ],
        ),
      );
      if (replace == null) return;

      final n = await BackupService().restore(json, media, replace: replace);
      if (context.mounted) _toast(context, 'Imported $n ${n == 1 ? 'entry' : 'entries'}');
    } on FormatException catch (e) {
      if (context.mounted) _toast(context, e.message);
    } catch (e) {
      if (context.mounted) _toast(context, 'Could not import: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final settings = context.watch<SettingsStore>();
    return ColoredBox(
      color: p.bg,
      child: Scaffold(
        appBar: AppBar(title: Text('Settings', style: heading(22, weight: FontWeight.w700, color: p.text))),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 28), children: [
                const _GroupTitle('Preferences'),
                _Group(children: [
                  _Row(
                    icon: Icons.contrast_rounded,
                    color: typeColor(MediaType.manhwa),
                    title: 'Appearance',
                    subtitle: _themeLabel(settings.themeMode),
                    trailing: Icon(Icons.chevron_right_rounded, color: p.subText),
                    onTap: () => _chooseTheme(context),
                  ),
                  _Row(
                    icon: Icons.link_rounded,
                    color: typeColor(MediaType.anime),
                    title: 'Progress from links',
                    subtitle: settings.autoUrlProgress
                        ? 'A chapter or episode number in a link updates progress.'
                        : 'Faelen asks before using the number in a link.',
                    trailing: Switch(value: settings.autoUrlProgress, onChanged: settings.setAutoUrlProgress),
                    onTap: () => settings.setAutoUrlProgress(!settings.autoUrlProgress),
                  ),
                  if (LinkOpener.supported)
                    _Row(
                      icon: Icons.open_in_browser_rounded,
                      color: typeColor(MediaType.movie),
                      title: 'Open links with',
                      subtitle: _browserLabel(settings),
                      trailing: Icon(Icons.chevron_right_rounded, color: p.subText),
                      onTap: () => showModalBottomSheet<void>(
                        context: context,
                        useSafeArea: true,
                        isScrollControlled: true,
                        builder: (_) => const _BrowserSheet(),
                      ),
                    ),
                  if (LinkOpener.supported)
                    _Row(
                      icon: Icons.screenshot_rounded,
                      color: typeColor(MediaType.drama),
                      title: 'Block Vault screenshots',
                      subtitle: settings.blockScreenshots
                          ? 'The Vault cannot be screenshotted or recorded, and is blank in recent apps.'
                          : 'Screenshots are allowed in the Vault. Turn on again when you finish testing.',
                      trailing: Switch(value: settings.blockScreenshots, onChanged: settings.setBlockScreenshots),
                      onTap: () => settings.setBlockScreenshots(!settings.blockScreenshots),
                    ),
                  if (ReleaseReminders.supported)
                    _Row(
                      icon: Icons.notifications_active_rounded,
                      color: typeColor(MediaType.movie),
                      title: 'Release reminders',
                      subtitle: 'Notify on release day. Days and time are set on each show.',
                      trailing: Switch(value: settings.releaseReminders, onChanged: (on) => _setReminders(context, settings, on)),
                      onTap: () => _setReminders(context, settings, !settings.releaseReminders),
                    ),
                  if (ReleaseReminders.supported && settings.releaseReminders)
                    _Row(
                      icon: Icons.schedule_rounded,
                      color: typeColor(MediaType.drama),
                      title: 'Default reminder time',
                      subtitle: context.read<ReleaseReminders>().timezoneFailed
                          ? "Your phone's timezone could not be read, so times may be off."
                          : 'Used for shows without their own time.',
                      trailing: OutlinedButton(
                        onPressed: () => _pickDefaultTime(context, settings),
                        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 12)),
                        child: Text(TimeOfDay(hour: settings.defaultReminderMinutes ~/ 60, minute: settings.defaultReminderMinutes % 60).format(context)),
                      ),
                    ),
                  if (ReleaseReminders.supported && settings.releaseReminders)
                    _Row(
                      icon: Icons.notifications_none_rounded,
                      color: p.primary,
                      title: 'Send a test notification',
                      subtitle: 'Check that reminders reach you.',
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () async {
                        final ok = await context.read<ReleaseReminders>().showTest();
                        if (context.mounted) _toast(context, ok ? 'Test sent' : 'Could not send. Check notification permission.');
                      },
                    ),
                ]),
                const _GroupTitle('App and data'),
                _Group(children: [
                  const _UpdateCheck(),
                  _Row(
                    icon: Icons.save_alt_rounded,
                    color: p.primary,
                    title: 'Backup',
                    subtitle: _backupNote(settings.lastBackup, context.read<MediaStore>().totalCount),
                    below: Row(children: [
                      Expanded(child: _BrutalButton(label: 'Export', icon: Icons.upload_rounded, primary: true, onPressed: () => _export(context))),
                      const SizedBox(width: 12),
                      Expanded(child: _BrutalButton(label: 'Import', icon: Icons.download_rounded, onPressed: () => _import(context))),
                    ]),
                  ),
                ]),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 16, 4, 0),
                  child: Text('Movie covers come from TMDB. This product uses the TMDB API but is not endorsed or certified by TMDB.',
                      style: TextStyle(color: p.subText, fontSize: 11.5, height: 1.35)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  static String _browserLabel(SettingsStore s) => switch (s.browserChoice) {
        null => 'Your phone\'s default browser',
        LinkOpener.ask => 'Ask every time',
        _ => s.browserLabel ?? 'A chosen browser',
      };

  static String _themeLabel(ThemeMode m) => switch (m) {
        ThemeMode.system => 'System default',
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
      };

  Future<void> _chooseTheme(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        builder: (_) => const _AppearanceSheet(),
      );

  static String _backupNote(int last, int entries) {
    if (last == 0) return entries == 0 ? 'Your data only lives on this phone.' : 'Never backed up. Your data only lives on this phone.';
    final days = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(last)).inDays;
    final when = days <= 0 ? 'today' : (days == 1 ? 'yesterday' : '$days days ago');
    return days >= 30 && entries > 0 ? 'Last backup $when. Time for a new one.' : 'Last backup $when.';
  }

  Future<void> _pickDefaultTime(BuildContext context, SettingsStore settings) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: settings.defaultReminderMinutes ~/ 60, minute: settings.defaultReminderMinutes % 60),
    );
    if (t != null) settings.setDefaultReminderMinutes(t.hour * 60 + t.minute);
  }

  /// Turning reminders on asks for notification permission first; a refusal leaves the switch off.
  Future<void> _setReminders(BuildContext context, SettingsStore settings, bool on) async {
    if (on && !await context.read<ReleaseReminders>().requestPermission()) {
      if (context.mounted) _toast(context, 'Allow notifications for Faelen in system settings to get reminders');
      return;
    }
    settings.setReleaseReminders(on);
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Text(text, style: heading(16, weight: FontWeight.w700, color: p.text)),
    );
  }
}

/// One outlined card holding several rows, split by hairlines, instead of a card per setting.
class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4), // room for the hard shadow
      child: Container(
        decoration: brutal(p, radius: 18, shadow: 3),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: p.outline.withValues(alpha: 0.6)),
            children[i],
          ],
        ]),
      ),
    );
  }
}

/// A setting: tinted icon, title and one short line, then either a trailing control (switch, button)
/// or a full-width control underneath.
class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
    this.trailing,
    this.below,
    this.onTap,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? below;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 38,
              height: 38,
              decoration: brutal(p, color: color, radius: 11, shadow: 0, border: 1.5),
              child: Icon(icon, size: 20, color: onTile),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: heading(15, weight: FontWeight.w700, color: p.text)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!, style: TextStyle(color: p.subText, fontSize: 12.5, height: 1.3)),
                  ),
              ]),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ]),
          if (below != null) ...[const SizedBox(height: 12), below!],
        ]),
      ),
    );
  }
}

class _UpdateCheck extends StatefulWidget {
  const _UpdateCheck();

  @override
  State<_UpdateCheck> createState() => _UpdateCheckState();
}

class _UpdateCheckState extends State<_UpdateCheck> {
  String? _version;
  bool _busy = false;
  bool _failed = false;
  String? _message;
  UpdateInfo? _update;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((i) {
      if (mounted) setState(() => _version = i.version);
    }).catchError((_) {});
  }

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _failed = false;
      _message = null;
      _update = null;
    });
    try {
      final current = _version ?? (await PackageInfo.fromPlatform()).version;
      final update = await UpdateService().checkFor(current);
      if (!mounted) return;
      setState(() {
        _update = update;
        _message = update == null ? 'You have the latest version.' : 'Version ${update.version} is available.';
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
          _message = 'Could not check. Are you online?';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final update = _update;
    return _Row(
      icon: Icons.system_update_rounded,
      color: typeColor(MediaType.drama),
      title: 'Faelen ${_version ?? '...'}',
      subtitle: 'Checked quietly once a day on GitHub.',
      below: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _BrutalButton(
          label: _busy ? 'Checking...' : 'Check for updates',
          icon: Icons.refresh_rounded,
          busy: _busy,
          onPressed: _check,
        ),
        if (_message != null) ...[
          const SizedBox(height: 12),
          _StatusNote(message: _message!, failed: _failed),
        ],
        if (update != null) ...[
          const SizedBox(height: 12),
          _BrutalButton(
            label: 'Download ${update.version}',
            icon: Icons.download_rounded,
            primary: true,
            onPressed: () => launchUrl(update.apkUrl, mode: LaunchMode.externalApplication),
          ),
          if (update.notes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(update.notes, maxLines: 4, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.subText, fontSize: 12.5, height: 1.35)),
          ],
          const SizedBox(height: 6),
          Text('Open the file when it finishes and tap Install. Your entries are kept.',
              style: TextStyle(color: p.subText, fontSize: 12.5, height: 1.35)),
        ],
      ]),
    );
  }
}

/// The result of an update check: a calm confirmation or a clear problem, with an icon so it does not rely on colour alone.
class _StatusNote extends StatelessWidget {
  const _StatusNote({required this.message, required this.failed});
  final String message;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final tone = failed ? const Color(0xFFF26B50) : const Color(0xFF4EC5B8);
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: tone, width: 1.5),
        ),
        child: Row(children: [
          Icon(failed ? Icons.wifi_off_rounded : Icons.check_circle_rounded, size: 18, color: tone),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: TextStyle(color: p.text, fontSize: 13, fontWeight: FontWeight.w700))),
        ]),
      ),
    );
  }
}

/// The one button style for Settings: thick outline, hard shadow that flattens when pressed.
/// [primary] fills with the accent colour; otherwise it sits on the card colour.
class _BrutalButton extends StatefulWidget {
  const _BrutalButton({required this.label, required this.icon, required this.onPressed, this.primary = false, this.busy = false});
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool primary;
  final bool busy;

  @override
  State<_BrutalButton> createState() => _BrutalButtonState();
}

class _BrutalButtonState extends State<_BrutalButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final enabled = !widget.busy;
    final fg = widget.primary ? p.onPrimary : p.text;
    const lift = 3.0;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => setState(() => _down = true) : null,
          onTapCancel: () => setState(() => _down = false),
          onTapUp: (_) => setState(() => _down = false),
          onTap: enabled ? widget.onPressed : null,
          child: Padding(
            padding: const EdgeInsets.only(bottom: lift),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 90),
              height: 48,
              transform: Matrix4.translationValues(0, _down ? lift : 0, 0),
              decoration: brutal(p, color: widget.primary ? p.primary : p.card, radius: 14, shadow: _down ? 0 : lift),
              child: Opacity(
                opacity: enabled ? 1 : 0.7,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  widget.busy
                      ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5, color: fg))
                      : Icon(widget.icon, size: 19, color: fg),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(widget.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: heading(14.5, weight: FontWeight.w700, color: fg)),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pick where media links open. Two ways of working first (the phone's default, or Android's list
/// every time), then "Always use" with every browser installed on the phone, shown with its own
/// icon. Applied as soon as one is tapped; the sheet closes after a beat so the check is seen.
class _BrowserSheet extends StatefulWidget {
  const _BrowserSheet();

  @override
  State<_BrowserSheet> createState() => _BrowserSheetState();
}

class _BrowserSheetState extends State<_BrowserSheet> {
  // Asked once, not on every rebuild, so choosing a row does not make the list flash.
  late final Future<List<Browser>> _browsers = LinkOpener.browsers();
  bool _closing = false;

  Future<void> _choose(SettingsStore settings, String? choice, {String? label}) async {
    if (_closing) return;
    _closing = true;
    HapticFeedback.selectionClick();
    settings.setBrowser(choice, label: label);
    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final settings = context.watch<SettingsStore>();
    final choice = settings.browserChoice;

    Widget check(bool selected) => AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? p.primary : Colors.transparent,
            border: Border.all(color: selected ? p.ink : p.outline, width: 2),
          ),
          child: selected ? Icon(Icons.check_rounded, size: 16, color: p.onPrimary) : null,
        );

    Widget row({
      required Widget leading,
      required String title,
      String? note,
      required bool selected,
      required VoidCallback onTap,
      double pad = 14,
    }) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Semantics(
            button: true,
            selected: selected,
            label: note == null ? title : '$title. $note',
            child: ExcludeSemantics(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTap,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 56),
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: pad),
                  decoration: brutal(p, color: p.card, radius: 16, shadow: selected ? 3 : 0, border: selected ? 3 : 1.5),
                  child: Row(children: [
                    leading,
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: heading(16, weight: FontWeight.w700, color: p.text)),
                        if (note != null) ...[
                          const SizedBox(height: 2),
                          Text(note, style: TextStyle(color: p.subText, fontSize: 12.5, height: 1.3)),
                        ],
                      ]),
                    ),
                    const SizedBox(width: 10),
                    check(selected),
                  ]),
                ),
              ),
            ),
          ),
        );

    Widget modeIcon(IconData icon) => Container(
          width: 42,
          height: 42,
          decoration: brutal(p, color: p.field, radius: 12, shadow: 0, border: 1.5),
          child: Icon(icon, size: 22, color: p.text),
        );

    Widget browserIcon(Browser b) => ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: SizedBox(
            width: 42,
            height: 42,
            child: b.icon == null
                ? ColoredBox(color: p.field, child: Icon(Icons.public_rounded, size: 22, color: p.text))
                : Image.memory(b.icon!, fit: BoxFit.cover, gaplessPlayback: true, excludeFromSemantics: true),
          ),
        );

    Widget groupLabel(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(2, 8, 2, 10),
          child: Text(text, style: TextStyle(color: p.subText, fontSize: 13, fontWeight: FontWeight.w800)),
        );

    Widget message(IconData icon, String text) => Padding(
          padding: const EdgeInsets.fromLTRB(2, 2, 2, 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 18, color: p.subText),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: TextStyle(color: p.subText, fontSize: 12.5, height: 1.35))),
          ]),
        );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Open links with', style: heading(22, weight: FontWeight.w700, color: p.text)),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 16),
          child: Text('Used when you tap Continue, and when you tap a release reminder.', style: TextStyle(color: p.subText, fontSize: 13, height: 1.35)),
        ),
        row(
          leading: modeIcon(Icons.phone_android_rounded),
          title: 'Default browser',
          note: 'Whatever your phone normally uses',
          selected: choice == null,
          onTap: () => _choose(settings, null),
        ),
        row(
          leading: modeIcon(Icons.help_outline_rounded),
          title: 'Ask every time',
          note: 'Faelen lists your browsers each time you open a link',
          selected: choice == LinkOpener.ask,
          onTap: () => _choose(settings, LinkOpener.ask),
        ),
        groupLabel('Always use'),
        FutureBuilder<List<Browser>>(
          future: _browsers,
          builder: (_, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3))),
              );
            }
            final list = snap.data ?? const <Browser>[];
            // A browser picked earlier that is no longer on the phone: say why nothing is ticked.
            final gone = choice != null && choice != LinkOpener.ask && !list.any((b) => b.package == choice);
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (gone)
                message(Icons.info_outline_rounded, '${settings.browserLabel ?? 'The browser you picked'} is no longer installed, so links open in your default browser.'),
              if (list.isEmpty)
                message(Icons.search_off_rounded, 'No other browsers were found on this phone.')
              else
                for (final b in list)
                  row(
                    leading: browserIcon(b),
                    title: b.label,
                    selected: choice == b.package,
                    onTap: () => _choose(settings, b.package, label: b.label),
                    pad: 7,
                  ),
            ]);
          },
        ),
      ]),
    );
  }
}

/// Pick the theme: three large options, each with a short explanation, applied as soon as one is tapped.
class _AppearanceSheet extends StatelessWidget {
  const _AppearanceSheet();

  static const _options = [
    (ThemeMode.system, Icons.brightness_auto_rounded, 'System default', 'Match your phone, light by day and dark by night'),
    (ThemeMode.light, Icons.light_mode_rounded, 'Light', 'Always light'),
    (ThemeMode.dark, Icons.dark_mode_rounded, 'Dark', 'Always dark, easier on the eyes at night'),
  ];

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final settings = context.watch<SettingsStore>();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Text('Appearance', style: heading(22, weight: FontWeight.w700, color: p.text)),
        ),
        for (final (mode, icon, title, note) in _options)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Semantics(
              button: true,
              selected: settings.themeMode == mode,
              label: '$title. $note',
              child: ExcludeSemantics(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    settings.setThemeMode(mode);
                    Navigator.pop(context);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: brutal(p,
                        color: p.card,
                        radius: 16,
                        shadow: settings.themeMode == mode ? 3 : 0,
                        border: settings.themeMode == mode ? 3 : 1.5),
                    child: Row(children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: brutal(p, color: p.field, radius: 12, shadow: 0, border: 1.5),
                        child: Icon(icon, size: 22, color: p.text),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(title, style: heading(16, weight: FontWeight.w700, color: p.text)),
                          const SizedBox(height: 2),
                          Text(note, style: TextStyle(color: p.subText, fontSize: 12.5, height: 1.3)),
                        ]),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: settings.themeMode == mode ? p.primary : Colors.transparent,
                          border: Border.all(color: settings.themeMode == mode ? p.ink : p.outline, width: 2),
                        ),
                        child: settings.themeMode == mode ? Icon(Icons.check_rounded, size: 16, color: p.onPrimary) : null,
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}
