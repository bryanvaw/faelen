import 'package:flutter/material.dart';

import 'models/media_entry.dart';

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

/// Flat accent per media type (bottom bar chips).
Color typeColor(MediaType t) => switch (t) {
      MediaType.manhwa => const Color(0xFFB99BFF), // lilac
      MediaType.anime => const Color(0xFF5E9BFA), // blue
      MediaType.movie => const Color(0xFFFFC93C), // yellow
      MediaType.drama => const Color(0xFF4CC2BB), // teal
    };

/// Ratings are stored 0-10 (0 = unrated) but shown as 5 stars with half steps.
String ratingLabel(int r) => r.isEven ? '${r ~/ 2}' : '${r / 2}';
