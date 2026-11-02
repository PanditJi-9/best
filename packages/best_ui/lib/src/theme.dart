import 'package:flutter/material.dart';

import 'tokens.dart';

/// One builder for both brightnesses. The bundled faces are deliberate:
/// [BestDisplay] is Amiri (editorial Arabic/Latin serif) and [BestText] is
/// IBM Plex Sans Arabic (a workhorse for UI, metadata and long Arabic prose).
/// Keeping both in the design package means every screen gets the same voice.
ThemeData bestTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: BestColors.cinnabar,
        brightness: brightness,
      ).copyWith(
        primary: isDark ? BestColors.cinnabar : BestColors.cinnabarDeep,
        onPrimary: isDark ? BestColors.ink : Colors.white,
        primaryContainer: isDark
            ? BestColors.cinnabar.withValues(alpha: 0.18)
            : BestColors.cinnabar.withValues(alpha: 0.14),
        onPrimaryContainer: isDark
            ? BestColors.cinnabar
            : BestColors.cinnabarDeep,
        secondary: BestColors.brass,
        onSecondary: BestColors.ink,
        secondaryContainer: BestColors.brass.withValues(alpha: 0.16),
        onSecondaryContainer: isDark
            ? BestColors.brass
            : const Color(0xFF5B4317),
        tertiary: BestColors.jade,
        onTertiary: BestColors.ink,
        surface: isDark ? BestColors.ink : BestColors.paper,
        onSurface: isDark ? const Color(0xFFF3EADB) : const Color(0xFF191510),
        onSurfaceVariant: isDark
            ? const Color(0xFFA89D8A)
            : const Color(0xFF655C4D),
        surfaceContainerLow: isDark
            ? BestColors.inkRaised
            : BestColors.paperRaised,
        surfaceContainer: isDark
            ? BestColors.inkElevated
            : const Color(0xFFEFE6D6),
        surfaceContainerHigh: isDark
            ? const Color(0xFF211C14)
            : const Color(0xFFE8DECC),
        surfaceContainerHighest: isDark
            ? const Color(0xFF2A241A)
            : const Color(0xFFE2D6C2),
        outline: isDark ? const Color(0xFF6F6554) : const Color(0xFF8C806B),
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
    fontFamily: 'BestText',
  );

  final text = base.textTheme
      .apply(
        fontFamily: 'BestText',
        fontFamilyFallback: const ['Noto Sans Arabic', 'Noto Naskh Arabic'],
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      )
      .copyWith(
        displayLarge: base.textTheme.displayLarge?.copyWith(
          fontFamily: 'BestDisplay',
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          height: 0.96,
        ),
        displayMedium: base.textTheme.displayMedium?.copyWith(
          fontFamily: 'BestDisplay',
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          height: 0.98,
        ),
        displaySmall: base.textTheme.displaySmall?.copyWith(
          fontFamily: 'BestDisplay',
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          height: 1,
        ),
        headlineLarge: base.textTheme.headlineLarge?.copyWith(
          fontFamily: 'BestDisplay',
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          height: 1.05,
        ),
        headlineMedium: base.textTheme.headlineMedium?.copyWith(
          fontFamily: 'BestDisplay',
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          height: 1.08,
        ),
        headlineSmall: base.textTheme.headlineSmall?.copyWith(
          fontFamily: 'BestDisplay',
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          height: 1.12,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontFamily: 'BestDisplay',
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          height: 1.15,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
        titleSmall: base.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(height: 1.7),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.65),
        bodySmall: base.textTheme.bodySmall?.copyWith(height: 1.55),
        labelLarge: base.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
        labelMedium: base.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
        labelSmall: base.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.25,
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
      indicatorColor: scheme.primary.withValues(alpha: 0.16),
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BestRadius.sm),
      ),
      height: 64,
      elevation: 0,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return text.labelSmall?.copyWith(
          fontSize: 10,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? scheme.primary : scheme.onSurfaceVariant,
          letterSpacing: 0,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          size: 22,
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
          borderRadius: BorderRadius.circular(BestRadius.sm),
        ),
        textStyle: text.labelLarge?.copyWith(fontSize: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BestRadius.sm),
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
        borderRadius: BorderRadius.circular(BestRadius.sm),
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
