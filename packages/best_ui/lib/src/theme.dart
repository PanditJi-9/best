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
///
/// Letter spacing is deliberately zero in every text role. Arabic is a
/// first-class language here and Flutter turns off letter joining as soon as
/// `letterSpacing` is non-zero, which breaks the cursive connection inside a
/// word. Latin tracking is added per role through `BestType.tracking`.
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
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
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
          letterSpacing: 0,
          height: 1.0,
        ),
        displayMedium: base.textTheme.displayMedium?.copyWith(
          fontFamily: BestFonts.text,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
          height: 1.02,
        ),
        displaySmall: base.textTheme.displaySmall?.copyWith(
          fontFamily: BestFonts.text,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
          height: 1.06,
        ),
        headlineLarge: base.textTheme.headlineLarge?.copyWith(
          fontFamily: BestFonts.text,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
          height: 1.08,
        ),
        headlineMedium: base.textTheme.headlineMedium?.copyWith(
          fontFamily: BestFonts.text,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
          height: 1.1,
        ),
        headlineSmall: base.textTheme.headlineSmall?.copyWith(
          fontFamily: BestFonts.text,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
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
          letterSpacing: 0,
          height: 1.3,
        ),
        // Material 3 ships positive tracking on body text (0.25-0.5). That is
        // fine for Latin and visibly separates joined Arabic letters.
        bodyLarge: base.textTheme.bodyLarge?.copyWith(
          letterSpacing: 0,
          height: 1.6,
        ),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(
          letterSpacing: 0,
          height: 1.55,
        ),
        bodySmall: base.textTheme.bodySmall?.copyWith(
          letterSpacing: 0,
          height: 1.5,
        ),
        labelLarge: base.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
        labelMedium: base.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
        labelSmall: base.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
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
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(BestRadius.md),
        borderSide: BorderSide(color: scheme.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(BestRadius.md),
        borderSide: BorderSide(color: scheme.error, width: 1.4),
      ),
      prefixIconColor: scheme.onSurfaceVariant,
      suffixIconColor: scheme.onSurfaceVariant,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, BestLayout.minTouch),
        padding: const EdgeInsets.symmetric(horizontal: BestSpace.xl),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BestRadius.md),
        ),
        textStyle: text.labelLarge?.copyWith(fontSize: 14),
        iconSize: 18,
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
      side: WidgetStateBorderSide.resolveWith((Set<WidgetState> states) {
        return BorderSide(
          color: states.contains(WidgetState.selected)
              ? scheme.primary.withValues(alpha: 0.55)
              : scheme.outlineVariant,
        );
      }),
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
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: ZoomPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: ZoomPageTransitionsBuilder(),
        TargetPlatform.linux: ZoomPageTransitionsBuilder(),
        TargetPlatform.fuchsia: ZoomPageTransitionsBuilder(),
      },
    ),
    scrollbarTheme: ScrollbarThemeData(
      radius: const Radius.circular(BestRadius.pill),
      thickness: const WidgetStatePropertyAll<double>(3),
      thumbColor: WidgetStatePropertyAll<Color>(
        scheme.onSurfaceVariant.withValues(alpha: 0.38),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 500),
      textStyle: text.labelMedium?.copyWith(
        color: isDark ? BestColors.ink : Colors.white,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(BestRadius.sm),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith<Color?>(
        (Set<WidgetState> states) =>
            states.contains(WidgetState.selected) ? Colors.white : null,
      ),
      trackColor: WidgetStateProperty.resolveWith<Color?>(
        (Set<WidgetState> states) =>
            states.contains(WidgetState.selected) ? scheme.primary : null,
      ),
    ),
    sliderTheme: SliderThemeData(
      trackHeight: 4,
      activeTrackColor: scheme.primary,
      inactiveTrackColor: scheme.surfaceContainerHighest,
      thumbColor: scheme.primary,
      overlayColor: scheme.primary.withValues(alpha: 0.14),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BestRadius.md),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      textStyle: text.bodyMedium,
    ),
    expansionTileTheme: ExpansionTileThemeData(
      shape: const Border(),
      collapsedShape: const Border(),
      iconColor: scheme.primary,
      collapsedIconColor: scheme.onSurfaceVariant,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: scheme.primary,
      selectionColor: scheme.primary.withValues(alpha: 0.28),
      selectionHandleColor: scheme.primary,
    ),
  );
}
