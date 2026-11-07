import 'package:flutter/material.dart';

import 'bidi.dart';
import 'cover.dart';
import 'rating.dart';
import 'tokens.dart';

/// A catalogue poster: the smallest unit of the home grid.
///
/// Three of these fit a phone. The cover is the only loud element; the title is
/// one line and the genre strip is one muted line, so a row of nine works scans
/// as nine posters instead of nine paragraphs.
class PosterTile extends StatelessWidget {
  const PosterTile({
    super.key,
    required this.title,
    this.coverUrl,
    this.badge,
    this.genres = const [],
    this.rating,
    this.progress = 0,
    this.onTap,
    this.onLongPress,
    this.inLibrary = false,
    this.showGenres = true,
  });

  final String title;
  final String? coverUrl;
  final String? badge;
  final List<String> genres;

  /// The source's own score, when it publishes one.
  final double? rating;

  /// 0..1. Zero hides the bar: an untouched work is not "0% read".
  final double progress;
  final VoidCallback? onTap;

  /// Long-press is the shortcut to the shelf: no menu, no detour.
  final VoidCallback? onLongPress;

  /// A small tick when the work is already on the shelf.
  final bool inLibrary;
  final bool showGenres;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: title,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(BestRadius.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 2 / 3,
              child: Stack(
                fit: StackFit.expand,
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
                      top: 6,
                      start: 6,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.25),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          child: Text(
                            badge!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 9.5,
                              height: 1.1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (rating != null)
                    PositionedDirectional(
                      bottom: 6,
                      start: 6,
                      child: RatingBadge(score: rating!, compact: true),
                    ),
                  if (inLibrary)
                    PositionedDirectional(
                      top: 6,
                      end: 6,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color:
                              theme.colorScheme.surface.withValues(alpha: 0.88),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.bookmark_added_rounded,
                          size: 14,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  if (progress > 0)
                    PositionedDirectional(
                      start: 0,
                      end: 0,
                      bottom: 0,
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(BestRadius.md),
                        ),
                        child: LinearProgressIndicator(
                          value: progress.clamp(0.0, 1.0),
                          minHeight: 3,
                          color: theme.colorScheme.primary,
                          backgroundColor: Colors.black.withValues(
                            alpha: 0.45,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: autoTextDirection(
                title,
                Directionality.of(context),
              ),
              style: theme.textTheme.titleSmall?.copyWith(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
            if (showGenres && genres.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                genres.take(3).join(' • '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textDirection: autoTextDirection(
                  genres.first,
                  Directionality.of(context),
                ),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 10,
                  height: 1.2,
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
