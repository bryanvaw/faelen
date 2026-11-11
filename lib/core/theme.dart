import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// One look for every module: neutral surfaces (a faint ink tint over the page, no outline), colour
/// only for the action and the selected state, and the bold ink outline with its hard shadow kept
/// for the two things that carry the brand: the cat marks and the Add button. No gradients.
class Palette {
  const Palette._({
    required this.bg,
    required this.card,
    required this.field,
    required this.ink,
    required this.primary,
    required this.onPrimary,
    required this.text,
    required this.subText,
    required this.outline,
  });

  final Color bg, card, field, ink, primary, onPrimary, text, subText, outline;

  static const light = Palette._(
    bg: Colors.white,
    card: Colors.white,
    field: Colors.white,
    ink: Color(0xFF111111), // outlines + hard shadows
    primary: Color(0xFFF26B50), // coral
    onPrimary: Color(0xFF111111), // ink on coral = 6.6:1
    text: Color(0xFF111111),
    subText: Color(0xFF5F5F5F),
    outline: Color(0xFFE6E6E6),
  );

  static const dark = Palette._(
    bg: Color(0xFF121212),
    card: Color(0xFF1E1E20),
    field: Color(0xFF1E1E20),
    ink: Color(0xFFF2F2F2),
    primary: Color(0xFFFF7A5F),
    onPrimary: Color(0xFF111111),
    text: Color(0xFFF2F2F2),
    subText: Color(0xFFA6A6A6),
    outline: Color(0xFF3A3A3D),
  );

  static Palette of(BuildContext c) => Theme.of(c).brightness == Brightness.dark ? dark : light;
}

/// Text that sits on the bright status tiles. Always dark, in both themes.
const onTile = Color(0xFF111111);

/// The neutral surface of cards, rows, fields and tiles: a faint ink tint over the page. A higher
/// [strength] is for something sitting on such a surface (a button inside a card).
Color quiet(Palette p, [double strength = 0.06]) => Color.alphaBlend(p.ink.withValues(alpha: strength), p.bg);

/// Card / tile decoration. By default a quiet filled surface with no outline: the page colour (or
/// no colour) becomes the neutral tint, any other colour is kept as a flat fill. With [strong] it
/// is the brand treatment, a bold ink outline on a hard offset shadow; only the cat marks and the
/// Add button use it. [shadow] and [border] only apply to the strong form.
BoxDecoration brutal(Palette p, {Color? color, double radius = 18, double shadow = 4, double border = 2, bool strong = false}) {
  if (!strong) {
    final plain = color == null || color == p.card || color == p.field || color == p.bg;
    return BoxDecoration(color: plain ? quiet(p) : color, borderRadius: BorderRadius.circular(radius));
  }
  return BoxDecoration(
    color: color ?? p.card,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: p.ink, width: border),
    boxShadow: [BoxShadow(color: p.ink, offset: Offset(0, shadow), blurRadius: 0)],
  );
}

/// Outfit for headings / numbers; DM Sans (the theme default) for everything else.
TextStyle heading(double size, {FontWeight weight = FontWeight.w700, Color? color, double? height}) =>
    GoogleFonts.outfit(fontSize: size, fontWeight: weight, color: color, height: height);

ThemeData buildTheme(Brightness b) {
  final p = b == Brightness.dark ? Palette.dark : Palette.light;
  final scheme = ColorScheme.fromSeed(seedColor: p.primary, brightness: b).copyWith(
    primary: p.primary,
    onPrimary: p.onPrimary,
    surface: p.card,
    onSurface: p.text,
    onSurfaceVariant: p.subText,
    outline: p.outline,
    surfaceContainerHighest: p.field,
  );

  // Fields are quiet filled surfaces; the outline appears only with focus or an error.
  OutlineInputBorder border([Color? c, double w = 2]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: c == null ? BorderSide.none : BorderSide(color: c, width: w),
      );

  final base = GoogleFonts.dmSansTextTheme(ThemeData(brightness: b).textTheme)
      .apply(bodyColor: p.text, displayColor: p.text);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.transparent,
    textTheme: base.copyWith(
      headlineSmall: heading(24, weight: FontWeight.w700, color: p.text),
      titleLarge: heading(20, weight: FontWeight.w700, color: p.text),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: p.card,
      indicatorColor: p.primary,
      selectedIconTheme: IconThemeData(color: p.onPrimary),
      unselectedIconTheme: IconThemeData(color: p.subText),
      selectedLabelTextStyle: TextStyle(color: p.text, fontWeight: FontWeight.w800, fontSize: 12),
      unselectedLabelTextStyle: TextStyle(color: p.subText, fontWeight: FontWeight.w600, fontSize: 12),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: quiet(p),
      border: border(),
      enabledBorder: border(),
      focusedBorder: border(p.primary),
      errorBorder: border(scheme.error),
      focusedErrorBorder: border(scheme.error, 3),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.bg,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 600), // stays centred on tablets/desktop
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.card,
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: p.outline),
      ),
      textStyle: TextStyle(color: p.text, fontWeight: FontWeight.w700, fontSize: 14),
      menuPadding: const EdgeInsets.symmetric(vertical: 6),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.primary,
        foregroundColor: p.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
      ),
    ),
    // The quiet partner of a filled button (Cancel): neutral, never the accent colour, which would
    // read as the main or the destructive choice.
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.text,
        backgroundColor: quiet(p),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.text,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
  );
}
