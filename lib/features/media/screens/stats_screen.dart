import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme.dart';
import '../media_theme.dart';
import '../models/media_entry.dart';
import '../state/media_store.dart';

/// The whole library at a glance, built to fit one phone screen: a hero card (titles, rating and a
/// status bar), three progress counters and a by-type breakdown.
class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final items = context.watch<MediaStore>().items;
    final rated = items.where((e) => e.rating > 0).toList();
    final avg = rated.isEmpty ? null : rated.fold<int>(0, (a, e) => a + e.rating) / rated.length / 2; // stars
    int sum(MediaType t) => items.where((e) => e.type == t).fold(0, (a, e) => a + e.current);
    final chapters = sum(MediaType.manhwa);
    final episodes = sum(MediaType.anime) + sum(MediaType.drama);
    final movies = items.where((e) => e.type == MediaType.movie && e.status == Status.completed).length;
    final byStatus = {for (final s in Status.values) s: items.where((e) => e.status == s).length};
    final byType = {for (final t in MediaType.values) t: items.where((e) => e.type == t).length};
    final topType = byType.values.fold(0, (a, b) => b > a ? b : a);

    return ColoredBox(
      color: p.bg,
      child: Scaffold(
        appBar: AppBar(title: Text('Library stats', style: heading(22, weight: FontWeight.w700, color: p.text))),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: items.isEmpty
                  ? Center(child: Text('Add a few titles to see stats.', style: TextStyle(color: p.subText, fontSize: 15)))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        _Card(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Expanded(
                                child: _Figure(value: '${items.length}', label: items.length == 1 ? 'Title' : 'Titles', big: true),
                              ),
                              _Figure(
                                value: avg == null ? '-' : avg.toStringAsFixed(1),
                                label: 'Avg rating',
                                icon: avg == null ? null : Icons.star_rounded,
                                iconColor: const Color(0xFFF5A623),
                                alignEnd: true,
                              ),
                            ]),
                            const SizedBox(height: 14),
                            _StatusBar(counts: byStatus, total: items.length),
                            const SizedBox(height: 12),
                            Wrap(spacing: 14, runSpacing: 6, children: [
                              for (final s in Status.values)
                                _Legend(color: statusColor(s), label: _short(s), count: byStatus[s]!),
                            ]),
                          ]),
                        ),
                        const SizedBox(height: 14),
                        Row(children: [
                          Expanded(child: _Counter(icon: Icons.menu_book_rounded, value: chapters, label: 'Chapters', color: typeColor(MediaType.manhwa))),
                          const SizedBox(width: 10),
                          Expanded(child: _Counter(icon: Icons.live_tv_rounded, value: episodes, label: 'Episodes', color: typeColor(MediaType.anime))),
                          const SizedBox(width: 10),
                          Expanded(child: _Counter(icon: Icons.movie_rounded, value: movies, label: 'Movies', color: typeColor(MediaType.movie))),
                        ]),
                        const SizedBox(height: 14),
                        _Card(
                          child: Column(children: [
                            for (final t in MediaType.values) ...[
                              if (t != MediaType.values.first) const SizedBox(height: 12),
                              _TypeRow(type: t, count: byType[t]!, top: topType),
                            ],
                          ]),
                        ),
                      ]),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  static String _short(Status s) => switch (s) {
        Status.planToWatch => 'Planned',
        Status.watching => 'Watching',
        Status.completed => 'Completed',
        Status.onHold => 'On hold',
        Status.dropped => 'Dropped',
      };
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4), // room for the hard shadow
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: brutal(p, radius: 18, shadow: 3),
        child: child,
      ),
    );
  }
}

/// A number with a small caption; the hero one is large.
class _Figure extends StatelessWidget {
  const _Figure({required this.value, required this.label, this.big = false, this.icon, this.iconColor, this.alignEnd = false});
  final String value;
  final String label;
  final bool big;
  final IconData? icon;
  final Color? iconColor;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Column(
      crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Text(value, style: heading(big ? 44 : 26, weight: FontWeight.w800, color: p.text, height: 1.0)),
          if (icon != null) ...[const SizedBox(width: 3), Icon(icon, size: big ? 28 : 22, color: iconColor)],
        ]),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: p.subText, fontSize: 12.5, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

/// One bar split into status colours in proportion to how many titles have each status.
class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.counts, required this.total});
  final Map<Status, int> counts;
  final int total;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      label: 'Status split: ${[for (final s in Status.values) if (counts[s]! > 0) '${counts[s]} ${s.label}'].join(', ')}',
      child: ExcludeSemantics(
        child: Container(
          height: 14,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: p.outline, width: 1.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(children: [
            for (final s in Status.values)
              if (counts[s]! > 0) Expanded(flex: counts[s]!, child: ColoredBox(color: statusColor(s), child: const SizedBox.expand())),
          ]),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label, required this.count});
  final Color color;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Opacity(
      opacity: count == 0 ? 0.5 : 1,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text('$label ', style: TextStyle(color: p.subText, fontSize: 12.5, fontWeight: FontWeight.w600)),
        Text('$count', style: TextStyle(color: p.text, fontSize: 12.5, fontWeight: FontWeight.w800)),
      ]),
    );
  }
}

class _Counter extends StatelessWidget {
  const _Counter({required this.icon, required this.value, required this.label, required this.color});
  final IconData icon;
  final int value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: brutal(p, radius: 16, shadow: 2),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, size: 17, color: onTile),
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text('$value', style: heading(24, weight: FontWeight.w800, color: p.text, height: 1.0)),
          ),
          const SizedBox(height: 3),
          Text(label, maxLines: 1, style: TextStyle(color: p.subText, fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}

class _TypeRow extends StatelessWidget {
  const _TypeRow({required this.type, required this.count, required this.top});
  final MediaType type;
  final int count;
  final int top;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final color = typeColor(type);
    return Row(children: [
      Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(9)),
        child: Icon(typeIcon(type), size: 17, color: onTile),
      ),
      const SizedBox(width: 12),
      SizedBox(width: 68, child: Text(type.label, style: heading(14, weight: FontWeight.w700, color: p.text))),
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: top == 0 ? 0 : count / top, minHeight: 8, color: color, backgroundColor: p.outline.withValues(alpha: 0.5)),
        ),
      ),
      SizedBox(width: 34, child: Text('$count', textAlign: TextAlign.end, style: heading(15, weight: FontWeight.w800, color: p.text))),
    ]);
  }
}
