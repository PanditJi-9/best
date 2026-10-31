import 'package:flutter/material.dart';

import 'cover.dart';
import 'tokens.dart';

/// The shelf card. It takes already-localized strings so this package never
/// needs to know which language the app is in.
class MediaCard extends StatelessWidget {
  const MediaCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.coverUrl,
    this.badge,
    this.progress = 0,
    this.rank,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final String? coverUrl;
  final String? badge;

  /// 0..1. A zero value hides the bar entirely; an empty work is not "0% read".
  final double progress;

  /// 1-based position in a ranked rail. Drawn as an outlined numeral so the
  /// artwork stays the loudest thing on the card.
  final int? rank;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      label: title,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(BestRadius.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 2 / 3,
              child: Stack(
                fit: StackFit.expand,
                clipBehavior: Clip.none,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(BestRadius.md),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                    child: BestCover(
                      title: title,
                      url: coverUrl,
                      radius: BestRadius.md,
                    ),
                  ),
                  if (badge != null)
                    PositionedDirectional(
                      top: BestSpace.sm,
                      start: BestSpace.sm,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.58),
                          borderRadius: BorderRadius.circular(BestRadius.pill),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: BestSpace.sm,
                            vertical: 3,
                          ),
                          child: Text(
                            badge!,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (rank != null)
                    PositionedDirectional(
                      bottom: -10,
                      end: 6,
                      child: Text(
                        '$rank',
                        style: TextStyle(
                          fontSize: 56,
                          height: 1,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -3,
                          foreground: Paint()
                            ..style = PaintingStyle.stroke
                            ..strokeWidth = 2
                            ..color = Colors.white.withValues(alpha: 0.9),
                          shadows: [
                            Shadow(
                              color: Colors.black.withValues(alpha: 0.5),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: BestSpace.sm + 2),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (progress > 0) ...[
              const SizedBox(height: BestSpace.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(BestRadius.pill),
                child: LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  minHeight: 4,
                  color: BestColors.jade,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
