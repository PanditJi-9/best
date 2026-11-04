import 'package:flutter/material.dart';

/// A deep navy reading room with one electric blue accent.
///
/// The palette is deliberately closer to a streaming app than to a printed
/// magazine: near-black blue surfaces, a single saturated action colour, and
/// amber reserved for scores. Covers carry the colour; the chrome stays quiet.
///
/// The historical names (`ink`, `cinnabar`, `brass`) are kept because every
/// screen and test already speaks them. They now describe the blue system:
/// `cinnabar` is the action blue, `brass` is the soft-blue accent, and the
/// amber used for ranks has its own token.
abstract final class BestColors {
  // Night surfaces.
  static const Color ink = Color(0xFF070B14);
  static const Color inkRaised = Color(0xFF0C1322);
  static const Color inkElevated = Color(0xFF111A2B);
  static const Color inkLine = Color(0xFF1D2940);

  // Day surfaces, for the light theme.
  static const Color paper = Color(0xFFF5F7FA);
  static const Color paperRaised = Color(0xFFFFFFFF);
  static const Color paperLine = Color(0xFFE2E8F0);

  // The action colour.
  static const Color blue = Color(0xFF3B82F6);
  static const Color blueDeep = Color(0xFF2563EB);
  static const Color blueSoft = Color(0xFF60A5FA);
  static const Color cyan = Color(0xFF22D3EE);

  /// Legacy alias: the primary action colour.
  static const Color cinnabar = blue;
  static const Color cinnabarDeep = blueDeep;

  /// Secondary accent. Soft blue keeps section indices and quiet links in the
  /// same family as the primary action instead of introducing a second hue.
  static const Color brass = Color(0xFF7CA6FF);

  static const Color gold = Color(0xFFF5B942);
  static const Color jade = Color(0xFF34D399);
  static const Color jadeDeep = Color(0xFF059669);
  static const Color danger = Color(0xFFF87171);
  static const Color rankGold = Color(0xFFF5B942);
  static const Color rankSilver = Color(0xFFC7D2E5);
  static const Color rankBronze = Color(0xFFD08A5A);

  /// The signature gradient: action blue into cyan. Used on the mark and the
  /// selected navigation pill, never as a page background.
  static const List<Color> aurora = <Color>[blue, cyan];
}

/// Fonts declared by a package are registered under a package-prefixed family
/// name. Asking for the bare name silently falls back to the system face, so
/// every style goes through these constants.
abstract final class BestFonts {
  static const String display = 'packages/best_ui/BestDisplay';
  static const String text = 'packages/best_ui/BestText';
}

abstract final class BestSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Softer than the previous build, but not bubbly: a poster grid needs a
/// radius small enough that nine covers still read as a grid.
abstract final class BestRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double pill = 999;
}

abstract final class BestMotion {
  static const Duration fast = Duration(milliseconds: 140);
  static const Duration normal = Duration(milliseconds: 220);
  static const Curve curve = Curves.easeOutCubic;
}
