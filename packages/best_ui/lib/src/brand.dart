import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'cover.dart';
import 'tokens.dart';

/// The Best seal: a vermilion stamp holding a four-point spark.
///
/// The 2.0 mark reads as a printed seal rather than an app-store tile: the
/// gradient is the stamp, the inset hairline is the impression, and the spark
/// is ivory paper. Drawn rather than shipped as an asset so it stays sharp at
/// every size and costs the bundle nothing.
class BestMark extends StatelessWidget {
  const BestMark({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: BestColors.aurora,
          ),
          borderRadius: BorderRadius.circular(size * 0.28),
          border: Border.all(
            color: BestColors.inkDeep.withValues(alpha: 0.24),
            width: 0.8,
          ),
        ),
        child: CustomPaint(
          painter: _SealPainter(side: size),
        ),
      ),
    );
  }
}

class _SealPainter extends CustomPainter {
  const _SealPainter({required this.side});

  final double side;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final inset = size.shortestSide * 0.11;
    final stamp = RRect.fromRectAndRadius(
      Rect.fromLTRB(inset, inset, size.width - inset, size.height - inset),
      Radius.circular(size.shortestSide * 0.18),
    );
    canvas.drawRRect(
      stamp,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (size.shortestSide * 0.03).clamp(0.8, 1.6)
        ..color = const Color(0xFFFFF4E4).withValues(alpha: 0.55),
    );

    final radius = size.shortestSide * 0.27;
    final path = Path()
      ..moveTo(center.dx, center.dy - radius)
      ..cubicTo(
        center.dx + radius * 0.10,
        center.dy - radius * 0.34,
        center.dx + radius * 0.30,
        center.dy - radius * 0.12,
        center.dx + radius,
        center.dy,
      )
      ..cubicTo(
        center.dx + radius * 0.30,
        center.dy + radius * 0.12,
        center.dx + radius * 0.10,
        center.dy + radius * 0.34,
        center.dx,
        center.dy + radius,
      )
      ..cubicTo(
        center.dx - radius * 0.10,
        center.dy + radius * 0.34,
        center.dx - radius * 0.30,
        center.dy + radius * 0.12,
        center.dx - radius,
        center.dy,
      )
      ..cubicTo(
        center.dx - radius * 0.30,
        center.dy - radius * 0.12,
        center.dx - radius * 0.10,
        center.dy - radius * 0.34,
        center.dx,
        center.dy - radius,
      )
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFFFFF6E9));
  }

  @override
  bool shouldRepaint(covariant _SealPainter oldDelegate) =>
      oldDelegate.side != side;
}

/// Mark plus wordmark. The tagline is optional because the same lockup is used
/// on the home header and in the about card.
class BestWordmark extends StatelessWidget {
  const BestWordmark({
    super.key,
    this.markSize = 34,
    this.tagline,
    this.label = 'Best',
  });

  final double markSize;
  final String? tagline;

  /// Localized product name. Latin "Best" is the default so the package stays
  /// usable without the app's localizations.
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BestMark(size: markSize),
        const SizedBox(width: BestSpace.md),
        // The lockup sits in an `Expanded` on the home header, so it has to be
        // able to give up width: a long tagline or a large system text scale
        // would otherwise overflow the row instead of ellipsizing.
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontSize: 23,
                  fontWeight: FontWeight.w700,
                  letterSpacing: Directionality.of(context) == TextDirection.rtl
                      ? 0
                      : -0.7,
                  height: 0.98,
                ),
              ),
              if (tagline != null) ...[
                const SizedBox(height: 4),
                Text(
                  tagline!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: BestType.tracking(context, 0.5),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A cover used as atmosphere: blurred, dimmed and scrimmed so the title above
/// it stays readable. Falls back to the deterministic gradient when the source
/// has no artwork.
class BestBackdrop extends StatelessWidget {
  const BestBackdrop({
    super.key,
    required this.title,
    this.url,
    this.blur = 26,
    this.opacity = 0.55,
  });

  final String title;
  final String? url;
  final double blur;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        Opacity(
          opacity: opacity,
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: BestCover(title: title, url: url, radius: 0),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                theme.colorScheme.surface.withValues(alpha: 0.15),
                theme.colorScheme.surface.withValues(alpha: 0.65),
                theme.colorScheme.surface,
              ],
              stops: const [0, 0.55, 1],
            ),
          ),
        ),
      ],
    );
  }
}

/// Three numbers on one card. HikariManga uses the same device on its profile
/// and series pages; it reads faster than three separate tiles.
class StatStrip extends StatelessWidget {
  const StatStrip({super.key, required this.stats});

  final List<StatItem> stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: BestSpace.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(BestRadius.md),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          for (var index = 0; index < stats.length; index++) ...[
            if (index > 0)
              Container(
                width: 1,
                height: 30,
                color: theme.colorScheme.outlineVariant,
              ),
            Expanded(child: _Stat(item: stats[index])),
          ],
        ],
      ),
    );
  }
}

class StatItem {
  const StatItem({required this.value, required this.label});

  final String value;
  final String label;
}

class _Stat extends StatelessWidget {
  const _Stat({required this.item});

  final StatItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            item.value,
            maxLines: 1,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
              fontFeatures: const [ui.FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          item.label,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
