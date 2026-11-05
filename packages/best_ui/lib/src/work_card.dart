import 'package:flutter/material.dart';

import 'cover.dart';
import 'press_scale.dart';
import 'tokens.dart';

/// The shape of a work, at the two densities the app actually uses.
///
/// Home, Library, Search and Downloads all show the same object — a work you
/// can open — so they show it with the same card. The poster density is for a
/// rail or a grid; the row density is for a list that carries an action.
enum WorkCardDensity { poster, row }

/// One card language for every surface.
///
/// It takes already-localised strings, so the package never needs to know
/// which language the app is in. `progress` is 0..1 and hides the rule when it
/// is zero: an untouched work is not "0% read".
class WorkCard extends StatelessWidget {
  const WorkCard({
    super.key,
    required this.title,
    this.subtitle,
    this.coverUrl,
    this.badge,
    this.progress = 0,
    this.progressLabel,
    this.density = WorkCardDensity.poster,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.semanticLabel,
    this.maxTitleLines = 2,
  });

  final String title;
  final String? subtitle;
  final String? coverUrl;

  /// A short label printed on the cover: the kind of work, or "New".
  final String? badge;

  final double progress;

  /// The one-line state under a row card, e.g. "Page 4 of 10".
  final String? progressLabel;

  final WorkCardDensity density;

  /// Replaces the chevron on a row card. The row stays one target: a caller
  /// that needs two buttons wraps them in a [Row] with 48 dp targets.
  final Widget? trailing;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? semanticLabel;
  final int maxTitleLines;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      label: semanticLabel,
      child: density == WorkCardDensity.poster
          ? _Poster(
              title: title,
              subtitle: subtitle,
              coverUrl: coverUrl,
              badge: badge,
              progress: progress,
              maxTitleLines: maxTitleLines,
              onTap: onTap,
              onLongPress: onLongPress,
            )
          : _Row(
              title: title,
              subtitle: subtitle,
              coverUrl: coverUrl,
              badge: badge,
              progress: progress,
              progressLabel: progressLabel,
              trailing: trailing,
              maxTitleLines: maxTitleLines,
              onTap: onTap,
              onLongPress: onLongPress,
            ),
    );
  }
}

class _Poster extends StatelessWidget {
  const _Poster({
    required this.title,
    required this.subtitle,
    required this.coverUrl,
    required this.badge,
    required this.progress,
    required this.maxTitleLines,
    required this.onTap,
    required this.onLongPress,
  });

  final String title;
  final String? subtitle;
  final String? coverUrl;
  final String? badge;
  final double progress;
  final int maxTitleLines;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BestTapScale(
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
                    border: Border.all(color: theme.colorScheme.outlineVariant),
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
                    child: CoverBadge(label: badge!),
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
                        backgroundColor: Colors.black.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: BestSpace.sm),
          Flexible(
            child: Text(
              title,
              maxLines: maxTitleLines,
              overflow: TextOverflow.ellipsis,
              style: BestType.cardTitle(context),
            ),
          ),
          if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: BestType.meta(context),
            ),
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.title,
    required this.subtitle,
    required this.coverUrl,
    required this.badge,
    required this.progress,
    required this.progressLabel,
    required this.trailing,
    required this.maxTitleLines,
    required this.onTap,
    required this.onLongPress,
  });

  final String title;
  final String? subtitle;
  final String? coverUrl;
  final String? badge;
  final double progress;
  final String? progressLabel;
  final Widget? trailing;
  final int maxTitleLines;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BestRadius.md),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: EdgeInsetsDirectional.fromSTEB(
            BestSpace.md,
            BestSpace.md,
            trailing == null ? BestSpace.xs : BestSpace.xxs,
            BestSpace.md,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 52,
                height: 76,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    BestCover(
                      title: title,
                      url: coverUrl,
                      radius: BestRadius.sm,
                    ),
                    if (badge != null && badge!.trim().isNotEmpty)
                      PositionedDirectional(
                        top: 3,
                        start: 3,
                        end: 3,
                        child: CoverBadge(label: badge!, dense: true),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: BestSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: maxTitleLines,
                      overflow: TextOverflow.ellipsis,
                      style: BestType.cardTitle(context),
                    ),
                    if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: BestType.meta(context),
                      ),
                    ],
                    if (progress > 0) ...[
                      const SizedBox(height: BestSpace.sm),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(BestRadius.pill),
                        child: LinearProgressIndicator(
                          value: progress.clamp(0.0, 1.0),
                          minHeight: 3,
                          color: theme.colorScheme.primary,
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHighest,
                        ),
                      ),
                      if (progressLabel != null) ...[
                        const SizedBox(height: BestSpace.xs + 1),
                        Text(
                          progressLabel!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: BestType.meta(context).copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: BestSpace.xxs),
                trailing!,
              ] else
                Padding(
                  padding:
                      const EdgeInsetsDirectional.only(start: BestSpace.xs),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small printed label over a cover. One shape for "Manhwa", "New" and the
/// guide's own badge.
class CoverBadge extends StatelessWidget {
  const CoverBadge({super.key, required this.label, this.dense = false});

  final String label;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(BestRadius.xs),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: dense ? 4 : 7,
          vertical: dense ? 1.5 : 3,
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: dense ? 9 : 10.5,
            height: 1.1,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}
