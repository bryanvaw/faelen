import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

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
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(utf8.encode(json), mimeType: 'application/json', name: name)],
        fileNameOverrides: [name],
        subject: 'Faelen backup',
      ));
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
                    subtitle: 'Follows your phone unless you choose.',
                    below: SegmentedButton<ThemeMode>(
                      showSelectedIcon: false,
                      expandedInsets: EdgeInsets.zero,
                      style: const ButtonStyle(visualDensity: VisualDensity.compact),
                      segments: [
                        ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_rounded), label: _segLabel('System')),
                        ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_rounded), label: _segLabel('Light')),
                        ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_rounded), label: _segLabel('Dark')),
                      ],
                      selected: {settings.themeMode},
                      onSelectionChanged: (s) => settings.setThemeMode(s.first),
                    ),
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
                  if (ReleaseReminders.supported)
                    _Row(
                      icon: Icons.notifications_active_rounded,
                      color: typeColor(MediaType.movie),
                      title: 'Release reminders',
                      subtitle: 'Notify on release day. Days and time are set on each show.',
                      trailing: Switch(value: settings.releaseReminders, onChanged: (on) => _setReminders(context, settings, on)),
                      onTap: () => _setReminders(context, settings, !settings.releaseReminders),
                    ),
                ]),
                const _GroupTitle('App and data'),
                _Group(children: [
                  const _UpdateCheck(),
                  _Row(
                    icon: Icons.save_alt_rounded,
                    color: p.primary,
                    title: 'Backup',
                    subtitle: 'Your data only lives on this phone.',
                    below: Row(children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _export(context),
                          icon: const Icon(Icons.upload_rounded),
                          label: const Text('Export'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _import(context),
                          icon: const Icon(Icons.download_rounded),
                          label: const Text('Import'),
                        ),
                      ),
                    ]),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
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

/// Segment label that shrinks to fit instead of wrapping mid-word on narrow screens or large fonts.
Widget _segLabel(String text) => FittedBox(fit: BoxFit.scaleDown, child: Text(text, maxLines: 1, softWrap: false));

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
      if (mounted) setState(() => _message = 'Could not check. Are you online?');
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
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 150),
        child: OutlinedButton(
          onPressed: _busy ? null : _check,
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 12)),
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : _segLabel('Check for updates'),
        ),
      ),
      below: (_message == null && update == null)
          ? null
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (_message != null)
                Text(_message!, style: TextStyle(color: p.text, fontSize: 13, fontWeight: FontWeight.w700)),
              if (update != null) ...[
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: () => launchUrl(update.apkUrl, mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.download_rounded),
                  label: _segLabel('Download ${update.version}'),
                ),
                if (update.notes.isNotEmpty) ...[
                  const SizedBox(height: 8),
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
