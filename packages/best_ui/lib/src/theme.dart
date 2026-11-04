import 'package:flutter/material.dart';

import 'tokens.dart';

/// One builder for both brightnesses, tuned for a poster-first reading app.
///
/// Headings use the UI face, not the editorial serif: a catalogue screen is a
/// product surface, and mixing a display serif into every chapter row made the
/// old build feel like a magazine that happened to scroll. Amiri is still
/// bundled for the wordmark and long-form quotes.
///
/// The component themes below are not decoration: they are the reason a new
/// screen can be written with plain `FilledButton`, `Chip` and `IconButton`
/// and still land on the app's 48 dp target, radius and colour. A screen that
/// hand-rolls those values is the thing this file exists to prevent.
ThemeData bestTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: BestColors.blue,
    brightness: brightness,
  ).copyWith(
    primary: isDark ? BestColors.blue : BestColors.blueDeep,
    onPrimary: Colors.white,
    primaryContainer: isDark
        ? BestColors.blue.withValues(alpha: 0.20)
        : BestColors.blue.withValues(alpha: 0.12),
    onPrimaryContainer: isDark ? BestColors.blueSoft : BestColors.blueDeep,
    secondary: isDark ? BestColors.cyan : const Color(0xFF0891B2),
    onSecondary: isDark ? BestColors.ink : Colors.white,
    secondaryContainer: BestColors.cyan.withValues(alpha: 0.16),
    onSecondaryContainer: isDark ? BestColors.cyan : const Color(0xFF155E75),
    tertiary: BestColors.jade,
    onTertiary: BestColors.ink,
    surface: isDark ? BestColors.ink : BestColors.paper,
    onSurface: isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A),
    onSurfaceVariant:
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF5A6B80),
    surfaceContainerLow: isDark ? BestColors.inkRaised : BestColors.paperRaised,
    surfaceContainer: isDark ? BestColors.inkElevated : const Color(0xFFF1F5F9),
    surfaceContainerHigh: isDark ? BestColors.inkLift : const Color(0xFFE9EFF7),
    surfaceContainerHighest:
        isDark ? const Color(0xFF1B2942) : BestColors.paperSunken,
    outline: isDark ? const Color(0xFF3B4A63) : const Color(0xFF94A3B8),
    outlineVariant: isDark ? BestColors.inkLine : BestColors.paperLine,
    error: BestColors.danger,
    onError: isDark ? BestColors.ink : Colors.white,
  );

  final base = ThemeData(
    colorScheme: scheme,
    brightness: brightness,
    useMaterial3: true,
    // InkSparkle compiles a fragment shader on first splash. That shader is
    // missing in headless widget tests and some older devices, so the app uses
    // the classic ripple: same feedback, no runtime shader dependency.
    splashFactory: InkRipple.splashFactory,
    fontFamily: BestFonts.text,
  );

  final text = base.textTheme
      .apply(
        fontFamily: BestFonts.text,
        fontFamilyFallback: const ['Noto Sans Arabic', 'Noto Naskh Arabic'],
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      )
      .copyWith(
        displayLarge: base.textTheme.displayLarge?.copyWith(
          fontFamily: BestFonts.text,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.2,
          height: 1.0,
        ),
        displayMedium: base.textTheme.displayMedium?.copyWith(
          fontFamily: BestFonts.text,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.8,
          height: 1.02,
        ),
        displaySmall: base.textTheme.displaySmall?.copyWith(
          fontFamily: BestFonts.text,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
          height: 1.06,
        ),
        headlineLarge: base.textTheme.headlineLarge?.copyWith(
          fontFamily: BestFonts.text,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
          height: 1.08,
        ),
        headlineMedium: base.textTheme.headlineMedium?.copyWith(
          fontFamily: BestFonts.text,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
          height: 1.1,
        ),
        headlineSmall: base.textTheme.headlineSmall?.copyWith(
          fontFamily: BestFonts.text,
          fontWeight: FontWeight.w700,
          height: 1.14,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontFamily: BestFonts.text,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          height: 1.18,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
          height: 1.25,
        ),
        titleSmall: base.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(height: 1.6),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.55),
        bodySmall: base.textTheme.bodySmall?.copyWith(height: 1.5),
        labelLarge: base.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
        labelMedium: base.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
        labelSmall: base.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.15,
        ),
      );

  return base.copyWith(
    textTheme: text,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      foregroundColor: scheme.onSurface,
      titleTextStyle: text.titleLarge,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor:
          isDark ? const Color(0xFF0A101C) : BestColors.paperRaised,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.primary.withValues(alpha: 0.18),
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BestRadius.pill),
      ),
      height: 68,
      elevation: 0,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>(
        (Set<WidgetState> states) {
          final selected = states.contains(WidgetState.selected);
          return text.labelSmall?.copyWith(
            fontSize: 10,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
            letterSpacing: 0,
          );
        },
      ),
      iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>(
        (Set<WidgetState> states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 23,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          );
        },
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? BestColors.inkRaised : BestColors.paperRaised,
      hintStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: BestSpace.lg,
        vertical: BestSpace.md + 2,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(BestRadius.md),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(BestRadius.md),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(BestRadius.md),
        borderSide: BorderSide(color: scheme.primary, width: 1.4),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, BestLayout.minTouch),
        padding: const EdgeInsets.symmetric(horizontal: BestSpace.xl),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BestRadius.md),
        ),
        textStyle: text.labelLarge?.copyWith(fontSize: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, BestLayout.minTouch),
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BestRadius.md),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: scheme.primary,
        minimumSize: const Size(0, BestLayout.minTouch),
        textStyle: text.labelLarge,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        // A 48 dp target even when the icon is 20: the app is used one-handed
        // on a bus, and a 32 dp hit box is a miss.
        minimumSize: const Size(BestLayout.minTouch, BestLayout.minTouch),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BestRadius.md),
        ),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: BestSpace.md),
        textStyle: text.labelMedium,
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BestRadius.pill),
        ),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: isDark ? BestColors.inkElevated : BestColors.paperRaised,
      selectedColor: scheme.primaryContainer,
      shape: const StadiumBorder(),
      side: BorderSide(color: scheme.outlineVariant),
      labelStyle: text.labelMedium,
      padding: const EdgeInsets.symmetric(horizontal: BestSpace.md),
      labelPadding: const EdgeInsets.symmetric(horizontal: BestSpace.xs),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BestRadius.lg),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: scheme.surfaceContainerLow,
      showDragHandle: true,
      dragHandleColor: scheme.outline,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(BestRadius.xl),
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BestRadius.lg),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor:
          isDark ? BestColors.inkElevated : const Color(0xFF0F172A),
      contentTextStyle: text.bodyMedium?.copyWith(color: Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BestRadius.sm),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: scheme.surfaceContainerHighest,
      circularTrackColor: scheme.surfaceContainerHighest,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: scheme.onSurfaceVariant,
      textColor: scheme.onSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BestRadius.sm),
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: scheme.primary,
      selectionColor: scheme.primary.withValues(alpha: 0.28),
      selectionHandleColor: scheme.primary,
    ),
  );
}
