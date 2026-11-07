import 'package:best_domain/best_domain.dart';
import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../actions.dart';
import '../l10n/generated/app_localizations.dart';
import '../labels.dart';
import '../navigation.dart';
import '../providers.dart';

/// Everything that happened, in one place.
///
/// A reading app has three histories: the chapter you have open, the works you
/// opened and left, and the files still coming down. They are different shapes,
/// so they are three segments rather than one mixed list.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

enum _HistoryTab { recent, continueReading }

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  _HistoryTab _tab = _HistoryTab.recent;

  Future<void> _refresh() async {
    ref.invalidate(continueProvider);
    ref.invalidate(recentProvider);
    try {
      await Future.wait([
        ref.read(continueProvider.future),
        ref.read(recentProvider.future),
      ]);
    } catch (_) {
      // Rendered inline.
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final continuing =
        ref.watch(continueProvider).value ?? const <ContinueEntry>[];
    final recent = ref.watch(recentProvider).value ?? const <Media>[];
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.historyTitle,
                        style: BestType.pageTitle(context),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.historySubtitle,
                        style: BestType.body(context),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: l10n.retry,
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
            child: _Segments(
              selected: _tab,
              onSelected: (tab) => setState(() => _tab = tab),
            ),
          ),
          Expanded(
            child: switch (_tab) {
              _HistoryTab.continueReading => _ContinueList(
                  entries: continuing,
                  onRefresh: _refresh,
                ),
              _HistoryTab.recent => _RecentList(
                  works: recent,
                  onRefresh: _refresh,
                ),
            },
          ),
        ],
      ),
    );
  }
}

class _Segments extends StatelessWidget {
  const _Segments({required this.selected, required this.onSelected});

  final _HistoryTab selected;
  final ValueChanged<_HistoryTab> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final options = <(_HistoryTab, String)>[
      (_HistoryTab.recent, l10n.historyRecent),
      (_HistoryTab.continueReading, l10n.historyContinue),
    ];
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final option = options[index];
          return _SegmentChip(
            label: option.$2,
            selected: option.$1 == selected,
            onTap: () => onSelected(option.$1),
          );
        },
      ),
    );
  }
}

class _SegmentChip extends StatelessWidget {
  const _SegmentChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(BestRadius.pill),
      child: AnimatedContainer(
        duration: BestMotion.fast,
        padding: const EdgeInsets.symmetric(horizontal: 15),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(BestRadius.pill),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          style: theme.textTheme.labelMedium?.copyWith(
            color: selected
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 11.5,
          ),
        ),
      ),
    );
  }
}

class _ContinueList extends StatelessWidget {
  const _ContinueList({required this.entries, required this.onRefresh});

  final List<ContinueEntry> entries;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (entries.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.12),
            EmptyState(
              icon: Icons.history_rounded,
              title: l10n.historyEmptyTitle,
              body: l10n.historyEmptyBody,
              action: FilledButton.icon(
                onPressed: () => context.push(Routes.sources),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(l10n.homeAddSources),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: entries.length,
        separatorBuilder: (context, index) => const SizedBox(height: 10),
        itemBuilder: (context, index) => _ContinueCard(entry: entries[index]),
      ),
    );
  }
}

class _ContinueCard extends ConsumerWidget {
  const _ContinueCard({required this.entry});

  final ContinueEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final media = entry.media;
    final total = entry.progress.total;
    final fraction = total <= 0
        ? (entry.progress.completed ? 1.0 : 0.0)
        : (entry.progress.position / total).clamp(0.0, 1.0);

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(BestRadius.lg),
      child: InkWell(
        onTap: () => openUnit(context, ref, media, entry.unit),
        borderRadius: BorderRadius.circular(BestRadius.lg),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(BestRadius.lg),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 62,
                height: 93,
                child: BestCover(
                  title: media.displayTitle,
                  url: media.coverUrl,
                  radius: BestRadius.sm,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      media.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${l10n.menuChaptersShort} '
                      '${shortNumber(entry.unit.number)} · '
                      '${kindLabel(l10n, media.kind)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 9),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(BestRadius.pill),
                      child: LinearProgressIndicator(
                        value: fraction,
                        minHeight: 4,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          total > 0
                              ? l10n.pageOf(
                                  (entry.progress.position + 1).clamp(1, total),
                                  total,
                                )
                              : l10n.continueReading,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 10.5,
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          Icons.play_arrow_rounded,
                          size: 18,
                          color: theme.colorScheme.primary,
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
    );
  }
}

class _RecentList extends StatelessWidget {
  const _RecentList({required this.works, required this.onRefresh});

  final List<Media> works;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (works.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.12),
            EmptyState(
              icon: Icons.history_toggle_off_rounded,
              title: l10n.historyEmptyTitle,
              body: l10n.historyRecentEmpty,
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: works.length,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) => _RecentRow(media: works[index]),
      ),
    );
  }
}

class _RecentRow extends ConsumerWidget {
  const _RecentRow({required this.media});

  final Media media;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(BestRadius.md),
      child: InkWell(
        onTap: () => openSeries(context, ref, media),
        borderRadius: BorderRadius.circular(BestRadius.md),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(BestRadius.md),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 48,
                height: 72,
                child: BestCover(
                  title: media.displayTitle,
                  url: media.coverUrl,
                  radius: BestRadius.sm,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      media.displayTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textDirection: autoTextDirection(
                        media.displayTitle,
                        Directionality.of(context),
                      ),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${kindLabel(l10n, media.kind)} · '
                      '${shortDate(media.lastOpenedAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
