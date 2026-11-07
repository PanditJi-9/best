import 'package:flutter/material.dart';

import 'bidi.dart';
import 'cover.dart';
import 'press_scale.dart';
import 'rating.dart';
import 'tokens.dart';
import 'work_card.dart' show CoverBadge;

/// The shelf card: a poster, a printed kind label, and a title in the app's UI
/// face (the same title style `WorkCard` uses, so a rail of `MediaCard`s and a
/// grid of `WorkCard`s read as one family). It takes already-localized strings
/// so the package never needs to know which language the app is in.
class MediaCard extends StatelessWidget {
  const MediaCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.coverUrl,
    this.badge,
    this.progress = 0,
    this.rank,
    this.rating,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final String? coverUrl;
  final String? badge;

  /// 0..1. A zero value hides the bar entirely; an empty work is not "0% read".
  final double progress;

  /// 1-based position in a ranked rail. Drawn as an outlined brass numeral so
  /// the artwork stays the loudest thing on the card.
  final int? rank;

  /// The source's own score, when it publishes one. Omitted for unrated works.
  final double? rating;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      label: title,
      child: BestTapScale(
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
                  if (badge != null && badge!.trim().isNotEmpty)
                    PositionedDirectional(
                      top: BestSpace.sm,
                      start: BestSpace.sm,
                      end: BestSpace.sm,
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: CoverBadge(label: badge!),
                      ),
                    ),
                  if (rating != null)
                    PositionedDirectional(
                      bottom: 6,
                      start: 6,
                      child: RatingBadge(score: rating!, compact: true),
                    ),
                  if (rank != null)
                    PositionedDirectional(
                      bottom: -8,
                      end: 5,
                      child: Text(
                        '$rank',
                        style: TextStyle(
                          fontFamily: BestFonts.display,
                          fontSize: 48,
                          height: 1,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -2,
                          foreground: Paint()
                            ..style = PaintingStyle.stroke
                            ..strokeWidth = 1.4
                            ..color = BestColors.brass,
                          shadows: [
                            Shadow(
                              color: Colors.black.withValues(alpha: 0.55),
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
            // A caller can pin the card to a rail height; let the title take
            // the space that is left instead of overflowing the column by a
            // pixel or two at a narrow phone width.
            Flexible(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textDirection: autoTextDirection(
                  title,
                  Directionality.of(context),
                ),
                style: BestType.cardTitle(context),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: autoTextDirection(
                subtitle,
                Directionality.of(context),
              ),
              style: BestType.meta(context),
            ),
            if (progress > 0) ...[
              const SizedBox(height: BestSpace.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(BestRadius.pill),
                child: LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  minHeight: 3,
                  color: theme.colorScheme.primary,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
