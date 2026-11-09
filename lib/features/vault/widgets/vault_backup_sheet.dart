import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme.dart';
import '../services/vault_backup.dart';
import '../state/vault_store.dart';

/// Save the Vault to a passphrase-protected file, or load one back in.
Future<void> showVaultBackup(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  builder: (_) => ChangeNotifierProvider<VaultStore>.value(
    value: context.read<VaultStore>(),
    child: const _BackupSheet(),
  ),
);

class _BackupSheet extends StatelessWidget {
  const _BackupSheet();

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Vault backup', style: heading(20, color: p.text)),
            const SizedBox(height: 6),
            Text(
              'The file is locked with a passphrase you choose and opens on any phone with Faelen. '
              'Faelen cannot recover a forgotten passphrase.',
              style: TextStyle(color: p.subText, fontSize: 13.5, height: 1.35),
            ),
            const SizedBox(height: 14),
            _Action(
              icon: Icons.upload_rounded,
              title: 'Save a backup',
              subtitle: 'Choose a passphrase, then share or store the file.',
              onTap: () => _save(context),
            ),
            _Action(
              icon: Icons.download_rounded,
              title: 'Load a backup',
              subtitle: 'Pick a .fvault file and enter its passphrase.',
              onTap: () => _load(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: p.text),
      title: Text(title, style: TextStyle(color: p.text, fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle, style: TextStyle(color: p.subText)),
      onTap: onTap,
    );
  }
}

void _toast(BuildContext c, String m) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

Future<void> _save(BuildContext context) async {
  final store = context.read<VaultStore>();
  final text = store.backupText();
  if (text == null) {
    _toast(context, 'The Vault could not be read, so there is nothing safe to back up.');
    return;
  }
  final pass = await _askPassphrase(context, confirm: true);
  if (pass == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  Navigator.pop(context);
  messenger.showSnackBar(const SnackBar(content: Text('Locking the backup...')));
  try {
    final now = DateTime.now();
    final file = await VaultBackup().encrypt(text, pass, now: now);
    final name = VaultBackup.fileName(now);
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(utf8.encode(file), mimeType: 'application/octet-stream', name: name)],
      fileNameOverrides: [name],
      subject: 'Faelen Vault backup',
    ));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not save the backup: $e')));
  }
}

Future<void> _load(BuildContext context) async {
  final store = context.read<VaultStore>();
  try {
    final files = await FilePicker.pickFiles(type: FileType.any);
    if (files.isEmpty || !context.mounted) return;
    final file = utf8.decode(await files.first.readAsBytes());
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final pass = await _askPassphrase(context, confirm: false);
    if (pass == null || !context.mounted) return;
    final text = await VaultBackup().decrypt(file, pass);
    if (!context.mounted) return;
    final replace = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Load backup'),
        content: const Text(
          'Merge adds the backup to your Vault (the newer copy of any duplicate wins). '
          'Replace deletes what is in the Vault now first.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Replace')),
          FilledButton(onPressed: () => Navigator.pop(d, false), child: const Text('Merge')),
        ],
      ),
    );
    if (replace == null) return;
    final n = await store.restoreBackup(text, replace: replace);
    if (context.mounted) Navigator.pop(context);
    messenger.showSnackBar(SnackBar(content: Text('Loaded $n ${n == 1 ? 'entry' : 'entries'}')));
  } on FormatException catch (e) {
    if (context.mounted) _toast(context, e.message);
  } catch (e) {
    if (context.mounted) _toast(context, 'Could not load the backup: $e');
  }
}

Future<String?> _askPassphrase(BuildContext context, {required bool confirm}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _PassphraseDialog(confirm: confirm),
  );
}

class _PassphraseDialog extends StatefulWidget {
  const _PassphraseDialog({required this.confirm});
  final bool confirm;

  @override
  State<_PassphraseDialog> createState() => _PassphraseDialogState();
}

class _PassphraseDialogState extends State<_PassphraseDialog> {
  final _a = TextEditingController();
  final _b = TextEditingController();
  String? _error;
  bool _show = false;

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  void _submit() {
    if (widget.confirm) {
      if (_a.text.length < VaultBackup.minPassphrase) {
        setState(() => _error = 'Use at least ${VaultBackup.minPassphrase} characters.');
        return;
      }
      if (_a.text != _b.text) {
        setState(() => _error = 'The two passphrases do not match.');
        return;
      }
    } else if (_a.text.isEmpty) {
      setState(() => _error = 'Enter the passphrase.');
      return;
    }
    Navigator.pop(context, _a.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.confirm ? 'Choose a passphrase' : 'Backup passphrase'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _a,
            obscureText: !_show,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'Passphrase',
              suffixIcon: IconButton(
                tooltip: _show ? 'Hide' : 'Show',
                icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                onPressed: () => setState(() => _show = !_show),
              ),
            ),
          ),
          if (widget.confirm)
            TextField(
              controller: _b,
              obscureText: !_show,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(labelText: 'Repeat passphrase'),
              onSubmitted: (_) => _submit(),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_error!, style: const TextStyle(color: Color(0xFFD93636))),
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: Text(widget.confirm ? 'Save' : 'Open')),
      ],
    );
  }
}
