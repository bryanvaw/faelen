import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme.dart';
import '../models/budget_models.dart';
import '../state/budget_store.dart';

const budgetDanger = Color(0xFFD93636);
const budgetGood = Color(0xFF1F9D55);

/// The colours of the Budget screens, all derived from the selected card's colour so buttons, tabs, bars
/// and sheets read as one family with the card above them.
///
/// Light theme: the card's own colour with ink outlines and hard ink shadows (the Faelen look).
/// Dark theme: pastel fills and white outlines glare on a dark page, so the colour is tuned
/// (pale ones a touch deeper, deep ones lifted until they read), outlines take the colour's own tint, and the hard
/// shadow becomes a deep shade of the same hue.
class Tone {
  const Tone({required this.main, required this.on, required this.soft, required this.line, required this.shade, required this.dark});

  /// Fill for the main action and the selected state.
  final Color main;

  /// Text and icons on [main].
  final Color on;

  /// A quiet wash of the hue for secondary buttons and unselected tiles.
  final Color soft;

  /// Outline colour and hard-shadow colour.
  final Color line, shade;
  final bool dark;

  static Tone from(CardSkin skin, Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final p = dark ? Palette.dark : Palette.light;
    var main = skin.face;
    if (dark) {
      final hsl = HSLColor.fromColor(skin.face);
      main = skin.face.computeLuminance() < 0.2
          ? hsl.withLightness(hsl.lightness < 0.6 ? 0.6 : hsl.lightness).withSaturation(hsl.saturation.clamp(0.0, 0.78)).toColor()
          : hsl.withLightness(hsl.lightness * 0.93).withSaturation(hsl.saturation * 0.92).toColor();
    }
    return Tone(
      main: main,
      on: readableOn(main),
      soft: Color.alphaBlend(main.withValues(alpha: dark ? 0.17 : 0.22), p.bg),
      line: dark ? Color.lerp(p.bg, main, 0.72)! : p.ink,
      shade: dark ? HSLColor.fromColor(main).withLightness(HSLColor.fromColor(main).lightness * 0.42).toColor() : p.ink,
      dark: dark,
    );
  }

  /// The tone of the card chosen in the Budget (or the first skin when none is).
  static Tone of(BuildContext context) {
    final store = Provider.of<BudgetStore?>(context);
    final skin = store?.selected?.skinData ?? cardSkins.first;
    return from(skin, Theme.of(context).brightness);
  }
}

/// Dark ink or white, whichever reads better on [bg].
Color readableOn(Color bg) {
  double contrast(Color a, Color b) {
    final l1 = a.computeLuminance(), l2 = b.computeLuminance();
    return (l1 > l2 ? l1 + 0.05 : l2 + 0.05) / (l1 > l2 ? l2 + 0.05 : l1 + 0.05);
  }

  return contrast(bg, onTile) >= contrast(bg, Colors.white) ? onTile : Colors.white;
}

/// Like [brutal], but the outline and hard shadow follow the [tone] in the dark theme.
BoxDecoration toneBox(BuildContext context, {Tone? tone, Color? color, double radius = 16, double shadow = 3, double border = 2}) {
  final p = Palette.of(context);
  final t = tone ?? Tone.of(context);
  return BoxDecoration(
    color: color ?? p.card,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: t.line, width: border),
    boxShadow: shadow == 0 ? null : [BoxShadow(color: t.shade, offset: Offset(0, shadow), blurRadius: 0)],
  );
}

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
  const ChoiceTile({super.key, required this.label, required this.icon, required this.color, required this.on, required this.onTap, this.height = 54, this.tone});
  final String label;
  final IconData icon;
  final Color color;
  final bool on;
  final VoidCallback onTap;
  final double height;
  final Tone? tone;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final tone = this.tone ?? Tone.of(context);
    final fill = tone.dark ? Color.lerp(color, p.bg, 0.12)! : color;
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
                ? toneBox(context, tone: tone, color: fill, radius: 14, shadow: 3)
                : BoxDecoration(color: color.withValues(alpha: tone.dark ? 0.16 : 0.22), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.transparent, width: 2)),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 21, color: on ? onTile : p.text),
              const SizedBox(height: 2),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: on ? FontWeight.w800 : FontWeight.w600, color: on ? onTile : p.text)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// A short bold label above a form control. [dense] tightens the space for compact forms.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key, this.dense = false});
  final String text;
  final bool dense;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: dense ? 12 : 18, bottom: dense ? 6 : 8),
        child: Text(text, style: heading(dense ? 13 : 14, weight: FontWeight.w700, color: Palette.of(context).text)),
      );
}

/// A pill that is on or off (used for card kinds, networks and filters). On = the tone's colour.
class PillChoice extends StatelessWidget {
  const PillChoice({super.key, required this.label, required this.on, required this.onTap, this.dot, this.tone, this.compact = false});
  final String label;
  final bool on;
  final VoidCallback onTap;
  final Color? dot;
  final Tone? tone;

  /// Smaller, for rows that must stay on one line on a narrow phone.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final t = tone ?? Tone.of(context);
    return Semantics(
      button: true,
      selected: on,
      label: label,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            constraints: BoxConstraints(minHeight: compact ? 38 : 40),
            padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14),
            decoration: on ? toneBox(context, tone: t, color: t.main, radius: 12, shadow: 2) : BoxDecoration(color: t.soft, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.transparent, width: 2)),
            child: Row(mainAxisSize: compact ? MainAxisSize.max : MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
              if (dot != null) ...[
                Container(width: 12, height: 12, decoration: BoxDecoration(color: dot, shape: BoxShape.circle, border: Border.all(color: on ? t.on : p.ink.withValues(alpha: 0.5), width: 1.5))),
                const SizedBox(width: 7),
              ],
              Flexible(
                child: compact
                    ? FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1, style: TextStyle(fontWeight: on ? FontWeight.w800 : FontWeight.w600, fontSize: 13.5, color: on ? t.on : p.text)))
                    : Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: on ? FontWeight.w800 : FontWeight.w600, fontSize: 13.5, color: on ? t.on : p.text)),
              ),
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
    final tone = Tone.of(context);
    return Container(
      width: size,
      height: size,
      decoration: toneBox(context, tone: tone, color: tone.dark ? Color.lerp(color, Palette.dark.bg, 0.12) : color, radius: size * 0.3, shadow: 0, border: 1.5),
      child: Icon(icon, size: size * 0.5, color: onTile),
    );
  }
}

/// The style of a sheet's main action: filled in the tone, with its outline.
ButtonStyle toneButton(BuildContext context, {double height = 50}) {
  final t = Tone.of(context);
  return FilledButton.styleFrom(backgroundColor: t.main, foregroundColor: t.on, minimumSize: Size.fromHeight(height), side: BorderSide(color: t.line, width: 2));
}
