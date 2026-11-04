import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';

/// Reader colour filter modes, ported from Yokai / Komikku's ColorFilterPage.
///
/// These filters apply as a [ColorFiltered] or [BackdropFilter] overlay on top
/// of the manga page content to protect the reader's eyes and enhance the
/// reading experience.
enum ReaderColorFilterMode {
  /// No filter applied.
  none,

  /// Convert pages to greyscale — classic manga look on coloured scans.
  greyscale,

  /// Invert all colours — a quick night mode for white-background pages.
  invert,

  /// Custom RGBA colour overlay for warm/sepia tints that reduce blue light.
  custom,
}

/// Settings for the reader colour filter system.
class ReaderColorFilter {
  const ReaderColorFilter({
    this.mode = ReaderColorFilterMode.none,
    this.customColor = const Color(0x33FF8800),
    this.customBrightnessOffset = 0,
  });

  final ReaderColorFilterMode mode;

  /// The tint colour when [mode] is [ReaderColorFilterMode.custom].
  /// Default is a warm amber at ~20% opacity.
  final Color customColor;

  /// Brightness offset from -75 to 100. Negative values overlay a dimming
  /// scrim for reading in the dark; 0 is system brightness.
  final int customBrightnessOffset;

  ReaderColorFilter copyWith({
    ReaderColorFilterMode? mode,
    Color? customColor,
    int? customBrightnessOffset,
  }) {
    return ReaderColorFilter(
      mode: mode ?? this.mode,
      customColor: customColor ?? this.customColor,
      customBrightnessOffset:
          customBrightnessOffset ?? this.customBrightnessOffset,
    );
  }
}

/// Wraps a child with the active reader colour filter.
///
/// When [filter.mode] is [ReaderColorFilterMode.none], the child is returned
/// unmodified. This is designed to wrap each page in the reader so the filter
/// applies per-page, not on the whole scaffold.
class ReaderColorFilterOverlay extends StatelessWidget {
  const ReaderColorFilterOverlay({
    super.key,
    required this.filter,
    required this.child,
  });

  final ReaderColorFilter filter;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    Widget result = child;

    // Apply brightness dimmer first (negative offset = dim).
    if (filter.customBrightnessOffset < 0) {
      final dimAlpha = (filter.customBrightnessOffset.abs() / 100.0)
          .clamp(0.0, 0.75);
      result = Stack(
        children: [
          result,
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: dimAlpha),
              ),
            ),
          ),
        ],
      );
    }

    // Apply the colour filter mode.
    return switch (filter.mode) {
      ReaderColorFilterMode.none => result,
      ReaderColorFilterMode.greyscale => ColorFiltered(
          colorFilter: const ColorFilter.matrix(<double>[
            0.2126, 0.7152, 0.0722, 0, 0, //
            0.2126, 0.7152, 0.0722, 0, 0, //
            0.2126, 0.7152, 0.0722, 0, 0, //
            0, 0, 0, 1, 0, //
          ]),
          child: result,
        ),
      ReaderColorFilterMode.invert => ColorFiltered(
          colorFilter: const ColorFilter.matrix(<double>[
            -1, 0, 0, 0, 255, //
            0, -1, 0, 0, 255, //
            0, 0, -1, 0, 255, //
            0, 0, 0, 1, 0, //
          ]),
          child: result,
        ),
      ReaderColorFilterMode.custom => Stack(
          children: [
            result,
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(color: filter.customColor),
              ),
            ),
          ],
        ),
    };
  }
}

/// Bottom sheet for configuring reader colour filters.
///
/// Provides quick toggles for greyscale, invert, warm-light and brightness
/// dimming. Ported from Yokai / Komikku's ColorFilterPage concept.
class ReaderColorFilterSheet extends StatefulWidget {
  const ReaderColorFilterSheet({
    super.key,
    required this.filter,
    required this.onChanged,
  });

  final ReaderColorFilter filter;
  final ValueChanged<ReaderColorFilter> onChanged;

  @override
  State<ReaderColorFilterSheet> createState() => _ReaderColorFilterSheetState();
}

class _ReaderColorFilterSheetState extends State<ReaderColorFilterSheet> {
  late ReaderColorFilter _filter;

  @override
  void initState() {
    super.initState();
    _filter = widget.filter;
  }

  void _update(ReaderColorFilter next) {
    setState(() => _filter = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          BestSpace.xl, BestSpace.lg, BestSpace.xl, BestSpace.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            Text(
              'فلتر القراءة',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                fontFamily: BestFontFamily.heading,
              ),
            ),
            const SizedBox(height: BestSpace.lg),

            // Mode chips
            Wrap(
              spacing: BestSpace.sm,
              runSpacing: BestSpace.sm,
              children: [
                _filterChip(
                  'بدون فلتر',
                  Icons.filter_none_rounded,
                  ReaderColorFilterMode.none,
                ),
                _filterChip(
                  'تدرج رمادي',
                  Icons.gradient_rounded,
                  ReaderColorFilterMode.greyscale,
                ),
                _filterChip(
                  'عكس الألوان',
                  Icons.invert_colors_rounded,
                  ReaderColorFilterMode.invert,
                ),
                _filterChip(
                  'ضوء دافئ',
                  Icons.wb_sunny_rounded,
                  ReaderColorFilterMode.custom,
                ),
              ],
            ),
            const SizedBox(height: BestSpace.xl),

            // Brightness slider
            Text(
              'تعتيم الشاشة',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: BestSpace.sm),
            Row(
              children: [
                const Icon(Icons.brightness_low_rounded, size: 18),
                Expanded(
                  child: Slider(
                    value: _filter.customBrightnessOffset.toDouble(),
                    min: -75,
                    max: 0,
                    divisions: 75,
                    onChanged: (v) => _update(
                      _filter.copyWith(customBrightnessOffset: v.round()),
                    ),
                  ),
                ),
                const Icon(Icons.brightness_high_rounded, size: 18),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String label, IconData icon, ReaderColorFilterMode mode) {
    final selected = _filter.mode == mode;
    final scheme = Theme.of(context).colorScheme;
    return FilterChip(
      selected: selected,
      showCheckmark: false,
      avatar: Icon(icon, size: 16),
      label: Text(label),
      labelStyle: TextStyle(
        fontFamily: BestFontFamily.heading,
        fontSize: 12,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
      ),
      selectedColor: scheme.primary.withValues(alpha: 0.16),
      side: BorderSide(
        color: selected
            ? scheme.primary.withValues(alpha: BestAlpha.borderStrong)
            : scheme.outlineVariant,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BestRadius.pill),
      ),
      onSelected: (_) => _update(_filter.copyWith(mode: mode)),
    );
  }
}
