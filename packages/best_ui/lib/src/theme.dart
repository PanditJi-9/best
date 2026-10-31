import 'package:flutter/material.dart';

import 'tokens.dart';

/// One theme builder for both brightnesses so a token cannot drift between the
/// light and dark builds. Platform dynamic color is deliberately off: the
/// palette is the identity, and a wallpaper-derived seed would erase it.
ThemeData bestTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: BestColors.jade,
        brightness: brightness,
      ).copyWith(
        primary: isDark ? BestColors.jade : BestColors.jadeDeep,
        onPrimary: isDark ? BestColors.ink : Colors.white,
        primaryContainer: isDark
            ? BestColors.jade.withValues(alpha: 0.16)
            : BestColors.jade.withValues(alpha: 0.22),
        onPrimaryContainer: isDark ? BestColors.jade : BestColors.jadeDeep,
        secondary: BestColors.vermilion,
        onSecondary: Colors.white,
        tertiary: BestColors.gold,
        surface: isDark ? BestColors.ink : BestColors.paper,
        onSurface: isDark ? const Color(0xFFF4F2ED) : const Color(0xFF14161A),
        onSurfaceVariant: isDark
            ? const Color(0xFF9AA1AE)
            : const Color(0xFF5F6570),
        surfaceContainerLow: isDark
            ? BestColors.inkRaised
            : BestColors.paperRaised,
        surfaceContainer: isDark
            ? BestColors.inkElevated
            : const Color(0xFFF1EDE5),
        surfaceContainerHigh: isDark
            ? const Color(0xFF1B1F29)
            : const Color(0xFFEDE8DF),
        surfaceContainerHighest: isDark
            ? const Color(0xFF222733)
            : const Color(0xFFE9E4DA),
        outlineVariant: isDark ? BestColors.inkLine : BestColors.paperLine,
        error: BestColors.danger,
      );

  final base = ThemeData(
    colorScheme: scheme,
    brightness: brightness,
    useMaterial3: true,
    // InkSparkle compiles a fragment shader on first splash. That shader is
    // missing in headless widget tests and some older devices, so the app uses
    // the classic ripple: same feedback, no runtime shader dependency.
    splashFactory: InkRipple.splashFactory,
  );

  final text = base.textTheme.copyWith(
    displaySmall: base.textTheme.displaySmall?.copyWith(
      fontWeight: FontWeight.w900,
      letterSpacing: -2,
      height: 0.98,
    ),
    headlineMedium: base.textTheme.headlineMedium?.copyWith(
      fontWeight: FontWeight.w900,
      letterSpacing: -1.2,
      height: 1.05,
    ),
    headlineSmall: base.textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: -0.7,
      height: 1.1,
    ),
    titleLarge: base.textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: -0.5,
    ),
    titleMedium: base.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.2,
    ),
    titleSmall: base.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w700,
      height: 1.25,
    ),
    labelLarge: base.textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: 0.2,
    ),
    labelMedium: base.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: 0.3,
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
      backgroundColor: isDark ? BestColors.inkRaised : BestColors.paperRaised,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.primary.withValues(alpha: isDark ? 0.18 : 0.14),
      indicatorShape: const StadiumBorder(),
      height: 74,
      elevation: 0,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return text.labelSmall?.copyWith(
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          color: selected ? scheme.primary : scheme.onSurfaceVariant,
          letterSpacing: 0.2,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          size: 24,
          color: selected ? scheme.primary : scheme.onSurfaceVariant,
        );
      }),
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
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: BestSpace.xl),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BestRadius.pill),
        ),
        textStyle: text.labelLarge?.copyWith(fontSize: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BestRadius.pill),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: scheme.primary,
        textStyle: text.labelLarge,
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: isDark ? BestColors.inkElevated : BestColors.paperRaised,
      selectedColor: scheme.primaryContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BestRadius.pill),
      ),
      side: BorderSide(color: scheme.outlineVariant),
      labelStyle: text.labelMedium,
      padding: const EdgeInsets.symmetric(horizontal: BestSpace.md),
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(BestRadius.lg),
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
      backgroundColor: isDark
          ? BestColors.inkElevated
          : const Color(0xFF231F26),
      contentTextStyle: text.bodyMedium?.copyWith(color: Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BestRadius.md),
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
    ),
  );
}
