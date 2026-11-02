import 'package:flutter/material.dart';

/// A small, warm editorial palette: ink and paper, one ember accent and one
/// brass highlight, with jade kept only for progress and offline state.
///
/// Artwork is the only thing allowed to be loud. The chrome is printed in ink,
/// ember and brass so a shelf of covers reads like a magazine spread rather than
/// a storefront.
abstract final class BestColors {
  static const Color ink = Color(0xFF0B0A08);
  static const Color inkRaised = Color(0xFF13110D);
  static const Color inkElevated = Color(0xFF1B1812);
  static const Color inkLine = Color(0xFF2C261B);
  static const Color paper = Color(0xFFF4EDDF);
  static const Color paperRaised = Color(0xFFFBF6EA);
  static const Color paperLine = Color(0xFFDDD2BD);
  static const Color cinnabar = Color(0xFFE05A3C);
  static const Color cinnabarDeep = Color(0xFFA93620);
  static const Color brass = Color(0xFFCFA85A);
  static const Color gold = brass;
  static const Color jade = Color(0xFF57B394);
  static const Color jadeDeep = Color(0xFF2F735C);
  static const Color danger = Color(0xFFE2604D);
  static const Color rankGold = brass;
  static const Color rankSilver = Color(0xFFB9C2CF);
  static const Color rankBronze = Color(0xFFC98A5B);

  /// The signature gradient: ember into brass. Used on the mark and the
  /// spotlight seal, never as a page background.
  static const List<Color> aurora = <Color>[cinnabar, brass];
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

/// Sharper than the previous build: an editorial page, not a rounded app card.
abstract final class BestRadius {
  static const double sm = 6;
  static const double md = 10;
  static const double lg = 16;
  static const double xl = 22;
  static const double pill = 999;
}

abstract final class BestMotion {
  static const Duration fast = Duration(milliseconds: 140);
  static const Duration normal = Duration(milliseconds: 220);
  static const Curve curve = Curves.easeOutCubic;
}
