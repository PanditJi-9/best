import 'package:flutter/material.dart';

/// "Ink & Ember" — the identity of Best 2.0.
///
/// Warm ink instead of blue-black, one sealed vermilion for action, and amber
/// for editorial accents. Artwork still carries the colour: the chrome is a
/// quiet dark room around a lit page.
///
/// The historical names (`blue`, `cinnabar`, `brass`) are kept because every
/// screen and test already speaks them. They now describe the ember system:
/// `cinnabar` is the action vermilion, `brass` is the warm editorial accent,
/// and the gold used for ranks has its own token.
abstract final class BestColors {
  // Night surfaces, darkest first. `inkDeep` is the page behind a hero;
  // `inkLift` is the surface a selected row or chip sits on.
  static const Color inkDeep = Color(0xFF060508);
  static const Color ink = Color(0xFF0A090D);
  static const Color inkRaised = Color(0xFF121016);
  static const Color inkElevated = Color(0xFF19161E);
  static const Color inkLift = Color(0xFF241F28);
  static const Color inkLine = Color(0xFF2E2733);

  // Day surfaces: warm paper rather than a blue-white office screen.
  // `paperSunken` is the well a search field or an unselected chip sits in.
  static const Color paper = Color(0xFFF7F2E9);
  static const Color paperRaised = Color(0xFFFFFCF7);
  static const Color paperSunken = Color(0xFFEDE4D4);
  static const Color paperLine = Color(0xFFE2D7C4);

  // The seal: the one action colour, warm and unmistakable.
  static const Color ember = Color(0xFFF25B4C);
  static const Color emberDeep = Color(0xFFD63E31);
  static const Color emberSoft = Color(0xFFFF8C7E);

  /// Warm editorial accent: section numerals, quiet links, small marks.
  static const Color amber = Color(0xFFE8A45C);

  // Legacy aliases. Screens written against the old blue system keep working;
  // every value now belongs to the ember family.
  static const Color blue = ember;
  static const Color blueDeep = emberDeep;
  static const Color blueSoft = emberSoft;
  static const Color cyan = amber;
  static const Color cinnabar = ember;
  static const Color cinnabarDeep = emberDeep;
  static const Color brass = Color(0xFFCF8A4B);

  static const Color gold = Color(0xFFF0C266);
  static const Color jade = Color(0xFF45D6A4);
  static const Color jadeDeep = Color(0xFF0E9F72);
  static const Color danger = Color(0xFFFF7A70);
  static const Color rankGold = Color(0xFFF0C266);
  static const Color rankSilver = Color(0xFFCFC8BC);
  static const Color rankBronze = Color(0xFFC08552);

  /// The signature gradient: vermilion into amber. Used on the mark, the
  /// selected destination and the progress rule — never as a page background.
  static const List<Color> aurora = <Color>[ember, amber];

  /// The scrim under a hero: transparent at the artwork, solid at the text.
  static const List<Color> heroScrim = <Color>[
    Color(0x00060508),
    Color(0xB3060508),
    Color(0xF5060508),
  ];
}

/// Fonts declared by a package are registered under a package-prefixed family
/// name. Asking for the bare name silently falls back to the system face, so
/// every style goes through these constants.
abstract final class BestFonts {
  /// Editorial display face: Amiri carries the masthead and page titles.
  static const String display = 'packages/best_ui/BestDisplay';

  /// The working UI face: bilingual, legible at card sizes.
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

/// Sharper than the old build: an editorial page, not a bubbly storefront.
/// The pill exists only for status dots and progress.
abstract final class BestRadius {
  static const double xs = 4;
  static const double sm = 7;
  static const double md = 10;
  static const double lg = 14;
  static const double xl = 20;
  static const double sheet = 26;
  static const double pill = 999;
}

/// One rhythm for the whole app. `fast` is a hover/press, `normal` a chip or a
/// progress rule, `slow` a sheet or a page reveal. `emphasized` is the curve
/// that makes a short move feel deliberate instead of abrupt.
abstract final class BestMotion {
  static const Duration fast = Duration(milliseconds: 130);
  static const Duration normal = Duration(milliseconds: 210);
  static const Duration slow = Duration(milliseconds: 320);
  static const Curve curve = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeOutQuint;
  static const Curve enter = Curves.easeOutBack;

  /// The gap between two cards in a staggered reveal.
  static const Duration stagger = Duration(milliseconds: 55);
}

/// Minimum target size shared by the component themes.
abstract final class BestLayout {
  static const double minTouch = 48;

  /// The horizontal gutter every scrolling page uses. Rails bleed to the
  /// screen edge and re-apply this value to their own first and last item, so
  /// a card is never cut off at an invisible inner margin.
  static const double gutter = 20;

  /// Widest a tab's content column may grow before it is centred.
  static const double maxContentWidth = 1120;
}

/// Reduced-motion aware helpers. A decorative animation asks here first, so a
/// person who turned animations off in system settings gets a still screen.
abstract final class BestMotionPolicy {
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  static Duration of(BuildContext context, Duration value) =>
      reduced(context) ? Duration.zero : value;
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

  /// The name of a screen: "Library", "The Database". Amiri gives a page
  /// title an editorial voice the UI face cannot; Arabic joins cleanly and
  /// Latin reads as a masthead rather than a button.
  static TextStyle pageTitle(BuildContext context) {
    final theme = Theme.of(context);
    return theme.textTheme.displaySmall!.copyWith(
      fontFamily: BestFonts.display,
      fontSize: 34,
      fontWeight: FontWeight.w700,
      height: 1.16,
      letterSpacing: tracking(context, -0.4),
    );
  }

  /// The name of a section inside a page.
  static TextStyle sectionTitle(BuildContext context) {
    final theme = Theme.of(context);
    return theme.textTheme.titleMedium!.copyWith(
      fontSize: 18,
      fontWeight: FontWeight.w800,
      height: 1.2,
      letterSpacing: tracking(context, -0.2),
    );
  }

  /// The title of a work on a card.
  static TextStyle cardTitle(BuildContext context) {
    final theme = Theme.of(context);
    return theme.textTheme.titleSmall!.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w700,
      height: 1.3,
      letterSpacing: 0,
    );
  }

  /// One muted line under a title: kind, author, progress.
  static TextStyle meta(BuildContext context) {
    final theme = Theme.of(context);
    return theme.textTheme.labelSmall!.copyWith(
      fontSize: 11.5,
      fontWeight: FontWeight.w500,
      height: 1.35,
      color: theme.colorScheme.onSurfaceVariant,
      letterSpacing: 0,
    );
  }

  /// The small capitalised label above a title. Case only applies to Latin
  /// scripts, so the caller passes the string through [eyebrowCase].
  static TextStyle eyebrow(BuildContext context) {
    final theme = Theme.of(context);
    return theme.textTheme.labelSmall!.copyWith(
      fontSize: 10.5,
      fontWeight: FontWeight.w800,
      height: 1.15,
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
      fontSize: 12.5,
      height: 1.55,
      color: theme.colorScheme.onSurfaceVariant,
    );
  }
}

/// Opacity vocabulary ported from the Yokai design language.
///
/// Borders stay hairline-quiet and tone containers stay low, so content is
/// always the brightest thing on screen.
abstract final class BestAlpha {
  /// Hairline border: present but not dominant.
  static const double border = 0.16;

  /// A stronger border for active/focused states.
  static const double borderStrong = 0.28;

  /// An accent used only to wash a surface, never to mark an element.
  static const double toneWash = 0.045;

  /// Container behind a tone badge or pill.
  static const double toneContainer = 0.10;

  /// Stronger container for emphasis.
  static const double toneContainerStrong = 0.18;

  /// Disabled elements.
  static const double disabled = 0.38;

  /// Supporting / secondary text.
  static const double supporting = 0.80;

  /// Inner edge highlight along a panel's leading edge.
  static const double edgeLight = 0.22;

  /// Ambient glow behind an accented panel.
  static const double haloGlow = 0.07;
}

/// Semantic tone — never the only carrier of meaning.
///
/// Every component that renders a tone also renders an icon and a text label,
/// so state survives colour blindness, greyscale screenshots and high-contrast
/// modes. Ported from the Yokai design language.
enum BestTone {
  /// Ordinary information.
  neutral,

  /// The screen's own accent — "this is the thing you came here for".
  accent,

  /// Confirmed good: downloaded, in sync, within limits.
  positive,

  /// Needs attention but still working.
  caution,

  /// Failed, blocked or unsafe.
  critical,

  /// Off, unsupported or not available.
  inactive;

  // Fixed hues contrast-checked against both light and dark surfaces.
  // Only accent follows the user's theme.
  static const Color _positiveOnLight = Color(0xFF0B6B4F);
  static const Color _positiveOnDark = Color(0xFF5FD9AC);
  static const Color _cautionOnLight = Color(0xFF8A5200);
  static const Color _cautionOnDark = Color(0xFFFFB86B);
  static const Color _criticalOnLight = Color(0xFF9A1B1B);
  static const Color _criticalOnDark = Color(0xFFFF9A90);

  /// Foreground colour (text, icon, stroke) for this tone.
  Color content(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return switch (this) {
      BestTone.neutral => scheme.onSurfaceVariant,
      BestTone.accent => scheme.primary,
      BestTone.positive => dark ? _positiveOnDark : _positiveOnLight,
      BestTone.caution => dark ? _cautionOnDark : _cautionOnLight,
      BestTone.critical => dark ? _criticalOnDark : _criticalOnLight,
      BestTone.inactive => scheme.outline,
    };
  }

  /// Low-emphasis container behind this tone's content.
  Color container(BuildContext context, {bool strong = false}) =>
      content(context).withValues(
        alpha: strong ? BestAlpha.toneContainerStrong : BestAlpha.toneContainer,
      );

  /// Hairline border for this tone.
  Color border(BuildContext context, {bool strong = false}) =>
      content(context).withValues(
        alpha: strong ? BestAlpha.borderStrong : BestAlpha.border,
      );
}

/// The one card contract: every number lives here so cards cannot drift.
///
/// Ported from the Yokai YokaiCardSpec.
abstract final class BestCardSpec {
  static const double radius = BestRadius.lg;
  static const double borderWidth = 1;
  static const double padding = BestSpace.lg;
  static const double iconContainer = 40;
  static const double iconGlyph = 20;
  static const double gap = BestSpace.sm;
  static const double gapTight = BestSpace.xs;
  static const double minHeight = 92;
  static const double gridSpacing = BestSpace.md;
  static const int titleLines = 2;
  static const int descriptionLines = 2;
  static const double minColumnWidth = 148;
}

/// The one section-header contract.
abstract final class BestSectionSpec {
  /// The accent rule above a section title: width and height.
  static const double accentRuleWidth = 28;
  static const double accentRuleHeight = 4;

  /// Gap between the rule and the title.
  static const double accentRuleGap = BestSpace.sm;

  /// Gap between heading and its supporting line.
  static const double titleGap = BestSpace.xs;

  /// Space before a section heading.
  static const double spaceBefore = BestSpace.xl;

  /// Space after a section heading.
  static const double spaceAfter = BestSpace.md;
}

/// Tabular figure sizes used by metric readouts so digits never reflow.
abstract final class BestMetricType {
  static const double valueLarge = 34;
  static const double valueMedium = 22;
  static const double valueSmall = 16;
}

/// Placeholder rendered instead of a value when there is nothing real to show.
/// Deliberately not "0", not "--%": a zero would be read as a measurement.
const String bestValueUnavailable = '—';

/// Font families for the three-family typography system.
///
/// - [heading]: Cairo — Arabic-optimized geometric face for titles and tabs.
/// - [reading]: Tajawal — warm, highly legible face for body text and synopses.
/// - [mono]: JetBrains Mono — tabular digits for live values that never reflow.
abstract final class BestFontFamily {
  static const String heading = 'packages/best_ui/BestHeading';
  static const String reading = 'packages/best_ui/BestReading';
  static const String mono = 'packages/best_ui/BestMono';
}
