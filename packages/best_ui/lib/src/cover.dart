import 'package:flutter/material.dart';

import 'tokens.dart';

/// A cover that never shows a broken image icon.
///
/// When a source has no cover, or the network fails, the fallback is a stable
/// gradient derived from the title plus its first glyph. That keeps the shelf
/// looking intentional offline instead of filling it with grey boxes.
class BestCover extends StatelessWidget {
  const BestCover({
    super.key,
    required this.title,
    this.url,
    this.radius = BestRadius.md,
  });

  final String title;
  final String? url;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final fallback = _CoverFallback(title: title);
    final image = (url == null || url!.isEmpty)
        ? fallback
        : Image.network(
            url!,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            frameBuilder: (
              BuildContext context,
              Widget child,
              int? frame,
              bool wasSynchronouslyLoaded,
            ) {
              if (wasSynchronouslyLoaded || frame != null) return child;
              return fallback;
            },
            errorBuilder: (
              BuildContext context,
              Object error,
              StackTrace? stack,
            ) => fallback,
          );

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: image,
      ),
    );
  }
}

class _CoverFallback extends StatelessWidget {
  const _CoverFallback({required this.title});

  final String title;

  static const List<List<Color>> _palettes = [
    [Color(0xFF2A1B16), Color(0xFF7A3526)],
    [Color(0xFF1D2420), Color(0xFF3F6B57)],
    [Color(0xFF2B2118), Color(0xFF8A5A32)],
    [Color(0xFF1B2433), Color(0xFF355C7D)],
    [Color(0xFF2E1B24), Color(0xFF7B3B4C)],
    [Color(0xFF22222A), Color(0xFF5A5A78)],
  ];

  @override
  Widget build(BuildContext context) {
    final trimmed = title.trim();
    final index = (trimmed.hashCode & 0x7fffffff) % _palettes.length;
    final palette = _palettes[index];
    final glyph = trimmed.isEmpty
        ? '?'
        : String.fromCharCode(trimmed.runes.first);

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: palette,
        ),
      ),
      child: Center(
        child: Text(
          glyph,
          style: TextStyle(
            fontFamily: BestFonts.display,
            color: Colors.white.withValues(alpha: 0.88),
            fontSize: 46,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
      ),
    );
  }
}
