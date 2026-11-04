import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';

import 'l10n/generated/app_localizations.dart';
import 'progress_label.dart';
import 'providers.dart';

/// The action and its progress always describe the same stored unit.
class ReadingCard extends StatelessWidget {
  const ReadingCard(
      {super.key,
      required this.slot,
      required this.onOpen,
      this.prominent = false});

  final ResumeSlot slot;
  final VoidCallback onOpen;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final progress = slot.continueEntry;
    final label = slot.isNext ? l10n.nextUp : l10n.homePickUp;
    final detail =
        progress == null ? label : continueProgressLabel(l10n, progress);
    if (!prominent) {
      return WorkCard(
        density: WorkCardDensity.row,
        title: slot.media.displayTitle,
        coverUrl: slot.media.coverUrl,
        subtitle: '$label · ${slot.unit.displayTitle}',
        progress: slot.fraction,
        progressLabel: detail,
        onTap: onOpen,
      );
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(BestRadius.xl),
        border:
            Border.all(color: theme.colorScheme.primary.withValues(alpha: .3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(
                slot.media.kind.isWatching
                    ? Icons.play_circle_outline
                    : Icons.auto_stories_outlined,
                color: theme.colorScheme.primary,
                size: 20),
            const SizedBox(width: 8),
            Expanded(
                child: Text(label,
                    style: BestType.cardTitle(context)
                        .copyWith(color: theme.colorScheme.primary))),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            SizedBox(
                width: 76,
                height: 114,
                child: BestCover(
                    title: slot.media.displayTitle,
                    url: slot.media.coverUrl,
                    radius: BestRadius.md)),
            const SizedBox(width: 16),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(slot.media.displayTitle,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: BestType.sectionTitle(context)),
                  const SizedBox(height: 6),
                  Text(slot.unit.displayTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: BestType.body(context)),
                  if (progress != null) ...[
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                        value: slot.fraction,
                        minHeight: 3,
                        borderRadius: BorderRadius.circular(BestRadius.pill)),
                    const SizedBox(height: 6),
                    Text(detail, style: BestType.meta(context)),
                  ],
                ])),
          ]),
          const SizedBox(height: 16),
          SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onOpen,
                icon: Icon(
                    slot.media.kind.isWatching
                        ? Icons.play_arrow_rounded
                        : Icons.menu_book_rounded,
                    size: 20),
                label: Text(slot.isNext ? l10n.nextUp : l10n.continueReading),
              )),
        ],
      ),
    );
  }
}
