import 'package:flutter/material.dart';

/// The palette is deliberately small: two grounds, one signature accent, one
/// warm highlight and one alert. A media app competes with its own artwork; the
/// chrome must not.
///
/// The identity is "ink and jade": a near-black canvas, a cool jade for action
/// and progress, vermilion only for live/new, and a muted gold for ratings and
/// ranks. HikariManga's blue-on-black proved the structure; this palette keeps
/// Best recognisable beside it.
abstract final class BestColors {
  static const Color ink = Color(0xFF07080B);
  static const Color inkRaised = Color(0xFF101218);
  static const Color inkElevated = Color(0xFF161922);
  static const Color inkLine = Color(0xFF232733);
  static const Color paper = Color(0xFFF7F5F0);
  static const Color paperRaised = Color(0xFFFFFFFF);
  static const Color paperLine = Color(0xFFE6E1D7);
  static const Color vermilion = Color(0xFFF05A3C);
  static const Color gold = Color(0xFFE8B45F);
  static const Color jade = Color(0xFF3BD3A4);
  static const Color jadeDeep = Color(0xFF0E7A5C);
  static const Color danger = Color(0xFFE5544B);
  static const Color rankGold = Color(0xFFE8B45F);
  static const Color rankSilver = Color(0xFFB9C2CF);
  static const Color rankBronze = Color(0xFFC98A5B);

  /// The two-stop signature gradient. Used on the wordmark, the spotlight art
  /// and the primary button; never as a page background.
  static const List<Color> aurora = <Color>[jade, gold];
}

abstract final class BestSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

abstract final class BestRadius {
  static const double sm = 12;
  static const double md = 18;
  static const double lg = 26;
  static const double xl = 34;
  static const double pill = 999;
}

abstract final class BestMotion {
  static const Duration fast = Duration(milliseconds: 140);
  static const Duration normal = Duration(milliseconds: 220);
  static const Curve curve = Curves.easeOutCubic;
}
