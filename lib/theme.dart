import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'models/media_entry.dart';

/// Flat "outlined" look: off-white page, white cards with a bold ink outline and a
/// hard offset shadow, coral accent and bright status colours. No gradients.
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

/// Card / tile decoration: bold outline plus a hard, un-blurred offset shadow.
BoxDecoration brutal(Palette p, {Color? color, double radius = 18, double shadow = 4, double border = 2}) =>
    BoxDecoration(
      color: color ?? p.card,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: p.ink, width: border),
      boxShadow: [BoxShadow(color: p.ink, offset: Offset(0, shadow), blurRadius: 0)],
    );

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

  OutlineInputBorder border(Color c, [double w = 2]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c, width: w),
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
      fillColor: p.field,
      border: border(p.ink),
      enabledBorder: border(p.ink),
      focusedBorder: border(p.primary, 3),
      errorBorder: border(scheme.error),
      focusedErrorBorder: border(scheme.error, 3),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.bg,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 600), // stays centred on tablets/desktop
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        side: BorderSide(color: p.ink, width: 2),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: p.ink, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.primary,
        foregroundColor: p.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: p.ink, width: 2)),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
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

/// Bright, flat status colours (also used for the progress ring and the filter tiles).
Color statusColor(Status s) => switch (s) {
      Status.watching => const Color(0xFF5E9BFA), // blue
      Status.planToWatch => const Color(0xFFFFC93C), // yellow
      Status.completed => const Color(0xFF4CC2BB), // teal
      Status.onHold => const Color(0xFFB99BFF), // lilac
      Status.dropped => const Color(0xFFF26B50), // coral
    };

IconData statusIcon(Status s) => switch (s) {
      Status.watching => Icons.play_arrow_rounded,
      Status.planToWatch => Icons.schedule_rounded,
      Status.completed => Icons.check_rounded,
      Status.onHold => Icons.pause_rounded,
      Status.dropped => Icons.close_rounded,
    };

IconData typeIcon(MediaType t) => switch (t) {
      MediaType.manhwa => Icons.menu_book_rounded,
      MediaType.anime => Icons.live_tv_rounded,
      MediaType.movie => Icons.movie_rounded,
      MediaType.drama => Icons.theater_comedy_rounded,
    };
