import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/settings_store.dart';
import '../../core/theme.dart';
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
                    segments: const [
                      ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_rounded), label: Text('System')),
                      ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_rounded), label: Text('Light')),
                      ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_rounded), label: Text('Dark')),
                    ],
                    selected: {settings.themeMode},
                    onSelectionChanged: (s) => settings.setThemeMode(s.first),
                  ),
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
