import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/settings_store.dart';
import '../../../core/theme.dart';
import '../../budget/widgets/budget_widgets.dart' show Tone, toneBox;
import '../models/vault_item.dart';
import '../state/vault_store.dart';
import '../widgets/copy_button.dart';
import '../widgets/vault_form_sheet.dart';
import '../widgets/vault_backup_sheet.dart';
import '../widgets/vault_palette.dart';
import 'vault_gate.dart';

const _danger = Color(0xFFD93636);

/// One colour family per section: everything on screen takes the colour of the section you are in.
Tone _toneOf(BuildContext context, VaultSection s) => vaultTone(context, s);

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
    _store.bridge.setSecure(
      context.read<SettingsStore?>()?.blockScreenshots ?? true,
    );
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
      VaultStatus.starting => ColoredBox(
        color: Palette.of(context).bg,
        child: const Center(child: CircularProgressIndicator()),
      ),
      VaultStatus.unlocked => const VaultScreen(),
      VaultStatus.failed => const _StartFailed(),
      _ => const VaultGate(),
    };
  }
}

Future<void> _eraseFlow(
  BuildContext context,
  VaultStore store, {
  required String title,
  required String body,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  if (!await confirmEraseVault(context, title: title, body: body)) return;
  try {
    await store.eraseEverything();
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('Could not erase the Vault: $e')),
    );
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
        appBar: AppBar(
          backgroundColor: p.bg,
          leading: BackButton(color: p.text),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_reset_rounded, size: 44, color: p.text),
                const SizedBox(height: 12),
                Text(
                  'The Vault could not start',
                  style: heading(20, color: p.text),
                ),
                const SizedBox(height: 8),
                Text(
                  'The secure storage on this device did not answer. If you just updated the app, stop it and run it again '
                  '(a hot restart is not enough). Nothing was changed.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: p.subText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  store.startError ?? '',
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.subText, fontSize: 11),
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: store.init,
                  child: const Text('Try again'),
                ),
                TextButton(
                  onPressed: () => _eraseFlow(
                    context,
                    store,
                    title: 'Erase the Vault?',
                    body:
                        'Use this only if "Try again" keeps failing, for example after restoring this phone from a backup. '
                        'It deletes everything saved in the Vault and lets you start again with a new PIN.',
                  ),
                  child: Text(
                    'Erase and start over',
                    style: TextStyle(color: p.subText),
                  ),
                ),
              ],
            ),
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
  /// null = everything; otherwise only that kind is listed. It is a filter, not a place.
  VaultSection? _tab;
  String? _open;
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
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => m?.hideCurrentSnackBar(),
    );
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
    final item = await showVaultForm(
      context,
      section: _tab ?? VaultSection.logins,
      newId: store.newId,
      store: store,
    );
    if (item != null) await store.add(item);
  }

  Future<void> _edit(VaultItem item) async {
    final store = context.read<VaultStore>();
    final saved = await showVaultForm(
      context,
      section: item.section,
      item: item,
      newId: store.newId,
      store: store,
    );
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
      ..showSnackBar(
        SnackBar(
          content: Text('Deleted ${item.title}'),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => store.add(item),
          ),
        ),
      );
  }

  Future<void> _call(VaultItem item) async {
    final digits = (item.field('Number')?.value ?? '').replaceAll(
      RegExp(r'[^0-9+]'),
      '',
    );
    if (digits.isEmpty) return;
    try {
      await launchUrl(Uri(scheme: 'tel', path: digits));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the dialler')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final store = context.watch<VaultStore>();
    final q = _query.trim().toLowerCase();
    final all = _tab == null
        ? ([...store.items]..sort(
            (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
          ))
        : store.section(_tab!);
    final items = [
      for (final i in all)
        if (q.isEmpty || i.title.toLowerCase().contains(q)) i,
    ];
    final counts = {
      for (final k in VaultSection.values)
        k: store.items.where((i) => i.section == k).length,
    };
    // Pinned entries are a group at the top of the list (with a visible copy button); the rest follow.
    // While searching there is one flat "Results" list.
    final pinned = q.isEmpty
        ? [
            for (final i in items)
              if (i.favorite) i,
          ]
        : <VaultItem>[];
    final rest = q.isEmpty
        ? [
            for (final i in items)
              if (!i.favorite) i,
          ]
        : items;
    final tone = _toneOf(context, _tab ?? VaultSection.logins);
    final heading0 = q.isNotEmpty
        ? 'Results'
        : (_tab == null ? 'All items' : _tab!.label);
    return ColoredBox(
      color: p.bg,
      child: Scaffold(
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        // Hidden while the keyboard is up (typing a search), so it never sits on top of the field.
        floatingActionButton: MediaQuery.viewInsetsOf(context).bottom > 0
            ? null
            : _AddFab(tone: tone, onTap: _add),
        body: SafeArea(
          bottom: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: Column(
                children: [
                  _Header(onLock: store.lock),
                  _SearchRow(
                    tone: tone,
                    controller: _search,
                    hint: _tab == null
                        ? 'Search your vault'
                        : 'Search ${_tab!.label.toLowerCase()}',
                    onQuery: (v) => setState(() => _query = v),
                    onClear: () => setState(() {
                      _query = '';
                      _search.clear();
                    }),
                  ),
                  if (store.loadError != null)
                    _Notice(
                      text:
                          '${store.loadError}. Nothing will be saved until this is fixed.',
                      color: _danger,
                      actionLabel: 'Erase and start over',
                      onAction: () => _eraseFlow(
                        context,
                        store,
                        title: 'Erase the Vault?',
                        body:
                            'The saved data cannot be read on this phone, so it cannot be recovered. '
                            'Erasing lets you start again with a new PIN.',
                      ),
                    ),
                  if (store.saveError != null)
                    _Notice(text: store.saveError!, color: _danger),
                  Expanded(
                    child: CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(
                          child: _FilterRow(
                            current: _tab,
                            counts: counts,
                            onSelect: (s) => setState(() {
                              _tab = s;
                              _open = null;
                              _revealed.clear();
                            }),
                          ),
                        ),
                        if (items.isEmpty)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: _Empty(
                              section: _tab,
                              tone: tone,
                              searching: q.isNotEmpty,
                              onAdd: _add,
                            ),
                          )
                        else ...[
                          if (pinned.isNotEmpty) ...[
                            const SliverToBoxAdapter(
                              child: _SectionLabel('Pinned'),
                            ),
                            _rows(
                              pinned,
                              store,
                              quick: true,
                              last: rest.isEmpty,
                            ),
                          ],
                          if (rest.isNotEmpty) ...[
                            SliverToBoxAdapter(child: _SectionLabel(heading0)),
                            _rows(rest, store, quick: false, last: true),
                          ],
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _rows(
    List<VaultItem> list,
    VaultStore store, {
    required bool quick,
    required bool last,
  }) {
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, last ? 104 : 6),
      sliver: SliverList.separated(
        itemCount: list.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, n) {
          final item = list[n];
          return _Row(
            key: ValueKey(item.id),
            item: item,
            open: _open == item.id,
            quickCopy: quick,
            revealed: _revealed,
            onToggle: () =>
                setState(() => _open = _open == item.id ? null : item.id),
            onReveal: _reveal,
            onCopy: store.copy,
            onCall: () => _call(item),
            onPin: () => store.toggleFavorite(item),
            onEdit: () => _edit(item),
            onDelete: () => _delete(item),
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onLock});
  final VoidCallback onLock;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 50),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Back',
              onPressed: () => Navigator.maybePop(context),
              icon: Icon(Icons.arrow_back_rounded, color: p.text),
            ),
            Image.asset(
              'assets/cats/passwords.png',
              width: 40,
              height: 40,
              excludeFromSemantics: true,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Vault', style: heading(21, color: p.text, height: 1.1)),
                  Text(
                    'Encrypted on this phone',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: p.subText,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Vault colour',
              onPressed: () => showVaultPalette(context),
              icon: Icon(Icons.palette_outlined, color: p.text),
            ),
            IconButton(
              tooltip: 'Vault backup',
              onPressed: () => showVaultBackup(context),
              icon: Icon(Icons.save_alt_rounded, color: p.text),
            ),
            IconButton(
              tooltip: 'Lock the Vault now',
              onPressed: onLock,
              icon: Icon(Icons.lock_rounded, color: p.text),
            ),
          ],
        ),
      ),
    );
  }
}

/// Search is always there (no button to open it): a soft fill with no outline, full width.
class _SearchRow extends StatelessWidget {
  const _SearchRow({
    required this.tone,
    required this.controller,
    required this.hint,
    required this.onQuery,
    required this.onClear,
  });
  final Tone tone;
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onQuery;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final fill = Color.alphaBlend(p.ink.withValues(alpha: 0.06), p.bg);
    const none = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(14)),
      borderSide: BorderSide.none,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 48,
              child: TextField(
                controller: controller,
                onChanged: onQuery,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: hint,
                  isDense: true,
                  filled: true,
                  fillColor: fill,
                  border: none,
                  enabledBorder: none,
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: tone.main, width: 1.8),
                  ),
                  prefixIcon: Icon(Icons.search_rounded, color: p.subText),
                  suffixIcon: controller.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: onClear,
                          icon: Icon(Icons.close_rounded, color: p.text),
                        ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.text,
    required this.color,
    this.actionLabel,
    this.onAction,
  });
  final String text;
  final Color color;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.fromLTRB(16, 4, 16, 6),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color, width: 1.5),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          style: TextStyle(
            color: Palette.of(context).text,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (onAction != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 40),
              alignment: Alignment.centerLeft,
            ),
            child: Text(
              actionLabel ?? '',
              style: TextStyle(color: color, fontWeight: FontWeight.w800),
            ),
          ),
      ],
    ),
  );
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.section,
    required this.size,
    required this.title,
    this.icon = false,
    this.filled = false,
  });
  final VaultSection section;

  /// Solid Vault colour instead of the quiet tint (the open row).
  final bool filled;
  final double size;
  final String title;

  /// Show the section icon instead of the title's first letter.
  final bool icon;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final tone = _toneOf(context, section);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled
            ? tone.main
            : Color.alphaBlend(p.ink.withValues(alpha: 0.09), p.card),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: icon || title.isEmpty
          ? Icon(
              section.icon,
              size: size * 0.5,
              color: filled ? tone.on : p.text,
            )
          : Text(
              title.characters.first.toUpperCase(),
              style: heading(size * 0.42, color: filled ? tone.on : p.text),
            ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.item,
    required this.open,
    this.quickCopy = false,
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

  /// Pinned entries show a copy button on the closed row (the one-tap path).
  final bool quickCopy;
  final Set<String> revealed;
  final VoidCallback onToggle, onCall, onPin, onEdit, onDelete;
  final void Function(String key) onReveal;
  final Future<void> Function(VaultField f) onCopy;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final chip = _expiryChip(item);
    final main = item.mainField;
    final tone = _toneOf(context, item.section);
    // Neutral surface, no outline, no tint: colour is kept for the action and the open state.
    final fill = Color.alphaBlend(
      p.ink.withValues(alpha: open ? 0.085 : 0.05),
      p.card,
    );
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Row(
              children: [
                // Only this left part toggles the row, so the buttons on the right keep their own
                // spoken labels (a merged label would hide them from a screen reader).
                Expanded(
                  child: Semantics(
                    button: true,
                    expanded: open,
                    label:
                        '${item.title}. ${item.section == VaultSection.ids ? '' : item.subtitle}',
                    child: ExcludeSemantics(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: onToggle,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
                          child: Row(
                            children: [
                              _Tile(
                                section: item.section,
                                size: 38,
                                title: item.title,
                                icon: item.section != VaultSection.logins,
                                filled: open,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            item.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 15,
                                              height: 1.2,
                                              color: p.text,
                                            ),
                                          ),
                                        ),
                                        if (item.favorite)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              left: 6,
                                            ),
                                            child: Icon(
                                              Icons.star_rounded,
                                              size: 15,
                                              color: p.subText,
                                            ),
                                          ),
                                        ?chip,
                                      ],
                                    ),
                                    if (item.subtitle.isNotEmpty)
                                      Text(
                                        item.subtitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          height: 1.2,
                                          color: p.subText,
                                          fontWeight: FontWeight.w600,
                                          fontFeatures: const [
                                            FontFeature.tabularFigures(),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (quickCopy && main != null)
                  CopyButton(
                    key: ValueKey('main-${item.id}'),
                    color: tone.main,
                    onColor: tone.on,
                    label: '${main.label.toLowerCase()} for ${item.title}',
                    secret: main.secret,
                    big: false,
                    compact: true,
                    flat: true,
                    onCopy: () => onCopy(main),
                  ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onToggle,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 12, 14, 12),
                    child: ExcludeSemantics(
                      child: AnimatedRotation(
                        turns: open ? 0.5 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: Icon(
                          Icons.expand_more_rounded,
                          size: 22,
                          color: p.subText,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: open
                ? _Detail(
                    item: item,
                    tone: tone,
                    revealed: revealed,
                    onReveal: onReveal,
                    onCopy: onCopy,
                    onCall: onCall,
                    onPin: onPin,
                    onEdit: onEdit,
                    onDelete: onDelete,
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget? _expiryChip(VaultItem item) {
    final d = item.daysLeft(DateTime.now());
    if (d == null || d > 60) return null;
    final expired = d < 0;
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: expired ? _danger : const Color(0xFFFFD166),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        expired ? 'Expired' : (d == 0 ? 'Today' : '${d}d left'),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: expired ? Colors.white : onTile,
        ),
      ),
    );
  }
}

/// Open-row geometry. The icon column is as wide as the row's tile and the text starts where the title
/// starts, so everything in an open row hangs off the same two vertical lines.
const _gutter = 10.0;
const _tileCol = 38.0;
const _textGap = 12.0;

class _Detail extends StatelessWidget {
  const _Detail({
    required this.item,
    required this.tone,
    required this.revealed,
    required this.onReveal,
    required this.onCopy,
    required this.onCall,
    required this.onPin,
    required this.onEdit,
    required this.onDelete,
  });
  final VaultItem item;
  final Tone tone;
  final Set<String> revealed;
  final void Function(String key) onReveal;
  final Future<void> Function(VaultField f) onCopy;
  final VoidCallback onCall, onPin, onEdit, onDelete;

  @override
  Widget build(BuildContext context) {
    final mainField = item.mainField;
    final lines = <Widget>[
      for (final f in item.fields)
        _FieldLine(
          item: item,
          tone: tone,
          primary: identical(f, mainField),
          field: f,
          shown: !f.secret || revealed.contains('${item.id}|${f.label}'),
          onReveal: () => onReveal('${item.id}|${f.label}'),
          onCopy: () => onCopy(f),
        ),
      if (item.expiry != null)
        _InfoLine(
          icon: Icons.event_outlined,
          label: 'Expires',
          value: _date(item.expiry!),
        ),
    ];
    final hair = Palette.of(context).ink.withValues(alpha: 0.10);
    return Padding(
      padding: const EdgeInsets.fromLTRB(_gutter, 0, _gutter, 10),
      child: Column(
        children: [
          Container(height: 1, color: hair),
          for (var i = 0; i < lines.length; i++) ...[
            if (i > 0)
              Container(
                height: 1,
                margin: const EdgeInsets.only(left: _tileCol + _textGap),
                color: hair.withValues(alpha: 0.12),
              ),
            lines[i],
          ],
          const SizedBox(height: 8),
          _OpenActions(
            item: item,
            tone: tone,
            onCall: onCall,
            onPin: onPin,
            onEdit: onEdit,
            onDelete: onDelete,
          ),
        ],
      ),
    );
  }

  static String _date(DateTime d) {
    const m = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }
}

/// Icon in the tile column, then a small label over a value. Shared by every line of an open row.
class _LineShell extends StatelessWidget {
  const _LineShell({
    required this.icon,
    required this.label,
    required this.value,
    this.trailing = const [],
  });
  final IconData icon;
  final String label;
  final Widget value;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 54),
      child: Row(
        children: [
          SizedBox(
            width: _tileCol,
            child: Icon(icon, size: 20, color: p.subText),
          ),
          const SizedBox(width: _textGap),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                      color: p.subText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  value,
                ],
              ),
            ),
          ),
          ...trailing,
        ],
      ),
    );
  }
}

/// A read-only line (no eye, no copy).
class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label, value;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return _LineShell(
      icon: icon,
      label: label,
      value: Text(
        value,
        style: TextStyle(
          fontSize: 15.5,
          height: 1.25,
          fontWeight: FontWeight.w700,
          color: p.text,
        ),
      ),
    );
  }
}

class _FieldLine extends StatelessWidget {
  const _FieldLine({
    required this.item,
    required this.tone,
    required this.field,
    required this.shown,
    required this.onReveal,
    required this.onCopy,
    this.primary = false,
  });
  final VaultItem item;
  final Tone tone;

  /// The field the entry is mostly opened for (the password, the number): its copy button is filled.
  final bool primary;
  final VaultField field;
  final bool shown;
  final VoidCallback onReveal;
  final Future<void> Function() onCopy;

  static IconData _icon(String label) => switch (label) {
    'Username' => Icons.person_outline_rounded,
    'Password' => Icons.key_outlined,
    'Link' => Icons.link_rounded,
    'Number' => Icons.phone_outlined,
    'ID number' => Icons.tag_rounded,
    'Notes' => Icons.notes_rounded,
    _ => Icons.label_outline_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final hidden = field.secret && !shown;
    return _LineShell(
      icon: _icon(field.label),
      label: field.label,
      value: Text(
        hidden ? maskAll(field.value) : field.value,
        maxLines: hidden ? 1 : 4,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: hidden ? 16 : 15.5,
          height: 1.25,
          fontWeight: FontWeight.w700,
          color: p.text,
          letterSpacing: hidden ? 2 : 0,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      trailing: [
        if (field.secret)
          Semantics(
            button: true,
            label: '${shown ? 'Hide' : 'Show'} ${field.label.toLowerCase()}',
            child: ExcludeSemantics(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onReveal,
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(
                    shown ? CupertinoIcons.eye_slash : CupertinoIcons.eye,
                    size: 22,
                    color: p.text.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ),
          ),
        CopyButton(
          label: '${field.label.toLowerCase()} for ${item.title}',
          color: tone.main,
          onColor: tone.on,
          secret: field.secret,
          big: false,
          compact: true,
          flat: true,
          onCopy: onCopy,
        ),
      ],
    );
  }
}

/// Call (numbers), Pin, Edit and Delete as one grouped control: one soft surface, equal segments,
/// thin dividers. Delete is the only red.
class _OpenActions extends StatelessWidget {
  const _OpenActions({
    required this.item,
    required this.tone,
    required this.onCall,
    required this.onPin,
    required this.onEdit,
    required this.onDelete,
  });
  final VaultItem item;
  final Tone tone;
  final VoidCallback onCall, onPin, onEdit, onDelete;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final surface = dark
        ? Colors.white.withValues(alpha: 0.07)
        : Colors.white.withValues(alpha: 0.72);
    final segments = <(IconData, String, String, VoidCallback, Color?)>[
      if (item.section == VaultSection.numbers)
        (Icons.call_outlined, 'Call', 'Call ${item.title}', onCall, null),
      (
        item.favorite ? Icons.star_rounded : Icons.star_outline_rounded,
        item.favorite ? 'Unpin' : 'Pin',
        item.favorite ? 'Unpin' : 'Pin',
        onPin,
        null,
      ),
      (Icons.edit_outlined, 'Edit', 'Edit', onEdit, null),
      (
        Icons.delete_outline_rounded,
        'Delete',
        'Delete ${item.title}',
        onDelete,
        _danger,
      ),
    ];
    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 46,
        child: Row(
          children: [
            for (var i = 0; i < segments.length; i++) ...[
              if (i > 0)
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  indent: 13,
                  endIndent: 13,
                  color: p.ink.withValues(alpha: 0.1),
                ),
              Expanded(
                child: Semantics(
                  button: true,
                  label: segments[i].$3,
                  child: ExcludeSemantics(
                    child: InkWell(
                      onTap: segments[i].$4,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  segments[i].$1,
                                  size: 19,
                                  color: segments[i].$5 ?? p.text,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  segments[i].$2,
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13.5,
                                    color: segments[i].$5 ?? p.text,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Heading above a group: "Pinned", "All items", the picked kind, or "Results".
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
      child: Text(
        text,
        style: heading(13, weight: FontWeight.w700, color: p.subText),
      ),
    );
  }
}

/// The one way to add: centred at the bottom, within thumb reach, keeping the Faelen outline.
class _AddFab extends StatelessWidget {
  const _AddFab({required this.tone, required this.onTap});
  final Tone tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Add',
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 60,
            height: 60,
            decoration: toneBox(
              context,
              tone: tone,
              color: tone.main,
              radius: 20,
              shadow: 4,
            ),
            child: Icon(Icons.add_rounded, color: tone.on, size: 30),
          ),
        ),
      ),
    );
  }
}

/// All / Logins / Numbers / IDs as one slim row of pills with counts. Neutral when off, the Vault colour
/// when picked: the only coloured thing in the row. "All" is always there, so there is always a way back.
class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.current,
    required this.counts,
    required this.onSelect,
  });
  final VaultSection? current;
  final Map<VaultSection, int> counts;
  final ValueChanged<VaultSection?> onSelect;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final tone = _toneOf(context, VaultSection.logins);
    final total = counts.values.fold(0, (a, b) => a + b);
    final entries = <(VaultSection?, String, int)>[
      (null, 'All', total),
      for (final k in VaultSection.values) (k, k.label, counts[k] ?? 0),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
      child: Row(
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: Builder(
                builder: (context) {
                  final (section, label, count) = entries[i];
                  final on = current == section;
                  return Semantics(
                    button: true,
                    selected: on,
                    label: label,
                    child: ExcludeSemantics(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onSelect(section),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          height: 38,
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: on
                                ? tone.main
                                : Color.alphaBlend(
                                    p.ink.withValues(alpha: 0.06),
                                    p.bg,
                                  ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  label,
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontWeight: on
                                        ? FontWeight.w800
                                        : FontWeight.w700,
                                    fontSize: 13,
                                    color: on ? tone.on : p.text,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  '$count',
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                    color: on
                                        ? tone.on.withValues(alpha: 0.75)
                                        : p.subText,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.section,
    required this.tone,
    required this.searching,
    required this.onAdd,
  });
  final VaultSection? section;
  final Tone tone;
  final bool searching;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final what = switch (section) {
      null => 'logins, numbers and IDs',
      VaultSection.logins => 'login',
      VaultSection.numbers => 'number',
      VaultSection.ids => 'ID',
    };
    final title = switch (section) {
      null => 'Nothing saved yet',
      VaultSection.logins => 'No logins yet',
      VaultSection.numbers => 'No numbers yet',
      VaultSection.ids => 'No IDs yet',
    };
    final addLabel = switch (section) {
      null => 'Add your first one',
      VaultSection.logins => 'Add a login',
      VaultSection.numbers => 'Add a number',
      VaultSection.ids => 'Add an ID',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!searching)
              Container(
                width: 88,
                height: 88,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Color.alphaBlend(p.ink.withValues(alpha: 0.06), p.bg),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Image.asset(
                  'assets/cats/passwords.png',
                  fit: BoxFit.contain,
                  excludeFromSemantics: true,
                ),
              ),
            const SizedBox(height: 16),
            Text(
              searching ? 'No match' : title,
              style: heading(20, color: p.text),
            ),
            const SizedBox(height: 4),
            Text(
              searching
                  ? 'Search looks at titles only.'
                  : section == null
                  ? 'Your $what are encrypted on this phone.'
                  : 'Saved $what details are encrypted on this phone.',
              textAlign: TextAlign.center,
              style: TextStyle(color: p.subText, fontWeight: FontWeight.w600),
            ),
            if (!searching) ...[
              const SizedBox(height: 18),
              FilledButton(
                onPressed: onAdd,
                style: FilledButton.styleFrom(
                  backgroundColor: tone.main,
                  foregroundColor: tone.on,
                ),
                child: Text(addLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
