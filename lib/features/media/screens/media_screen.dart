import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/media_entry.dart';
import '../state/media_store.dart';
import '../../../core/theme.dart';
import '../media_theme.dart';
import '../services/pinned_actions.dart';
import '../services/pinned_store.dart';
import '../services/release_schedule.dart';
import 'stats_screen.dart';
import '../widgets/media_card.dart';
import '../widgets/media_form_sheet.dart';

const _maxContentWidth = 1100.0;
const _railBreakpoint = 720.0;

// Navigation order: All, then each media type.
const _navLabels = ['All', 'Webtoon', 'Anime', 'Movie', 'Drama'];
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

Future<void> _togglePin(BuildContext context, PinnedStore pins, String id) async {
  final problem = await pins.toggle(id);
  if (problem != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problem)));
  }
}

class MediaScreen extends StatelessWidget {
  const MediaScreen({super.key});

  Future<void> _openForm(BuildContext context, MediaEntry? entry) async {
    final store = context.read<MediaStore>();
    final result = await showMediaForm(context, entry: entry, initialType: store.typeFilter, onDelete: (id) => _confirmDelete(context, id));
    if (result != null) await store.save(result);
  }

  Future<void> _confirmDelete(BuildContext context, String id) async {
    final store = context.read<MediaStore>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Delete entry?'),
        content: const Text('You can undo it for a few seconds afterwards.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    final removed = await store.softDelete(id);
    if (removed == null || !context.mounted) return;
    // The cover file is only deleted once the undo window closes.
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(
          content: Text('Deleted "${removed.title}"'),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(label: 'Undo', onPressed: () => store.restore(removed)),
        ))
        .closed
        .then((reason) {
      if (reason != SnackBarClosedReason.action) store.purgeCover(removed);
    });
  }

  /// Marks everything released so far as read/watched.
  MediaEntry _catchUp(MediaEntry e) {
    final released = releaseStatus(e, DateTime.now())?.released ?? e.current;
    final next = released > e.current ? released : e.current;
    final done = e.total > 0 && next >= e.total;
    return e.copyWith(current: next, status: done ? Status.completed : e.status);
  }

  VoidCallback? _incrementFor(MediaStore store, MediaEntry e) =>
      e.type == MediaType.movie || e.status == Status.completed ? null : () => store.save(bumpEntry(e));

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
      catchUp: (e) => store.save(_catchUp(e)),
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
  const _Content({required this.store, required this.onOpen, required this.onDelete, required this.incrementFor, required this.catchUp});
  final MediaStore store;
  final void Function(MediaEntry) onOpen;
  final void Function(String) onDelete;
  final VoidCallback? Function(MediaEntry) incrementFor;
  final void Function(MediaEntry) catchUp;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    if (store.loading) return Center(child: CircularProgressIndicator(color: p.primary));

    final items = store.visible;
    final pins = context.watch<PinnedStore?>(); // null where pinning is not set up

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxContentWidth),
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            _Header(store: store),
            if (store.notice != null) _NoticeBanner(message: store.notice!, onClose: store.dismissNotice),
            _StatusTiles(store: store),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
              child: Row(children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(
                        text: store.typeFilter == null ? 'Library' : '${store.typeFilter!.label} library',
                        style: heading(20, weight: FontWeight.w700, color: p.text),
                      ),
                      TextSpan(
                        text: '  ${items.length}',
                        style: TextStyle(color: p.subText, fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'Library stats',
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const StatsScreen())),
                  icon: Icon(Icons.insights_rounded, color: p.text, size: 22),
                ),
                PopupMenuButton<MediaSort>(
                  tooltip: 'Sort: ${store.sort.label}',
                  position: PopupMenuPosition.under,
                  onSelected: store.setSort,
                  itemBuilder: (_) => [
                    for (final s in MediaSort.values)
                      PopupMenuItem(
                        value: s,
                        child: Row(children: [
                          Expanded(
                            child: Text(s.label,
                                style: TextStyle(
                                    color: s == store.sort ? p.primary : p.text,
                                    fontWeight: s == store.sort ? FontWeight.w800 : FontWeight.w600)),
                          ),
                          if (s == store.sort) Icon(Icons.check_rounded, size: 18, color: p.primary),
                        ]),
                      ),
                  ],
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 44),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.sort_rounded, color: p.text, size: 20),
                      const SizedBox(width: 6),
                      Text(store.sort.label, style: TextStyle(color: p.text, fontSize: 13, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
              ]),
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
                            onCatchUp: () => catchUp(e),
                            onContinue: e.url.isEmpty
                                ? null
                                : () async {
                                    await pins?.pinForContinue(e); // so +1 / Done are one swipe away in the shade
                                    if (context.mounted) await _openLink(context, e.url);
                                  },
                            pinned: pins?.isPinned(e.id) ?? false,
                            onTogglePin: pins != null && PinnedStore.supported && canPin(e) ? () => _togglePin(context, pins, e.id) : null,
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

/// One compact row: back, brand mark, title and a search button. Tapping the button turns the row
/// into a search field (and the close button turns it back), so searching costs no permanent space.
/// On wide screens the field simply stays open beside the title.
class _Header extends StatefulWidget {
  const _Header({required this.store});
  final MediaStore store;

  @override
  State<_Header> createState() => _HeaderState();
}

class _HeaderState extends State<_Header> {
  late bool _open = widget.store.query.isNotEmpty;
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller.text = widget.store.query;
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _show() {
    setState(() => _open = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  void _close() {
    _controller.clear();
    widget.store.setQuery('');
    _focus.unfocus();
    setState(() => _open = false);
  }

  Widget _field(Palette p, {required bool closable}) => Container(
        height: 46,
        decoration: brutal(p, color: p.field, radius: 14, shadow: 3),
        child: TextField(
          controller: _controller,
          focusNode: _focus,
          onChanged: widget.store.setQuery,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search titles…',
            hintStyle: TextStyle(color: p.subText),
            prefixIcon: Icon(Icons.search_rounded, color: p.text),
            suffixIcon: closable
                ? IconButton(
                    tooltip: 'Close search',
                    onPressed: _close,
                    icon: Icon(Icons.close_rounded, color: p.text),
                  )
                : null,
            isDense: true,
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 13),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 600;
    final searching = widget.store.query.isNotEmpty;

    final back = Navigator.canPop(context)
        ? IconButton(
            tooltip: 'Back to modules',
            onPressed: () => Navigator.maybePop(context),
            icon: Icon(Icons.arrow_back_rounded, color: p.text),
          )
        : const SizedBox(width: 12);

    final brand = [
      Image.asset('assets/cats/media.png', width: 44, height: 44, excludeFromSemantics: true),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('My List', style: heading(22, weight: FontWeight.w700, color: p.text, height: 1.1)),
          Text('Your watch & read tracker',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.subText, fontSize: 12, fontWeight: FontWeight.w500)),
        ]),
      ),
    ];

    Widget row;
    if (wide) {
      row = Row(children: [back, ...brand, ConstrainedBox(constraints: const BoxConstraints(maxWidth: 340, minWidth: 220), child: _field(p, closable: false))]);
    } else if (_open) {
      row = Row(children: [back, Expanded(child: _field(p, closable: true))]);
    } else {
      row = Row(children: [
        back,
        ...brand,
        const SizedBox(width: 8),
        Semantics(
          button: true,
          label: searching ? 'Search, filtering by "${widget.store.query}"' : 'Search titles',
          child: Tooltip(
            message: 'Search titles',
            child: GestureDetector(
              onTap: _show,
              child: Container(
                width: 46,
                height: 46,
                decoration: brutal(p, color: searching ? p.primary : p.field, radius: 14, shadow: 3),
                child: Icon(Icons.search_rounded, color: searching ? p.onPrimary : p.text),
              ),
            ),
          ),
        ),
      ]);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 20, 14),
      child: SizedBox(
        height: 50,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          child: KeyedSubtree(key: ValueKey(wide ? 'wide' : _open), child: row),
        ),
      ),
    );
  }
}

/// Status filter tiles in a 3x2 grid (one row of six on wide screens). Each shows the icon and the
/// live count on one line with the label under it, so the grid stays compact. Tapping one filters
/// the list by that status; tapping it again (or All) clears it.
class _StatusTiles extends StatelessWidget {
  const _StatusTiles({required this.store});
  final MediaStore store;

  static String _shortLabel(Status s) => switch (s) {
        Status.watching => 'Watching',
        Status.planToWatch => 'Planned',
        Status.completed => 'Completed',
        Status.onHold => 'On Hold',
        Status.dropped => 'Dropped',
      };

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return LayoutBuilder(builder: (context, c) {
      const pad = 20.0, gap = 10.0;
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
        // The neutral tile is always light, so it needs dark text in both themes (p.text is light in dark mode).
        final fg = onTile;
        return SizedBox(
          width: w,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 4), // room for the hard shadow
            child: Semantics(
              button: true,
              selected: selected,
              label: '$label, $count ${count == 1 ? 'title' : 'titles'}',
              child: ExcludeSemantics(
                child: GestureDetector(
                  onTap: onTap,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
                    // An empty status stays in its full colour but sits flat (no shadow, thinner outline), so it recedes
                    // by depth instead of by washing out.
                    decoration: brutal(p,
                        color: color,
                        radius: 14,
                        shadow: selected ? 3 : (count == 0 ? 0 : 2),
                        border: selected ? 3 : (count == 0 ? 1.5 : 2)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        // The selected tile's icon turns into a check, so the state shows without shifting the layout.
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: selected ? p.ink : Colors.black.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(selected ? Icons.check_rounded : icon, size: 17, color: selected ? p.card : fg),
                        ),
                        const Spacer(),
                        Text('$count', style: heading(21, weight: FontWeight.w800, color: fg, height: 1.0)),
                      ]),
                      const SizedBox(height: 7),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(label, maxLines: 1, style: heading(14, weight: FontWeight.w700, color: fg)),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        );
      }

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: pad),
        child: Wrap(spacing: gap, runSpacing: 6, children: [
          tile(
            label: 'All',
            count: store.totalCount,
            icon: Icons.apps_rounded,
            color: const Color(0xFFF1F1F1),
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
}

/// A dismissible heads-up shown after loading when entries were skipped or restored.
class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({required this.message, required this.onClose});
  final String message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
        decoration: brutal(p, color: const Color(0xFFFFD66B), radius: 14, shadow: 2),
        child: Row(children: [
          const Icon(Icons.warning_amber_rounded, color: onTile),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: const TextStyle(color: onTile, fontWeight: FontWeight.w700, fontSize: 13))),
          IconButton(tooltip: 'Dismiss', onPressed: onClose, icon: const Icon(Icons.close_rounded, color: onTile)),
        ]),
      ),
    );
  }
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
