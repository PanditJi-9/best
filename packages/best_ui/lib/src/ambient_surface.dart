import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'tokens.dart';

/// A quiet, slowly drifting pair of radial glows behind a screen's content.
///
/// Ported from the Yokai design language's `YokaiAmbientSurface`. It gives
/// launch screens and library headers depth without a photograph or a gradient
/// strip. Intensity stays low enough that text contrast is never in question.
class BestAmbientSurface extends StatefulWidget {
  const BestAmbientSurface({
    super.key,
    this.intensity = 1.0,
    required this.child,
  });

  /// Scales both glows. 0 disables them (reduced-motion). 1 is default.
  final double intensity;
  final Widget child;

  @override
  State<BestAmbientSurface> createState() => _BestAmbientSurfaceState();
}

class _BestAmbientSurfaceState extends State<BestAmbientSurface>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final tertiary = theme.colorScheme.tertiary;
    final intensity = widget.intensity;

    if (intensity <= 0) {
      return widget.child;
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _AmbientPainter(
            phase: _controller.value,
            primary: primary,
            tertiary: tertiary,
            intensity: intensity,
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _AmbientPainter extends CustomPainter {
  _AmbientPainter({
    required this.phase,
    required this.primary,
    required this.tertiary,
    required this.intensity,
  });

  final double phase;
  final Color primary;
  final Color tertiary;
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final minDim = math.min(w, h);

    // Primary glow — upper-left, drifting.
    final c1 = Offset(w * (0.18 + 0.10 * phase), h * (0.12 + 0.04 * phase));
    final r1 = minDim * 0.85;
    final paint1 = Paint()
      ..shader = RadialGradient(
        colors: [
          primary.withValues(alpha: 0.20 * intensity),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: c1, radius: r1));
    canvas.drawCircle(c1, r1, paint1);

    // Tertiary glow — lower-right, counter-drifting.
    final c2 = Offset(w * (0.86 - 0.08 * phase), h * (0.78 - 0.05 * phase));
    final r2 = minDim * 0.70;
    final paint2 = Paint()
      ..shader = RadialGradient(
        colors: [
          tertiary.withValues(alpha: 0.14 * intensity),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: c2, radius: r2));
    canvas.drawCircle(c2, r2, paint2);
  }

  @override
  bool shouldRepaint(_AmbientPainter old) =>
      old.phase != phase ||
      old.primary != primary ||
      old.tertiary != tertiary ||
      old.intensity != intensity;
}
