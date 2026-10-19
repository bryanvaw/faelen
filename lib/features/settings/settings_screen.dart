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
              child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
                _Section(
                  title: 'Appearance',
                  child: SegmentedButton<ThemeMode>(
                    showSelectedIcon: false,
                    expandedInsets: EdgeInsets.zero,
                    segments: [
                      ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_rounded), label: _segLabel('System')),
                      ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_rounded), label: _segLabel('Light')),
                      ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_rounded), label: _segLabel('Dark')),
                    ],
                    selected: {settings.themeMode},
                    onSelectionChanged: (s) => settings.setThemeMode(s.first),
                  ),
                ),
                _Section(
                  title: 'Links',
                  subtitle: 'When an entry has a link with a chapter or episode number in it '
                      '(like /chapter-45), Faelen can use that as your progress.',
                  child: SegmentedButton<bool>(
                    showSelectedIcon: false,
                    expandedInsets: EdgeInsets.zero,
                    segments: [
                      ButtonSegment(value: false, icon: Icon(Icons.help_outline_rounded), label: _segLabel('Ask first')),
                      ButtonSegment(value: true, icon: Icon(Icons.bolt_rounded), label: _segLabel('Automatic')),
                    ],
                    selected: {settings.autoUrlProgress},
                    onSelectionChanged: (s) => settings.setAutoUrlProgress(s.first),
                  ),
                ),
                if (ReleaseReminders.supported)
                  _Section(
                    title: 'Release reminders',
                    subtitle: 'A notification on the day a show you are following gets a new chapter or episode. '
                        'Set its release days when editing it; the time is 9:00 unless you pick another there.',
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Remind me on release day'),
                      value: settings.releaseReminders,
                      onChanged: (on) async {
                        if (on && !await context.read<ReleaseReminders>().requestPermission()) {
                          if (context.mounted) {
                            _toast(context, 'Allow notifications for Faelen in system settings to get reminders');
                          }
                          return;
                        }
                        settings.setReleaseReminders(on);
                      },
                    ),
                  ),
                const _Section(
                  title: 'App updates',
                  subtitle: 'New versions are published on GitHub. Faelen also checks quietly once a day.',
                  child: _UpdateCheck(),
                ),
                _Section(
                  title: 'Backup',
                  subtitle: 'Your data only lives on this device. Export a backup file to keep it safe '
                      'or move it to another phone.',
                  child: Row(children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _export(context),
                        icon: const Icon(Icons.upload_rounded),
                        label: const Text('Export'),
                      ),
                    ),
                    const SizedBox(width: 12),
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
            ),
          ),
        ),
      ),
    );
  }
}

/// Segment label that shrinks to fit instead of wrapping mid-word on narrow screens or large fonts.
Widget _segLabel(String text) => FittedBox(fit: BoxFit.scaleDown, child: Text(text, maxLines: 1, softWrap: false));

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
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Installed version ${_version ?? '...'}', style: TextStyle(color: p.text, fontWeight: FontWeight.w600)),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: _busy ? null : _check,
        icon: _busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.system_update_rounded),
        label: _segLabel('Check for updates'),
      ),
      if (update != null) ...[
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: () => launchUrl(update.apkUrl, mode: LaunchMode.externalApplication),
          icon: const Icon(Icons.download_rounded),
          label: _segLabel('Download ${update.version}'),
        ),
      ],
      if (_message != null) ...[
        const SizedBox(height: 10),
        Text(_message!, style: TextStyle(color: p.text, fontSize: 13, fontWeight: FontWeight.w600)),
      ],
      if (update != null) ...[
        if (update.notes.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(update.notes, maxLines: 6, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.subText, fontSize: 13, height: 1.35)),
        ],
        const SizedBox(height: 6),
        Text('After it downloads, open the file and tap Install. Your entries are kept.',
            style: TextStyle(color: p.subText, fontSize: 12.5, height: 1.35)),
      ],
    ]);
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.subtitle});
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: brutal(p, radius: 18, shadow: 3),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: heading(17, weight: FontWeight.w700, color: p.text)),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: TextStyle(color: p.subText, fontSize: 13, height: 1.35)),
          ],
          const SizedBox(height: 14),
          child,
        ]),
      ),
    );
  }
}
