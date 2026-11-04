import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';

import 'l10n/generated/app_localizations.dart';
import 'progress_label.dart';
import 'providers.dart';

/// The action and its progress always describe the same stored unit.
class ReadingCard extends StatelessWidget {
  const ReadingCard({
    super.key,
    required this.slot,
    required this.onOpen,
    this.prominent = false,
  });

  final ResumeSlot slot;
  final VoidCallback onOpen;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final progress = slot.continueEntry;
    final isWatching = slot.media.kind.isWatching;
    final actionLabel = slot.isNext
        ? l10n.nextUp
        : isWatching
            ? l10n.continueWatching
            : l10n.continueReading;
    final detail = progress == null
        ? l10n.homePickUp
        : continueProgressLabel(l10n, progress);

    if (!prominent) {
      return WorkCard(
        density: WorkCardDensity.row,
        title: slot.media.displayTitle,
        coverUrl: slot.media.coverUrl,
        subtitle: '$actionLabel · ${slot.unit.displayTitle}',
        progress: slot.fraction,
        progressLabel: detail,
        onTap: onOpen,
      );
    }

    final theme = Theme.of(context);
    final actionIcon =
        isWatching ? Icons.play_arrow_rounded : Icons.auto_stories_rounded;

    return LayoutBuilder(
      builder: (context, constraints) {
        final height =
            (constraints.maxWidth * 0.64).clamp(252.0, 344.0).toDouble();
        return Semantics(
          button: true,
          label:
              '${slot.media.displayTitle}, ${slot.unit.displayTitle}, $actionLabel',
          child: Material(
            color: BestColors.inkDeep,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(BestRadius.xl),
              side: BorderSide(
                color: theme.colorScheme.primary.withValues(alpha: 0.5),
              ),
            ),
            child: InkWell(
              onTap: onOpen,
              child: SizedBox(
                height: height,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    BestCover(
                      title: slot.media.displayTitle,
                      url: slot.media.coverUrl,
                      radius: 0,
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            BestColors.inkDeep.withValues(alpha: 0.12),
                            BestColors.inkDeep.withValues(alpha: 0.34),
                            BestColors.inkDeep.withValues(alpha: 0.96),
                          ],
                          stops: const [0.0, 0.38, 1.0],
                        ),
                      ),
                    ),
                    PositionedDirectional(
                      top: BestSpace.lg,
                      start: BestSpace.lg,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: BestColors.inkDeep.withValues(alpha: 0.62),
                          borderRadius:
                              BorderRadius.circular(BestRadius.pill),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.18),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsetsDirectional.fromSTEB(
                            BestSpace.md,
                            BestSpace.xs + 1,
                            BestSpace.md,
                            BestSpace.xs + 1,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isWatching
                                    ? Icons.play_circle_outline_rounded
                                    : Icons.auto_stories_outlined,
                                color: Colors.white,
                                size: 16,
                              ),
                              const SizedBox(width: BestSpace.xs + 1),
                              Text(
                                slot.isNext ? l10n.nextUp : l10n.homePickUp,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    PositionedDirectional(
                      start: BestSpace.lg,
                      end: BestSpace.lg,
                      bottom: BestSpace.lg,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            slot.media.displayTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              height: 1.12,
                            ),
                          ),
                          const SizedBox(height: BestSpace.xs),
                          Text(
                            slot.unit.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.white.withValues(alpha: 0.84),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (slot.fraction > 0) ...[
                            const SizedBox(height: BestSpace.md),
                            Row(
                              children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius:
                                        BorderRadius.circular(BestRadius.pill),
                                    child: LinearProgressIndicator(
                                      value: slot.fraction
                                          .clamp(0.0, 1.0)
                                          .toDouble(),
                                      minHeight: 4,
                                      color: BestColors.cyan,
                                      backgroundColor:
                                          Colors.white.withValues(alpha: 0.22),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: BestSpace.md),
                                Text(
                                  detail,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.88),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: BestSpace.md),
                          Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: BestColors.aurora,
                                  ),
                                  borderRadius:
                                      BorderRadius.circular(BestRadius.md),
                                ),
                                child: Icon(
                                  actionIcon,
                                  color: Colors.white,
                                  size: 21,
                                ),
                              ),
                              const SizedBox(width: BestSpace.md),
                              Expanded(
                                child: Text(
                                  actionLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.arrow_forward_rounded,
                                color: Colors.white.withValues(alpha: 0.86),
                                size: 20,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
