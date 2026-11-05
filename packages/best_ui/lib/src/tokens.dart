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
  static const double sheet = 28;
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

  /// The name of a screen: "Library", "The Database".
  static TextStyle pageTitle(BuildContext context) {
    final theme = Theme.of(context);
    return theme.textTheme.displaySmall!.copyWith(
      fontSize: 30,
      fontWeight: FontWeight.w800,
      height: 1.08,
      letterSpacing: tracking(context, -0.6),
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

/// Font families for the enhanced three-family typography system.
///
/// - [heading]: Cairo — Arabic-optimized geometric face for titles and tabs.
/// - [reading]: Tajawal — warm, highly legible face for body text and synopses.
/// - [mono]: JetBrains Mono — tabular digits for live values that never reflow.
abstract final class BestFontFamily {
  static const String heading = 'packages/best_ui/BestHeading';
  static const String reading = 'packages/best_ui/BestReading';
  static const String mono = 'packages/best_ui/BestMono';
}
