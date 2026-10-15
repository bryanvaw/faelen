import 'dart:io';

import 'package:flutter/material.dart';

import '../models/media_entry.dart';
import '../../../core/theme.dart';
import '../media_theme.dart';

class MediaCard extends StatelessWidget {
  const MediaCard({
    super.key,
    required this.entry,
    required this.onTap,
    required this.onLongPress,
    this.onIncrement,
    this.coverFile,
  });

  final MediaEntry entry;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  /// Adds one episode/chapter. Null hides the button (movies, completed).
  final VoidCallback? onIncrement;

  /// Cover image to show on the left, if the entry has one and it exists on disk.
  final File? coverFile;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final color = statusColor(entry.status);
    final isMovie = entry.type == MediaType.movie;
    final progressLabel = '${entry.type.unit} ${entry.current} / ${entry.total > 0 ? entry.total : '?'}';
    final unitName = entry.type.unit == 'Ch' ? 'chapter' : 'episode';

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
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              if (coverFile != null) ...[
                _Cover(file: coverFile!, title: entry.title),
                const SizedBox(width: 14),
              ],
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
                        Text(progressLabel, style: TextStyle(color: p.text, fontSize: 12.5, fontWeight: FontWeight.w700)),
                      ]),
                    if (entry.rating > 0)
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.star_rounded, size: 17, color: Color(0xFFF5A623)),
                        const SizedBox(width: 2),
                        Text(ratingLabel(entry.rating), style: TextStyle(color: p.text, fontSize: 12.5, fontWeight: FontWeight.w800)),
                      ]),
                    if (onIncrement != null)
                      Semantics(
                        button: true,
                        label: 'Add one $unitName to ${entry.title}',
                        child: InkResponse(
                          onTap: onIncrement,
                          radius: 26,
                          child: Container(
                            width: 44, // 44px touch target
                            height: 36,
                            alignment: Alignment.center,
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(color: p.ink, shape: BoxShape.circle),
                              child: Icon(Icons.add_rounded, size: 20, color: p.card),
                            ),
                          ),
                        ),
                      ),
                  ]),
                ]),
              ),
              const SizedBox(width: 12),
              _Ring(entry: entry, color: color, isMovie: isMovie),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.entry, required this.color, required this.isMovie});
  final MediaEntry entry;
  final Color color;
  final bool isMovie;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final done = entry.status == Status.completed;
    final noBar = isMovie || entry.total == 0;
    final value = noBar ? (done ? 1.0 : 0.0) : entry.progress;

    final Widget center = noBar
        ? (done || isMovie
            ? Icon(done ? Icons.check_rounded : statusIcon(entry.status), color: p.text, size: 22)
            : Text('${entry.current}', style: heading(15, weight: FontWeight.w700, color: p.text)))
        : Text('${(entry.progress * 100).round()}%', style: heading(13, weight: FontWeight.w700, color: p.text));

    return Semantics(
      label: '${entry.status.label}${entry.total > 0 ? ', ${(entry.progress * 100).round()} percent' : ''}',
      child: SizedBox(
        width: 58,
        height: 58,
        child: Stack(alignment: Alignment.center, children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: value,
              strokeWidth: 6,
              strokeCap: StrokeCap.round,
              color: color,
              backgroundColor: p.outline,
            ),
          ),
          center,
        ]),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.file, required this.title});
  final File file;
  final String title;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      width: 56,
      height: 80,
      decoration: brutal(p, radius: 10, shadow: 2),
      clipBehavior: Clip.antiAlias,
      child: Image.file(
        file,
        fit: BoxFit.cover,
        cacheWidth: 168, // decode small; the card only shows 56px
        semanticLabel: 'Cover of $title',
        errorBuilder: (_, _, _) => Icon(Icons.image_not_supported_outlined, color: p.subText),
      ),
    );
  }
}
