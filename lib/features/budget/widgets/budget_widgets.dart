import 'package:flutter/material.dart';

import '../../../core/theme.dart';

const budgetDanger = Color(0xFFD93636);
const budgetGood = Color(0xFF1F9D55);

/// Something that sinks onto its hard shadow while pressed, like the buttons elsewhere in Faelen.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.onTap, required this.builder, this.lift = 3, this.label, this.onLongPress});
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget Function(bool pressed) builder;
  final double lift;
  final String? label;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final body = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null ? null : (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: Padding(
        padding: EdgeInsets.only(bottom: widget.lift),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          transform: Matrix4.translationValues(0, _down ? widget.lift : 0, 0),
          child: widget.builder(_down),
        ),
      ),
    );
    if (widget.label == null) return body;
    return Semantics(button: true, label: widget.label, child: ExcludeSemantics(child: body));
  }
}

/// A selectable tile: icon over a label. Soft tint when off; filled, outlined and lifted when on.
class ChoiceTile extends StatelessWidget {
  const ChoiceTile({super.key, required this.label, required this.icon, required this.color, required this.on, required this.onTap, this.height = 64});
  final String label;
  final IconData icon;
  final Color color;
  final bool on;
  final VoidCallback onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      button: true,
      selected: on,
      label: label,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            height: height,
            decoration: on
                ? brutal(p, color: color, radius: 14, shadow: 3)
                : BoxDecoration(color: color.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.transparent, width: 2)),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 22, color: on ? onTile : p.text),
              const SizedBox(height: 3),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: on ? FontWeight.w800 : FontWeight.w600, color: on ? onTile : p.text)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// A short bold label above a form control.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(text, style: heading(14, weight: FontWeight.w700, color: Palette.of(context).text)),
      );
}

/// A pill that is on or off (used for card kinds, networks and filters).
class PillChoice extends StatelessWidget {
  const PillChoice({super.key, required this.label, required this.on, required this.onTap, this.dot});
  final String label;
  final bool on;
  final VoidCallback onTap;
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      button: true,
      selected: on,
      label: label,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            constraints: const BoxConstraints(minHeight: 40),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: on ? brutal(p, color: p.primary, radius: 12, shadow: 2) : BoxDecoration(color: p.field, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.outline, width: 1.5)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (dot != null) ...[
                Container(width: 12, height: 12, decoration: BoxDecoration(color: dot, shape: BoxShape.circle, border: Border.all(color: p.ink, width: 1.5))),
                const SizedBox(width: 7),
              ],
              Text(label, style: TextStyle(fontWeight: on ? FontWeight.w800 : FontWeight.w600, fontSize: 13.5, color: on ? p.onPrimary : p.text)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// A rounded tile holding a category icon, in the category's colour.
class CategoryBadge extends StatelessWidget {
  const CategoryBadge({super.key, required this.icon, required this.color, this.size = 44});
  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      width: size,
      height: size,
      decoration: brutal(p, color: color, radius: size * 0.3, shadow: 0, border: 1.5),
      child: Icon(icon, size: size * 0.5, color: onTile),
    );
  }
}
