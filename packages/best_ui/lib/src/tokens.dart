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
  // Night surfaces, darkest first. `inkDeep` is the page behind a hero;
  // `inkLift` is the surface a selected row or chip sits on.
  static const Color inkDeep = Color(0xFF05080F);
  static const Color ink = Color(0xFF070B14);
  static const Color inkRaised = Color(0xFF0C1322);
  static const Color inkElevated = Color(0xFF111A2B);
  static const Color inkLift = Color(0xFF17233A);
  static const Color inkLine = Color(0xFF1D2940);

  // Day surfaces, for the light theme. `paperSunken` is the well a search
  // field or an unselected chip sits in.
  static const Color paper = Color(0xFFF5F7FA);
  static const Color paperRaised = Color(0xFFFFFFFF);
  static const Color paperSunken = Color(0xFFEBF0F7);
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

  /// The signature gradient: action blue into cyan. Used on the mark, the
  /// selected destination and the progress rule — never as a page background.
  static const List<Color> aurora = <Color>[blue, cyan];

  /// The scrim under a hero: transparent at the artwork, solid at the text.
  static const List<Color> heroScrim = <Color>[
    Color(0x00050810),
    Color(0xB3050810),
    Color(0xF5050810),
  ];
}

/// Fonts declared by a package are registered under a package-prefixed family
/// name. Asking for the bare name silently falls back to the system face, so
/// every style goes through these constants.
abstract final class BestFonts {
  static const String display = 'packages/best_ui/BestDisplay';
  static const String text = 'packages/best_ui/BestText';
}

abstract final class BestSpace {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double huge = 44;
}

/// Softer than the previous build, but not bubbly: a poster grid needs a
/// radius small enough that nine covers still read as a grid.
abstract final class BestRadius {
  static const double xs = 6;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double pill = 999;
}

/// One rhythm for the whole app. `fast` is a hover/press, `normal` a chip or a
/// progress rule, `slow` a sheet or a page reveal. `emphasized` is the curve
/// that makes a short move feel deliberate instead of abrupt.
abstract final class BestMotion {
  static const Duration fast = Duration(milliseconds: 140);
  static const Duration normal = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 340);
  static const Curve curve = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeOutQuint;
  static const Curve enter = Curves.easeOutBack;

  /// The gap between two cards in a staggered reveal.
  static const Duration stagger = Duration(milliseconds: 55);
}

/// Minimum target size shared by the component themes.
abstract final class BestLayout {
  static const double minTouch = 48;
}

/// The app's type voice, in one place.
///
/// Every screen asks for a *role* (`sectionTitle`, `meta`) instead of copying
/// a size and a weight. Tracking is zero in Arabic: letter spacing on a joined
/// script opens gaps inside words, which reads as a typo, not as a headline.
abstract final class BestType {
  static bool _rtl(BuildContext context) =>
      Directionality.maybeOf(context) == TextDirection.rtl;

  static double tracking(BuildContext context, double value) =>
      _rtl(context) ? 0 : value;

  /// The name of a screen: "Library", "The Database".
  static TextStyle pageTitle(BuildContext context) {
    final theme = Theme.of(context);
    return theme.textTheme.displaySmall!.copyWith(
      fontSize: 30,
      fontWeight: FontWeight.w800,
      height: 1.08,
      letterSpacing: tracking(context, -0.8),
    );
  }

  /// The name of a section inside a page.
  static TextStyle sectionTitle(BuildContext context) {
    final theme = Theme.of(context);
    return theme.textTheme.titleMedium!.copyWith(
      fontSize: 17,
      fontWeight: FontWeight.w800,
      height: 1.2,
      letterSpacing: tracking(context, -0.2),
    );
  }

  /// The title of a work on a card.
  static TextStyle cardTitle(BuildContext context) {
    final theme = Theme.of(context);
    return theme.textTheme.titleSmall!.copyWith(
      fontSize: 13.5,
      fontWeight: FontWeight.w700,
      height: 1.25,
      letterSpacing: 0,
    );
  }

  /// One muted line under a title: kind, author, progress.
  static TextStyle meta(BuildContext context) {
    final theme = Theme.of(context);
    return theme.textTheme.labelSmall!.copyWith(
      fontSize: 10.5,
      fontWeight: FontWeight.w500,
      height: 1.3,
      color: theme.colorScheme.onSurfaceVariant,
      letterSpacing: 0,
    );
  }

  /// The small capitalised label above a title. Case only applies to Latin
  /// scripts, so the caller passes the string through [eyebrowCase].
  static TextStyle eyebrow(BuildContext context) {
    final theme = Theme.of(context);
    return theme.textTheme.labelSmall!.copyWith(
      fontSize: 9.5,
      fontWeight: FontWeight.w800,
      height: 1.1,
      letterSpacing: tracking(context, 1.1),
    );
  }

  /// Uppercasing an Arabic label changes nothing visually but breaks the
  /// shaping assumptions of a few fonts, so it is skipped in RTL.
  static String eyebrowCase(BuildContext context, String value) =>
      _rtl(context) ? value : value.toUpperCase();

  /// The one line of body copy a card is allowed.
  static TextStyle body(BuildContext context) {
    final theme = Theme.of(context);
    return theme.textTheme.bodySmall!.copyWith(
      fontSize: 11.5,
      height: 1.5,
      color: theme.colorScheme.onSurfaceVariant,
    );
  }
}
