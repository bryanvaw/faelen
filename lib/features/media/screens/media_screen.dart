import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/media_entry.dart';
import '../state/media_store.dart';
import '../../../core/theme.dart';
import '../media_theme.dart';
import '../widgets/media_card.dart';
import '../widgets/media_form_sheet.dart';

const _maxContentWidth = 1100.0;
const _railBreakpoint = 720.0;

// Navigation order: All, then each media type.
const _navLabels = ['All', 'Manhwa', 'Anime', 'Movie', 'Drama'];
const _navIcons = [
  Icons.grid_view_rounded,
  Icons.menu_book_rounded,
  Icons.live_tv_rounded,
  Icons.movie_rounded,
  Icons.theater_comedy_rounded,
];

Future<void> _openLink(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  var ok = false;
  try {
    ok = uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    // Falls through to the message below.
  }
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open that link')));
  }
}

class MediaScreen extends StatelessWidget {
  const MediaScreen({super.key});

  Future<void> _openForm(BuildContext context, MediaEntry? entry) async {
    final store = context.read<MediaStore>();
    final result = await showMediaForm(context, entry: entry, onDelete: (id) => _confirmDelete(context, id));
    if (result != null) await store.save(result);
  }

  Future<void> _confirmDelete(BuildContext context, String id) async {
    final store = context.read<MediaStore>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Delete entry?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await store.delete(id);
  }

  MediaEntry _bump(MediaEntry e) {
    final next = e.current + 1;
    final done = e.total > 0 && next >= e.total;
    return e.copyWith(
      current: done ? e.total : next,
      status: done ? Status.completed : (e.status == Status.planToWatch ? Status.watching : e.status),
    );
  }

  VoidCallback? _incrementFor(MediaStore store, MediaEntry e) =>
      e.type == MediaType.movie || e.status == Status.completed ? null : () => store.save(_bump(e));

  static int _indexOf(MediaType? t) => t == null ? 0 : t.index + 1;
  static MediaType? _typeAt(int i) => i == 0 ? null : MediaType.values[i - 1];

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final store = context.watch<MediaStore>();
    final wide = MediaQuery.sizeOf(context).width >= _railBreakpoint;
    final add = _AddButton(onTap: () => _openForm(context, null));

    final content = _Content(
      store: store,
      onOpen: (e) => _openForm(context, e),
      onDelete: (id) => _confirmDelete(context, id),
      incrementFor: (e) => _incrementFor(store, e),
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (Theme.of(context).brightness == Brightness.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
          .copyWith(statusBarColor: Colors.transparent),
      child: ColoredBox(
        color: p.bg,
        child: Scaffold(
          bottomNavigationBar: wide
              ? null
              : _BottomBar(
                  selected: store.typeFilter?.index,
                  // Tapping the active type again clears the filter (back to All).
                  onSelect: (i) {
                    final t = MediaType.values[i];
                    store.setType(store.typeFilter == t ? null : t);
                  },
                  add: add,
                ),
          body: SafeArea(
            bottom: wide,
            child: wide
                ? Row(children: [
                    NavigationRail(
                      selectedIndex: _indexOf(store.typeFilter),
                      onDestinationSelected: (i) => store.setType(_typeAt(i)),
                      labelType: NavigationRailLabelType.all,
                      leading: Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: add),
                      destinations: [
                        for (var i = 0; i < _navLabels.length; i++)
                          NavigationRailDestination(icon: Icon(_navIcons[i]), label: Text(_navLabels[i])),
                      ],
                    ),
                    Container(width: 2, color: p.ink),
                    Expanded(child: content),
                  ])
                : content,
          ),
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      button: true,
      label: 'Add title',
      child: Tooltip(
        message: 'Add title',
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 58,
            height: 58,
            decoration: brutal(p, color: p.primary, radius: 29, shadow: 3),
            child: const Icon(Icons.add_rounded, size: 34, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

/// Bottom bar in the app's outlined style: each media type is a labelled tab whose
/// icon sits in a chip. The active tab's chip fills with the type colour, gets an
/// outline and a hard shadow. The add button is raised above the bar.
/// Tap the active type again to clear the filter.
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.selected, required this.onSelect, required this.add});
  final int? selected; // index into MediaType.values, or null for All
  final ValueChanged<int> onSelect;
  final Widget add;

  Widget _item(BuildContext context, int i) {
    final p = Palette.of(context);
    final type = MediaType.values[i];
    final on = selected == i;
    final label = type.label;
    return Expanded(
      child: Semantics(
        button: true,
        selected: on,
        label: on ? '$label, selected. Tap to show all' : label,
        child: ExcludeSemantics(
          child: InkResponse(
            onTap: () => onSelect(i),
            radius: 36,
            child: SizedBox(
              height: 64, // >= 44px touch target
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 46,
                  height: 32,
                  decoration: on
                      ? brutal(p, color: typeColor(type), radius: 12, shadow: 2)
                      : BoxDecoration(
                          color: typeColor(type).withValues(alpha: 0.28),
                          borderRadius: BorderRadius.circular(12),
                        ),
                  child: Icon(typeIcon(type), size: 22, color: on ? onTile : p.text),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: TextStyle(fontSize: 11, fontWeight: on ? FontWeight.w800 : FontWeight.w600, color: p.text),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      key: const ValueKey('bottom-nav'),
      decoration: BoxDecoration(color: p.card, border: Border(top: BorderSide(color: p.ink, width: 2))),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 76,
          child: Row(children: [
            _item(context, 0),
            _item(context, 1),
            // Raised a little above the bar; stays within the bar's hit area.
            Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Center(child: Transform.translate(offset: const Offset(0, -8), child: add))),
            _item(context, 2),
            _item(context, 3),
          ]),
        ),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.store, required this.onOpen, required this.onDelete, required this.incrementFor});
  final MediaStore store;
  final void Function(MediaEntry) onOpen;
  final void Function(String) onDelete;
  final VoidCallback? Function(MediaEntry) incrementFor;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    if (store.loading) return Center(child: CircularProgressIndicator(color: p.primary));

    final items = store.visible;

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxContentWidth),
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            const _Header(),
            _StatusTiles(store: store),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
              child: Row(children: [
                Expanded(
                  child: Text(
                    store.typeFilter == null ? 'Library' : '${store.typeFilter!.label} library',
                    style: heading(21, weight: FontWeight.w700, color: p.text),
                  ),
                ),
                PopupMenuButton<MediaSort>(
                  tooltip: 'Sort: ${store.sort.label}',
                  initialValue: store.sort,
                  onSelected: store.setSort,
                  itemBuilder: (_) => [
                    for (final s in MediaSort.values) PopupMenuItem(value: s, child: Text(s.label)),
                  ],
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 44),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.sort_rounded, color: p.text, size: 22),
                      const SizedBox(width: 6),
                      Text(store.sort.label, style: TextStyle(color: p.text, fontSize: 13, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              child: Container(
                decoration: brutal(p, color: p.field, radius: 14, shadow: 3),
                child: TextField(
                  onChanged: store.setQuery,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search titles…',
                    hintStyle: TextStyle(color: p.subText),
                    prefixIcon: Icon(Icons.search_rounded, color: p.text),
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ),
            ),
            if (items.isEmpty)
              _Empty(message: store.error ?? (store.totalCount == 0 ? 'Nothing here yet.\nTap + to add your first title.' : 'No matches.'))
            else
              LayoutBuilder(builder: (context, c) {
                // 1 column on phones, 2 on tablets, 3 on wide screens.
                const pad = 20.0, gap = 18.0;
                final cols = c.maxWidth >= 900 ? 3 : (c.maxWidth >= 600 ? 2 : 1);
                final w = (c.maxWidth - pad * 2 - gap * (cols - 1)) / cols;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: pad),
                  child: Wrap(spacing: gap, runSpacing: gap, children: [
                    for (final e in items)
                      SizedBox(
                        key: ValueKey(e.id),
                        width: w,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 4), // room for the hard shadow
                          child: MediaCard(
                            entry: e,
                            onTap: () => onOpen(e),
                            onLongPress: () => onDelete(e.id),
                            onIncrement: incrementFor(e),
                            onContinue: e.url.isEmpty ? null : () => _openLink(context, e.url),
                            coverFile: store.covers.fileFor(e.cover),
                          ),
                        ),
                      ),
                  ]),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Row(children: [
        if (Navigator.canPop(context)) ...[
          IconButton(
            tooltip: 'Back to modules',
            onPressed: () => Navigator.maybePop(context),
            icon: Icon(Icons.arrow_back_rounded, color: p.text),
          ),
          const SizedBox(width: 4),
        ],
        Container(
          width: 50,
          height: 50,
          decoration: brutal(p, color: p.primary, radius: 16, shadow: 3),
          child: Icon(Icons.movie_filter_rounded, color: p.onPrimary),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('My List', style: heading(26, weight: FontWeight.w700, color: p.text, height: 1.15)),
            Text('Your watch & read tracker', style: TextStyle(color: p.subText, fontSize: 13, fontWeight: FontWeight.w500)),
          ]),
        ),
      ]),
    );
  }
}

/// Status overview tiles. Tapping one filters the list by that status.
class _StatusTiles extends StatelessWidget {
  const _StatusTiles({required this.store});
  final MediaStore store;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return LayoutBuilder(builder: (context, c) {
      const pad = 20.0, gap = 14.0;
      final cols = c.maxWidth >= 760 ? 6 : 3;
      final w = (c.maxWidth - pad * 2 - gap * (cols - 1)) / cols;

      Widget tile({
        required String label,
        required int count,
        required IconData icon,
        required Color color,
        required bool selected,
        required VoidCallback onTap,
      }) {
        return SizedBox(
          width: w,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Semantics(
              button: true,
              selected: selected,
              label: '$label, $count titles',
              child: GestureDetector(
                onTap: onTap,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 96),
                  padding: const EdgeInsets.all(12),
                  decoration: brutal(p, color: color, radius: 16, shadow: 3, border: selected ? 3.5 : 2),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.12), shape: BoxShape.circle),
                        child: Icon(icon, size: 18, color: onTile),
                      ),
                      if (selected) const Icon(Icons.check_circle_rounded, size: 18, color: onTile),
                    ]),
                    const SizedBox(height: 10),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(label, style: heading(15, weight: FontWeight.w700, color: onTile)),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text('$count ${count == 1 ? 'title' : 'titles'}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: onTile)),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        );
      }

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: pad),
        child: Wrap(spacing: gap, runSpacing: 10, children: [
          tile(
            label: 'All',
            count: store.totalCount,
            icon: Icons.apps_rounded,
            color: p.card == Colors.white ? Colors.white : const Color(0xFFEDEDED),
            selected: store.statusFilter == null,
            onTap: () => store.setStatus(null),
          ),
          for (final s in Status.values)
            tile(
              label: _shortLabel(s),
              count: store.countWhere(s),
              icon: statusIcon(s),
              color: statusColor(s),
              selected: store.statusFilter == s,
              onTap: () => store.setStatus(store.statusFilter == s ? null : s),
            ),
        ]),
      );
    });
  }

  static String _shortLabel(Status s) => switch (s) {
        Status.watching => 'Watching',
        Status.planToWatch => 'Planned',
        Status.completed => 'Completed',
        Status.onHold => 'On Hold',
        Status.dropped => 'Dropped',
      };
}

class _Empty extends StatelessWidget {
  const _Empty({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(children: [
        Icon(Icons.movie_filter_rounded, size: 64, color: p.subText.withValues(alpha: 0.6)),
        const SizedBox(height: 12),
        Text(message,
            textAlign: TextAlign.center,
            style: TextStyle(color: p.subText, fontSize: 15, fontWeight: FontWeight.w600, height: 1.4)),
      ]),
    );
  }
}
