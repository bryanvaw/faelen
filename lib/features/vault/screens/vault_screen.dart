import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/settings_store.dart';
import '../../../core/theme.dart';
import '../models/vault_item.dart';
import '../state/vault_store.dart';
import '../widgets/copy_button.dart';
import '../widgets/vault_form_sheet.dart';
import 'vault_gate.dart';

const _danger = Color(0xFFD93636);

/// Entry point from the hub: starts the Vault's lock, hides it from screenshots and the recent-apps
/// list while open, and locks it again when you leave.
class VaultFlow extends StatefulWidget {
  const VaultFlow({super.key});

  @override
  State<VaultFlow> createState() => _VaultFlowState();
}

class _VaultFlowState extends State<VaultFlow> {
  late final VaultStore _store = context.read<VaultStore>();

  @override
  void initState() {
    super.initState();
    // Settings > "Block screenshots in the Vault" (on unless the user turned it off).
    _store.bridge.setSecure(context.read<SettingsStore?>()?.blockScreenshots ?? true);
    _store.init();
  }

  @override
  void dispose() {
    _store.bridge.setSecure(false);
    // After this frame: notifying listeners while the tree is being torn down is not allowed.
    WidgetsBinding.instance.addPostFrameCallback((_) => _store.lock());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = context.select<VaultStore, VaultStatus>((s) => s.status);
    return switch (status) {
      VaultStatus.starting => ColoredBox(color: Palette.of(context).bg, child: const Center(child: CircularProgressIndicator())),
      VaultStatus.unlocked => const VaultScreen(),
      VaultStatus.failed => const _StartFailed(),
      _ => const VaultGate(),
    };
  }
}

Future<void> _eraseFlow(BuildContext context, VaultStore store, {required String title, required String body}) async {
  final messenger = ScaffoldMessenger.of(context);
  if (!await confirmEraseVault(context, title: title, body: body)) return;
  try {
    await store.eraseEverything();
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not erase the Vault: $e')));
  }
}

/// The secure store could not be opened (plugin missing after a hot restart, or the Keystore refused).
class _StartFailed extends StatelessWidget {
  const _StartFailed();

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final store = context.read<VaultStore>();
    return ColoredBox(
      color: p.bg,
      child: Scaffold(
        appBar: AppBar(backgroundColor: p.bg, leading: BackButton(color: p.text)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.lock_reset_rounded, size: 44, color: p.text),
              const SizedBox(height: 12),
              Text('The Vault could not start', style: heading(20, color: p.text)),
              const SizedBox(height: 8),
              Text(
                'The secure storage on this device did not answer. If you just updated the app, stop it and run it again '
                '(a hot restart is not enough). Nothing was changed.',
                textAlign: TextAlign.center,
                style: TextStyle(color: p.subText, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              Text(store.startError ?? '', maxLines: 4, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(color: p.subText, fontSize: 11)),
              const SizedBox(height: 18),
              FilledButton(onPressed: store.init, child: const Text('Try again')),
              TextButton(
                onPressed: () => _eraseFlow(
                  context,
                  store,
                  title: 'Erase the Vault?',
                  body: 'Use this only if "Try again" keeps failing, for example after restoring this phone from a backup. '
                      'It deletes everything saved in the Vault and lets you start again with a new PIN.',
                ),
                child: Text('Erase and start over', style: TextStyle(color: p.subText)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  VaultSection _tab = VaultSection.logins;
  String? _open;
  bool _searching = false;
  String _query = '';
  final _search = TextEditingController();
  final _revealed = <String>{};
  final _timers = <String, Timer>{};
  ScaffoldMessengerState? _messenger;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messenger = ScaffoldMessenger.of(context);
  }

  @override
  void dispose() {
    // The "Deleted X / Undo" bar belongs to this unlocked screen; do not leave it up after a lock.
    final m = _messenger;
    WidgetsBinding.instance.addPostFrameCallback((_) => m?.hideCurrentSnackBar());
    for (final t in _timers.values) {
      t.cancel();
    }
    _search.dispose();
    super.dispose();
  }

  void _reveal(String key) {
    setState(() {
      if (_revealed.remove(key)) {
        _timers.remove(key)?.cancel();
      } else {
        _revealed.add(key);
        _timers[key] = Timer(const Duration(seconds: 10), () {
          if (mounted) setState(() => _revealed.remove(key));
        });
      }
    });
  }

  Future<void> _add() async {
    final store = context.read<VaultStore>();
    final item = await showVaultForm(context, section: _tab, newId: store.newId, store: store);
    if (item != null) await store.add(item);
  }

  Future<void> _edit(VaultItem item) async {
    final store = context.read<VaultStore>();
    final saved = await showVaultForm(context, section: item.section, item: item, newId: store.newId, store: store);
    if (saved != null) await store.update(saved);
  }

  Future<void> _delete(VaultItem item) async {
    final store = context.read<VaultStore>();
    final messenger = ScaffoldMessenger.of(context);
    await store.remove(item.id);
    if (!mounted) return; // the Vault locked meanwhile
    setState(() => _open = null);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Deleted ${item.title}'),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(label: 'Undo', onPressed: () => store.add(item)),
      ));
  }

  Future<void> _call(VaultItem item) async {
    final digits = (item.field('Number')?.value ?? '').replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.isEmpty) return;
    try {
      await launchUrl(Uri(scheme: 'tel', path: digits));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the dialler')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final store = context.watch<VaultStore>();
    final q = _query.trim().toLowerCase();
    final items = [
      for (final i in store.section(_tab))
        if (q.isEmpty || i.title.toLowerCase().contains(q)) i,
    ];
    final favs = _searching ? <VaultItem>[] : store.favorites;
    return ColoredBox(
      color: p.bg,
      child: Scaffold(
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: Stack(children: [
                Column(children: [
                  _Header(
                    accent: _tab.color,
                    searching: _searching,
                    controller: _search,
                    onSearch: () => setState(() {
                      _searching = !_searching;
                      if (!_searching) {
                        _query = '';
                        _search.clear();
                      }
                    }),
                    onQuery: (v) => setState(() => _query = v),
                    onLock: store.lock,
                  ),
                  if (store.loadError != null)
                    _Notice(
                      text: '${store.loadError}. Nothing will be saved until this is fixed.',
                      color: _danger,
                      actionLabel: 'Erase and start over',
                      onAction: () => _eraseFlow(
                        context,
                        store,
                        title: 'Erase the Vault?',
                        body: 'The saved data cannot be read on this phone, so it cannot be recovered. '
                            'Erasing lets you start again with a new PIN.',
                      ),
                    ),
                  if (store.saveError != null) _Notice(text: store.saveError!, color: _danger),
                  if (favs.isNotEmpty) _Favorites(items: favs, store: store),
                  Expanded(
                    child: items.isEmpty
                        ? _Empty(section: _tab, searching: q.isNotEmpty, onAdd: _add)
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                            itemCount: items.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 12),
                            itemBuilder: (_, n) {
                              final item = items[n];
                              return _Row(
                                key: ValueKey(item.id),
                                item: item,
                                open: _open == item.id,
                                revealed: _revealed,
                                onToggle: () => setState(() => _open = _open == item.id ? null : item.id),
                                onReveal: _reveal,
                                onCopy: store.copy,
                                onCall: () => _call(item),
                                onPin: () => store.toggleFavorite(item),
                                onEdit: () => _edit(item),
                                onDelete: () => _delete(item),
                              );
                            },
                          ),
                  ),
                  _BottomBar(
                    current: _tab,
                    onSelect: (s) => setState(() {
                      _tab = s;
                      _open = null;
                      _revealed.clear();
                    }),
                  ),
                ]),
                Positioned(right: 16, bottom: 88, child: _AddButton(color: _tab.color, onTap: _add)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.accent, required this.searching, required this.controller, required this.onSearch, required this.onQuery, required this.onLock});
  final Color accent;
  final bool searching;
  final TextEditingController controller;
  final VoidCallback onSearch, onLock;
  final ValueChanged<String> onQuery;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 4),
      child: SizedBox(
        height: 52,
        child: Row(children: [
          IconButton(tooltip: 'Back', onPressed: () => Navigator.maybePop(context), icon: Icon(Icons.arrow_back_rounded, color: p.text)),
          if (searching)
            Expanded(
              child: TextField(
                controller: controller,
                autofocus: true,
                onChanged: onQuery,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(hintText: 'Search titles', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
              ),
            )
          else ...[
            Container(
              width: 34,
              height: 34,
              padding: const EdgeInsets.all(3),
              decoration: brutal(p, color: accent, radius: 10, shadow: 2),
              child: Image.asset('assets/cats/passwords.png', fit: BoxFit.contain, excludeFromSemantics: true),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text('Vault', style: heading(22, color: p.text))),
          ],
          IconButton(
            tooltip: searching ? 'Close search' : 'Search',
            onPressed: onSearch,
            icon: Icon(searching ? Icons.close_rounded : Icons.search_rounded, color: p.text),
          ),
          if (!searching)
            Semantics(
              button: true,
              label: 'Lock the Vault now',
              child: ExcludeSemantics(
                child: GestureDetector(
                  onTap: onLock,
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: brutal(p, radius: 12, shadow: 2),
                    child: Row(children: [
                      Icon(Icons.lock_rounded, size: 17, color: p.text),
                      const SizedBox(width: 6),
                      Text('Lock', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: p.text)),
                    ]),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.color, this.actionLabel, this.onAction});
  final String text;
  final Color color;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12), border: Border.all(color: color, width: 1.5)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(text, style: TextStyle(color: Palette.of(context).text, fontSize: 13, fontWeight: FontWeight.w600)),
          if (onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 40), alignment: Alignment.centerLeft),
              child: Text(actionLabel ?? '', style: TextStyle(color: color, fontWeight: FontWeight.w800)),
            ),
        ]),
      );
}

/// One-tap chips for the entries you paste most. A tap copies the entry's main field.
class _Favorites extends StatelessWidget {
  const _Favorites({required this.items, required this.store});
  final List<VaultItem> items;
  final VaultStore store;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 62,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, n) => _FavChip(item: items[n], store: store),
      ),
    );
  }
}

class _FavChip extends StatefulWidget {
  const _FavChip({required this.item, required this.store});
  final VaultItem item;
  final VaultStore store;

  @override
  State<_FavChip> createState() => _FavChipState();
}

class _FavChipState extends State<_FavChip> {
  Timer? _reset;
  bool _copied = false;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  Future<void> _tap() async {
    final f = widget.item.mainField;
    if (f == null) return;
    await widget.store.copy(f);
    if (!mounted) return;
    setState(() => _copied = true);
    _reset?.cancel();
    _reset = Timer(f.secret ? clipboardClear : const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final item = widget.item;
    final f = item.mainField;
    final what = (f?.label ?? '').toLowerCase();
    return Semantics(
      button: true,
      liveRegion: true,
      label: _copied ? 'Copied $what for ${item.title}' : 'Copy $what for ${item.title}',
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: _tap,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 200),
            padding: const EdgeInsets.fromLTRB(6, 0, 14, 0),
            decoration: brutal(p, color: _copied ? item.section.color : p.card, radius: 14, shadow: 3),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _Tile(section: item.section, size: 34, title: item.title, icon: true),
              const SizedBox(width: 8),
              Flexible(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: _copied ? onTile : p.text)),
                  Text(
                    _copied ? (f?.secret == true ? 'copied · clears in 30s' : 'copied') : what,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _copied ? onTile : p.subText),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.section, required this.size, required this.title, this.icon = false});
  final VaultSection section;
  final double size;
  final String title;

  /// Show the section icon instead of the title's first letter.
  final bool icon;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: section.color, borderRadius: BorderRadius.circular(size * 0.28), border: Border.all(color: p.ink, width: 2)),
      child: icon || title.isEmpty
          ? Icon(section.icon, size: size * 0.5, color: onTile)
          : Text(title.characters.first.toUpperCase(), style: heading(size * 0.42, color: onTile)),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.item,
    required this.open,
    required this.revealed,
    required this.onToggle,
    required this.onReveal,
    required this.onCopy,
    required this.onCall,
    required this.onPin,
    required this.onEdit,
    required this.onDelete,
  });

  final VaultItem item;
  final bool open;
  final Set<String> revealed;
  final VoidCallback onToggle, onCall, onPin, onEdit, onDelete;
  final void Function(String key) onReveal;
  final Future<void> Function(VaultField f) onCopy;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final main = item.mainField;
    final chip = _expiryChip(item);
    return Container(
      decoration: brutal(p, radius: 16, shadow: 3),
      child: Column(children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Row(children: [
            // Only this left part expands the row, so the buttons on the right keep their own
            // spoken labels (a merged label would hide them from a screen reader).
            Expanded(
              child: Semantics(
                button: true,
                expanded: open,
                label: '${item.title}. ${item.section == VaultSection.ids ? '' : item.subtitle}',
                child: ExcludeSemantics(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: onToggle,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 64),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
                        child: Row(children: [
                          _Tile(section: item.section, size: 44, title: item.title, icon: item.section == VaultSection.ids),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                              Row(children: [
                                Flexible(child: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, color: p.text))),
                                if (item.favorite) Padding(padding: const EdgeInsets.only(left: 6), child: Icon(Icons.star_rounded, size: 16, color: p.text)),
                                ?chip,
                              ]),
                              if (item.subtitle.isNotEmpty)
                                Text(item.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: p.subText, fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()])),
                            ]),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (item.section == VaultSection.numbers) ...[
              _IconSquare(icon: Icons.call_rounded, label: 'Call ${item.title}', onTap: onCall),
              const SizedBox(width: 8),
            ],
            if (main != null)
              CopyButton(
                key: ValueKey('main-${item.id}'),
                color: item.section.color,
                label: '${main.label.toLowerCase()} for ${item.title}',
                secret: main.secret,
                onCopy: () => onCopy(main),
              ),
            const SizedBox(width: 8),
          ]),
        ),
        if (open) _Detail(item: item, revealed: revealed, onReveal: onReveal, onCopy: onCopy, onPin: onPin, onEdit: onEdit, onDelete: onDelete),
      ]),
    );
  }

  Widget? _expiryChip(VaultItem item) {
    final d = item.daysLeft(DateTime.now());
    if (d == null || d > 60) return null;
    final expired = d < 0;
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(color: expired ? _danger : const Color(0xFFFFD166), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF111111), width: 1.5)),
      child: Text(expired ? 'Expired' : (d == 0 ? 'Today' : '${d}d left'), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: expired ? Colors.white : onTile)),
    );
  }
}

class _IconSquare extends StatelessWidget {
  const _IconSquare({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      button: true,
      label: label,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.ink, width: 2)),
            child: Icon(icon, size: 22, color: p.text),
          ),
        ),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.item, required this.revealed, required this.onReveal, required this.onCopy, required this.onPin, required this.onEdit, required this.onDelete});
  final VaultItem item;
  final Set<String> revealed;
  final void Function(String key) onReveal;
  final Future<void> Function(VaultField f) onCopy;
  final VoidCallback onPin, onEdit, onDelete;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final rows = <Widget>[
      for (final f in item.fields)
        _FieldLine(
          item: item,
          field: f,
          shown: !f.secret || revealed.contains('${item.id}|${f.label}'),
          onReveal: () => onReveal('${item.id}|${f.label}'),
          onCopy: () => onCopy(f),
        ),
      if (item.expiry != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Expires', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: p.subText)),
            Text(_date(item.expiry!), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.text)),
          ]),
        ),
    ];
    return Container(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: p.outline, width: 2))),
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
      child: Column(children: [
        ...rows,
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: _Action(icon: item.favorite ? Icons.star_rounded : Icons.star_outline_rounded, label: item.favorite ? 'Unpin' : 'Pin to top', onTap: onPin)),
          const SizedBox(width: 8),
          Expanded(child: _Action(icon: Icons.edit_rounded, label: 'Edit', onTap: onEdit)),
          const SizedBox(width: 8),
          _Action(icon: Icons.delete_outline_rounded, label: '', semantics: 'Delete ${item.title}', onTap: onDelete, color: _danger, width: 56),
        ]),
      ]),
    );
  }

  static String _date(DateTime d) {
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }
}

class _FieldLine extends StatelessWidget {
  const _FieldLine({required this.item, required this.field, required this.shown, required this.onReveal, required this.onCopy});
  final VaultItem item;
  final VaultField field;
  final bool shown;
  final VoidCallback onReveal;
  final Future<void> Function() onCopy;

  static IconData _icon(String label) => switch (label) {
        'Username' => Icons.person_outline_rounded,
        'Password' => Icons.key_rounded,
        'Link' => Icons.link_rounded,
        'Number' => Icons.call_rounded,
        'ID number' => Icons.tag_rounded,
        'Notes' => Icons.notes_rounded,
        _ => Icons.label_outline_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final hidden = field.secret && !shown;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 60),
      child: Row(children: [
        const SizedBox(width: 6),
        Icon(_icon(field.label), size: 20, color: p.subText),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(field.label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: p.subText)),
              const SizedBox(height: 2),
              Text(
                hidden ? maskAll(field.value) : field.value,
                style: TextStyle(
                  fontSize: hidden ? 20 : 16,
                  height: hidden ? 1.0 : 1.25,
                  fontWeight: FontWeight.w800,
                  color: p.text,
                  letterSpacing: hidden ? 2.5 : 0,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ]),
          ),
        ),
        if (field.secret)
          Semantics(
            button: true,
            label: '${shown ? 'Hide' : 'Show'} ${field.label.toLowerCase()}',
            child: ExcludeSemantics(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onReveal,
                child: SizedBox(width: 44, height: 44, child: Icon(shown ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 22, color: p.text)),
              ),
            ),
          ),
        CopyButton(label: '${field.label.toLowerCase()} for ${item.title}', color: item.section.color, secret: field.secret, big: false, onCopy: onCopy),
      ]),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap, this.color, this.width, this.semantics});
  final IconData icon;
  final String label;
  final String? semantics;
  final VoidCallback onTap;
  final Color? color;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final c = color ?? p.text;
    return Semantics(
      button: true,
      label: semantics ?? label,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            width: width,
            height: 46,
            decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: color ?? p.ink, width: 2)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 19, color: c),
              if (label.isNotEmpty) ...[const SizedBox(width: 6), Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: c)))],
            ]),
          ),
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.color, required this.onTap});
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      button: true,
      label: 'Add',
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 56,
            height: 56,
            decoration: brutal(p, color: color, radius: 16, shadow: 4),
            child: const Icon(Icons.add_rounded, size: 30, color: onTile),
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.current, required this.onSelect});
  final VaultSection current;
  final ValueChanged<VaultSection> onSelect;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      height: 72,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      decoration: BoxDecoration(color: p.card, border: Border(top: BorderSide(color: p.ink, width: 2))),
      child: Row(children: [
        for (final s in VaultSection.values)
          Expanded(
            child: Semantics(
              button: true,
              selected: s == current,
              label: s.label,
              child: ExcludeSemantics(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelect(s),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Container(
                      width: 52,
                      height: 30,
                      decoration: BoxDecoration(
                        color: s == current ? s.color : Colors.transparent,
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: s == current ? p.ink : Colors.transparent, width: 2),
                      ),
                      child: Icon(s.icon, size: 20, color: s == current ? onTile : p.subText),
                    ),
                    const SizedBox(height: 2),
                    Text(s.label, style: TextStyle(fontSize: 12, fontWeight: s == current ? FontWeight.w800 : FontWeight.w700, color: s == current ? p.text : p.subText)),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.section, required this.searching, required this.onAdd});
  final VaultSection section;
  final bool searching;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final what = switch (section) { VaultSection.logins => 'login', VaultSection.numbers => 'number', VaultSection.ids => 'ID' };
    final title = switch (section) { VaultSection.logins => 'No logins yet', VaultSection.numbers => 'No numbers yet', VaultSection.ids => 'No IDs yet' };
    final addLabel = switch (section) { VaultSection.logins => 'Add a login', VaultSection.numbers => 'Add a number', VaultSection.ids => 'Add an ID' };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (!searching)
            Container(
              width: 88,
              height: 88,
              padding: const EdgeInsets.all(8),
              decoration: brutal(p, color: section.color, radius: 24, shadow: 3),
              child: Image.asset('assets/cats/passwords.png', fit: BoxFit.contain, excludeFromSemantics: true),
            ),
          const SizedBox(height: 16),
          Text(searching ? 'No match' : title, style: heading(20, color: p.text)),
          const SizedBox(height: 4),
          Text(
            searching ? 'Search looks at titles only.' : 'Saved $what details are encrypted on this phone.',
            textAlign: TextAlign.center,
            style: TextStyle(color: p.subText, fontWeight: FontWeight.w600),
          ),
          if (!searching) ...[const SizedBox(height: 18), FilledButton(onPressed: onAdd, style: FilledButton.styleFrom(backgroundColor: section.color, foregroundColor: onTile), child: Text(addLabel))],
        ]),
      ),
    );
  }
}
