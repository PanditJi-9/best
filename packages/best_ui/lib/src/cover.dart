import 'package:flutter/material.dart';

import 'tokens.dart';

/// A cover that never shows a broken image icon.
///
/// While the artwork loads, the slot shows a quiet sunken surface (no letter
/// flash, no pulse: a grid of nine covers must not blink). When the first frame
/// arrives the image fades in. When a source has no cover, or the network
/// fails, the fallback is a stable gradient derived from the title plus its
/// first glyph. That keeps the shelf looking intentional offline instead of
/// filling it with grey boxes.
///
/// Decoding is capped to the size the slot is actually painted at, so a
/// 1200 px source never costs full-resolution memory inside a 120 px tile.
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

  /// Never decode a cover wider than this, however large the slot is.
  static const int _maxDecodeWidth = 1080;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = _CoverFallback(title: title);
    final hasUrl = url != null && url!.isNotEmpty;

    Widget content;
    if (!hasUrl) {
      content = fallback;
    } else {
      final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
      final fade = BestMotionPolicy.of(context, BestMotion.slow);
      content = LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final width = constraints.maxWidth;
          final int? cacheWidth = width.isFinite && width > 0
              ? (width * dpr).round().clamp(64, _maxDecodeWidth).toInt()
              : null;
          return Image.network(
            url!,
            fit: BoxFit.cover,
            cacheWidth: cacheWidth,
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
            frameBuilder: (
              BuildContext context,
              Widget child,
              int? frame,
              bool wasSynchronouslyLoaded,
            ) {
              if (wasSynchronouslyLoaded) return child;
              return AnimatedOpacity(
                opacity: frame == null ? 0 : 1,
                duration: fade,
                curve: BestMotion.curve,
                child: child,
              );
            },
            errorBuilder: (
              BuildContext context,
              Object error,
              StackTrace? stack,
            ) =>
                fallback,
          );
        },
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: ColoredBox(
        color: scheme.surfaceContainerHighest,
        // The derived artwork sits behind the network image. While the image
        // downloads (or when it never arrives) the slot still has an identity
        // instead of a flat grey box that reads as a broken cover.
        child: Stack(
          fit: StackFit.expand,
          children: [
            fallback,
            content,
          ],
        ),
      ),
    );
  }
}

class _CoverFallback extends StatelessWidget {
  const _CoverFallback({required this.title});

  final String title;

  // Warm, ink and mineral grounds: an offline cover should look printed on
  // the same paper as the rest of the app, not like a default blue tile.
  static const List<List<Color>> _palettes = [
    [Color(0xFF2A0F0C), Color(0xFF8E2F22)],
    [Color(0xFF2B1C0B), Color(0xFF9A6326)],
    [Color(0xFF1E1220), Color(0xFF5E2C4A)],
    [Color(0xFF0E211C), Color(0xFF276B57)],
    [Color(0xFF141521), Color(0xFF3A3F66)],
    [Color(0xFF221812), Color(0xFF6E4530)],
  ];

  @override
  Widget build(BuildContext context) {
    final trimmed = title.trim();
    final index = (trimmed.hashCode & 0x7fffffff) % _palettes.length;
    final palette = _palettes[index];
    final glyph =
        trimmed.isEmpty ? '?' : String.fromCharCode(trimmed.runes.first);

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: palette,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // A soft light from the top corner and a darker foot, so an offline
          // cover reads as printed artwork rather than a flat colour block.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-0.7, -0.8),
                radius: 1.1,
                colors: [Color(0x2EFFFFFF), Color(0x00FFFFFF)],
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x00000000), Color(0x52000000)],
                stops: [0.5, 1],
              ),
            ),
          ),
          Center(
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
        ],
      ),
    );
  }
}
