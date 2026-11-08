import 'package:flutter/material.dart';

import 'tokens.dart';

/// A thin progress rule: a quiet track with a fill in the signature gradient.
///
/// The aurora is the only colour a progress moment gets, so a reader sees where
/// they stopped without a solid bar competing with the artwork. Pass [colors]
/// for a state with its own hue (a finished download is jade), and [track] when
/// the rule sits on artwork and needs a darker well.
class BestProgressRule extends StatelessWidget {
  const BestProgressRule({
    super.key,
    required this.value,
    this.height = 3,
    this.track,
    this.colors,
  });

  /// 0..1. Anything outside that range is clamped and never drawn past the end.
  final double value;

  /// The rule's thickness. Both ends are fully rounded at this radius.
  final double height;

  /// The unfilled part. Defaults to the theme's raised surface.
  final Color? track;

  /// The fill. Defaults to [BestColors.aurora].
  final List<Color>? colors;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fraction = value.isFinite ? value.clamp(0.0, 1.0).toDouble() : 0.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: track ?? scheme.surfaceContainerHighest),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FractionallySizedBox(
                widthFactor: fraction,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: AlignmentDirectional.centerStart,
                      end: AlignmentDirectional.centerEnd,
                      colors: colors ?? BestColors.aurora,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
