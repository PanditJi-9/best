import 'package:flutter/material.dart';

/// The palette is deliberately small: two grounds, one accent, one warm
/// highlight. A media app competes with its own artwork; the chrome must not.
abstract final class BestColors {
  static const Color ink = Color(0xFF0A0A0F);
  static const Color inkRaised = Color(0xFF14141C);
  static const Color inkLine = Color(0xFF262632);
  static const Color paper = Color(0xFFFAF7F1);
  static const Color paperRaised = Color(0xFFFFFFFF);
  static const Color vermilion = Color(0xFFE4573D);
  static const Color gold = Color(0xFFF0C05A);
  static const Color jade = Color(0xFF2FA37C);
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
  static const double sm = 10;
  static const double md = 16;
  static const double lg = 22;
  static const double pill = 999;
}

abstract final class BestMotion {
  static const Duration fast = Duration(milliseconds: 140);
  static const Duration normal = Duration(milliseconds: 220);
  static const Curve curve = Curves.easeOutCubic;
}
