import 'package:best_domain/best_domain.dart';
import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';

/// A bottom sheet that lists all chapters/units of the current work, letting
/// the reader jump to any chapter without leaving the reader screen.
///
/// Ported from HikariManga's quick chapter navigation sheet. The current
/// chapter is highlighted with the accent tone.
class ChapterListSheet extends StatelessWidget {
  const ChapterListSheet({
    super.key,
    required this.units,
    required this.currentUnitId,
    required this.onSelected,
    this.workTitle,
  });

  final List<MediaUnit> units;
  final String currentUnitId;
  final ValueChanged<MediaUnit> onSelected;
  final String? workTitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.only(top: BestSpace.sm),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(
                BestSpace.xl, BestSpace.lg, BestSpace.xl, BestSpace.md,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'الفصول',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontFamily: BestFontFamily.heading,
                          ),
                        ),
                        if (workTitle != null)
                          Text(
                            workTitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Chapter count badge
                  BestPillBadge(
                    label: '${units.length}',
                    tone: BestTone.neutral,
                    compact: true,
                    icon: Icons.list_rounded,
                  ),
                ],
              ),
            ),
            const BestHairlineRule(),
            // Chapter list
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.only(bottom: BestSpace.xl),
                itemCount: units.length,
                itemBuilder: (context, index) {
                  final unit = units[index];
                  final isCurrent = unit.id == currentUnitId;

                  return Material(
                    color: isCurrent
                        ? theme.colorScheme.primary
                            .withValues(alpha: BestAlpha.toneContainer)
                        : Colors.transparent,
                    child: InkWell(
                      onTap: isCurrent ? null : () => onSelected(unit),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: BestSpace.xl,
                          vertical: BestSpace.md,
                        ),
                        child: Row(
                          children: [
                            // Chapter number
                            Container(
                              width: 36,
                              height: 36,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: isCurrent
                                    ? theme.colorScheme.primary
                                        .withValues(alpha: 0.16)
                                    : theme.colorScheme.surfaceContainerHigh,
                                borderRadius:
                                    BorderRadius.circular(BestRadius.sm),
                              ),
                              child: Text(
                                '${index + 1}',
                                style: TextStyle(
                                  fontFamily: BestFontFamily.mono,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: isCurrent
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const SizedBox(width: BestSpace.md),
                            // Chapter title
                            Expanded(
                              child: Text(
                                unit.displayTitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight:
                                      isCurrent ? FontWeight.w700 : null,
                                  color: isCurrent
                                      ? theme.colorScheme.primary
                                      : null,
                                ),
                              ),
                            ),
                            // Current indicator
                            if (isCurrent) ...[
                              const SizedBox(width: BestSpace.sm),
                              Icon(
                                Icons.play_circle_filled_rounded,
                                size: 18,
                                color: theme.colorScheme.primary,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
