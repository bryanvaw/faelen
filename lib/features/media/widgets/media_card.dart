import 'dart:io';

import 'package:flutter/material.dart';

import '../models/media_entry.dart';
import '../../../core/theme.dart';
import '../media_theme.dart';
import '../services/release_schedule.dart';

class MediaCard extends StatelessWidget {
  const MediaCard({
    super.key,
    required this.entry,
    required this.onTap,
    required this.onLongPress,
    this.onIncrement,
    this.onContinue,
    this.coverFile,
  });

  final MediaEntry entry;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  /// Adds one episode/chapter. Null hides the button (movies, completed).
  final VoidCallback? onIncrement;

  /// Opens the saved link. Null hides the button (no link).
  final VoidCallback? onContinue;

  /// Cover image to show on the left, if the entry has one and it exists on disk.
  final File? coverFile;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final color = statusColor(entry.status);
    final isMovie = entry.type == MediaType.movie;
    final progressLabel =
        '${entry.season > 0 ? 'S${entry.season} · ' : ''}${entry.type.unit} ${entry.current} / ${entry.total > 0 ? entry.total : '?'}';
    final unitName = entry.type.unit == 'Ch' ? 'chapter' : 'episode';
    final release = releaseStatus(entry, DateTime.now());

    return Container(
      decoration: brutal(p),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(entry.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: heading(17, weight: FontWeight.w600, color: p.text, height: 1.2)),
                    const SizedBox(height: 6),
                    Row(children: [
                      Icon(typeIcon(entry.type), size: 15, color: p.subText),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text('${entry.type.label} · ${entry.status.label}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: p.subText, fontSize: 12.5, fontWeight: FontWeight.w600)),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    Wrap(spacing: 12, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      if (!isMovie)
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.check_circle_outline_rounded, size: 16, color: p.text),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(progressLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: p.text, fontSize: 12.5, fontWeight: FontWeight.w700)),
                          ),
                        ]),
                      if (release != null) _ReleaseChip(release: release, unit: entry.type.unit),
                      if (entry.rating > 0)
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.star_rounded, size: 17, color: Color(0xFFF5A623)),
                          const SizedBox(width: 2),
                          Text(ratingLabel(entry.rating), style: TextStyle(color: p.text, fontSize: 12.5, fontWeight: FontWeight.w800)),
                        ]),
                    ]),
                    if (!isMovie && entry.total > 0) ...[
                      const SizedBox(height: 10),
                      Semantics(
                        label: '${(entry.progress * 100).round()} percent',
                        child: ExcludeSemantics(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: entry.progress,
                              minHeight: 7,
                              color: color,
                              backgroundColor: p.outline,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ]),
                ),
                const SizedBox(width: 14),
                _Cover(file: coverFile, entry: entry),
              ]),
              // Actions span the card's full width so nothing floats beside the progress ring.
              if (onContinue != null || onIncrement != null) ...[
                const SizedBox(height: 12),
                Row(children: [
                  if (onContinue != null)
                    Expanded(
                      child: _ActionPill(
                        label: 'Continue',
                        icon: Icons.open_in_new_rounded,
                        semantics: 'Continue ${entry.title} in browser',
                        filled: color,
                        expand: true,
                        onTap: onContinue!,
                      ),
                    ),
                  if (onContinue != null && onIncrement != null) const SizedBox(width: 10),
                  if (onIncrement != null)
                    onContinue == null
                        ? Expanded(
                            child: _ActionPill(
                              label: '+1 ${entry.type.unit}',
                              icon: Icons.add_rounded,
                              semantics: 'Add one $unitName to ${entry.title}',
                              expand: true,
                              onTap: onIncrement!,
                            ),
                          )
                        : _ActionPill(
                            label: '+1 ${entry.type.unit}',
                            semantics: 'Add one $unitName to ${entry.title}',
                            onTap: onIncrement!,
                          ),
                ]),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// Small pill button on the card: filled with the status colour, or outlined for the quiet action.
class _ActionPill extends StatelessWidget {
  const _ActionPill({required this.label, required this.semantics, required this.onTap, this.icon, this.filled, this.expand = false});
  final String label;
  final String semantics;
  final VoidCallback onTap;
  final IconData? icon;
  final Color? filled; // null = outlined on the card colour
  final bool expand; // fill the width it is given instead of hugging the label

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final fg = filled != null ? onTile : p.text;
    return Semantics(
      button: true,
      label: semantics,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44), // full-size touch target
            child: Center(
              child: Container(
                height: 40,
                width: expand ? double.infinity : null,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: brutal(p, color: filled ?? p.card, radius: 20, shadow: filled != null ? 2 : 0),
                child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                  if (icon != null) ...[Icon(icon, size: 16, color: fg), const SizedBox(width: 6)],
                  Flexible(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: heading(12.5, weight: FontWeight.w700, color: fg)),
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

/// "3 new" when behind, otherwise "Caught up" with the next release day.
class _ReleaseChip extends StatelessWidget {
  const _ReleaseChip({required this.release, required this.unit});
  final ReleaseStatus release;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final behind = release.behind;
    final next = release.nextRelease;
    final nextLabel = next == null ? 'Series finished' : 'Next ${weekdayShort[next.weekday - 1]}';
    final text = behind > 0 ? '$behind new' : 'Caught up · $nextLabel';
    return Semantics(
      label: behind > 0 ? '$behind unread, ${release.released} released' : 'Caught up. $nextLabel',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: behind > 0
              ? brutal(p, color: p.primary, radius: 10, shadow: 1)
              : BoxDecoration(color: p.field, borderRadius: BorderRadius.circular(10)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(behind > 0 ? Icons.new_releases_rounded : Icons.event_available_rounded,
                size: 14, color: behind > 0 ? onTile : p.subText),
            const SizedBox(width: 4),
            Flexible(
              child: Text(text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: behind > 0 ? onTile : p.subText)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// The poster on the right of the card. Entries without a cover (or on web, where covers are
/// unavailable) get a tile in the type's colour and icon, so the card keeps the same shape.
class _Cover extends StatelessWidget {
  const _Cover({required this.file, required this.entry});
  final File? file;
  final MediaEntry entry;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    Widget placeholder() => Container(
          color: typeColor(entry.type),
          alignment: Alignment.center,
          child: Icon(typeIcon(entry.type), size: 28, color: onTile),
        );
    return Container(
      width: 70,
      height: 100,
      decoration: brutal(p, radius: 12, shadow: 2),
      clipBehavior: Clip.antiAlias,
      child: file == null
          ? placeholder()
          : Image.file(
              file!,
              fit: BoxFit.cover,
              cacheWidth: 210, // decode small; the card only shows 70px
              semanticLabel: 'Cover of ${entry.title}',
              errorBuilder: (_, _, _) => placeholder(),
            ),
    );
  }
}
