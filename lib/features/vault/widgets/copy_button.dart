import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme.dart';

/// Copies something and shows it on the button itself: a check, a green face, and for secrets a
/// thin bar along the bottom edge that drains over [clearAfter] (when the clipboard is cleared).
/// No snackbar, so nothing covers the list or the bottom bar.
class CopyButton extends StatefulWidget {
  const CopyButton({
    super.key,
    required this.onCopy,
    required this.label,
    this.secret = false,
    this.clearAfter = const Duration(seconds: 30),
    this.big = true,
    this.color,
  });

  final Future<void> Function() onCopy;

  /// Spoken name: "password for Netflix".
  final String label;
  final bool secret;
  final Duration clearAfter;

  /// 48dp coral button for a row's main copy; false is the 44dp quiet icon inside an open row.
  final bool big;

  /// The section's colour for the button face and the draining bar; the app's coral when null.
  final Color? color;

  @override
  State<CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<CopyButton> with SingleTickerProviderStateMixin {
  late final AnimationController _drain = AnimationController(vsync: this);
  Timer? _reset;
  bool _copied = false;

  @override
  void dispose() {
    _reset?.cancel();
    _drain.dispose();
    super.dispose();
  }

  Future<void> _tap() async {
    await widget.onCopy();
    if (!mounted) return;
    setState(() => _copied = true);
    _reset?.cancel();
    final hold = widget.secret ? widget.clearAfter : const Duration(seconds: 2);
    if (widget.secret && !MediaQuery.disableAnimationsOf(context)) {
      _drain.duration = hold;
      _drain.forward(from: 0);
    }
    _reset = Timer(hold, () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final size = widget.big ? 48.0 : 44.0;
    final accent = widget.color ?? p.primary;
    // Copied flips to the ink colour (dark in light mode, light in dark mode) so it reads on every
    // section colour; the bar that drains keeps the section colour.
    final face = _copied ? p.ink : (widget.big ? accent : Colors.transparent);
    final fg = _copied ? p.bg : (widget.big ? onTile : p.text);
    return Semantics(
      button: true,
      liveRegion: true,
      label: _copied ? 'Copied ${widget.label}' : 'Copy ${widget.label}',
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _tap,
          child: SizedBox(
            width: size,
            height: size,
            child: Container(
              decoration: BoxDecoration(
                color: face,
                borderRadius: BorderRadius.circular(widget.big ? 14 : 12),
                border: widget.big || _copied ? Border.all(color: p.ink, width: 2) : null,
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(alignment: Alignment.center, children: [
                Icon(_copied ? Icons.check_rounded : Icons.copy_rounded, size: widget.big ? 22 : 20, color: fg),
                if (_copied && widget.secret)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: AnimatedBuilder(
                      animation: _drain,
                      builder: (_, _) => Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: (1 - _drain.value).clamp(0.0, 1.0),
                          child: Container(height: 4, color: accent),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
