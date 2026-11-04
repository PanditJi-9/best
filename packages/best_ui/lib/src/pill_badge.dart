import 'package:flutter/material.dart';

import 'tokens.dart';

/// A capsule-shaped badge with a translucent fill and a thin accent border.
///
/// Ported from HikariManga's BadgePill pattern: `BestAlpha.toneContainer`
/// (10%) fill and `BestAlpha.border` (16%) stroke. The shape signals state
/// ("new", "completed", "manhwa") rather than action — pills are never primary
/// buttons.
class BestPillBadge extends StatelessWidget {
  const BestPillBadge({
    super.key,
    required this.label,
    this.tone = BestTone.accent,
    this.icon,
    this.compact = false,
  });

  final String label;
  final BestTone tone;
  final IconData? icon;

  /// If true, uses tighter padding for inline use.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final toneColor = tone.content(context);
    final fill = tone.container(context);
    final stroke = tone.border(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(BestRadius.pill),
        border: Border.all(color: stroke, width: BestCardSpec.borderWidth),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 12,
          vertical: compact ? 3 : 5,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: compact ? 12 : 14, color: toneColor),
              SizedBox(width: compact ? 4 : 6),
            ],
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: toneColor,
                fontSize: compact ? 10 : 11.5,
                fontWeight: FontWeight.w700,
                fontFamily: BestFontFamily.heading,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
