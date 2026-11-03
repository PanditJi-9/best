import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import 'tokens.dart';

/// A source's own score, drawn as a small printed stamp.
///
/// Only sources that publish a score ever produce one of these; the widget has
/// no "unrated" state on purpose, because an empty star would read as zero.
class RatingBadge extends StatelessWidget {
  const RatingBadge({
    super.key,
    required this.score,
    this.compact = false,
  });

  /// 0–10, from the source.
  final double score;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = score.toStringAsFixed(1);
    return Semantics(
      label: '$label / 10',
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 5 : 7,
          vertical: compact ? 2 : 4,
        ),
        decoration: BoxDecoration(
          color: BestColors.brass.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(BestRadius.sm),
          border: Border.all(
            color: BestColors.brass.withValues(alpha: 0.55),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.star_rounded,
              size: compact ? 10 : 12,
              color: BestColors.brass,
            ),
            const SizedBox(width: 3),
            Text(
              label,
              style: (compact
                      ? theme.textTheme.labelSmall
                      : theme.textTheme.labelMedium)
                  ?.copyWith(
                color: BestColors.brass,
                fontWeight: FontWeight.w800,
                height: 1,
                letterSpacing: 0,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
