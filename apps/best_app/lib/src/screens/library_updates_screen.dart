import 'package:best_domain/best_domain.dart';
import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../actions.dart';
import '../l10n/generated/app_localizations.dart';
import '../labels.dart';
import '../providers.dart';

/// The chapters that appeared after a work was already on the shelf.
///
/// This is a reading feed, not an app-version banner: every row opens the
/// chapter, and a chapter disappears once it has been started. A work's first
/// chapter list never lands here, so adding a series does not flood the tab.
class LibraryUpdatesScreen extends ConsumerWidget {
  const LibraryUpdatesScreen({super.key});

  Future<void> _refresh(WidgetRef ref) =>
      ref.read(libraryAutoRefreshProvider.notifier).refreshNow();

  Future<void> _markRead(
    BuildContext context,
    WidgetRef ref,
    List<LibraryUpdate> updates,
  ) async {
    if (updates.isEmpty) return;
    final repository = ref.read(repositoryProvider);
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final update in updates) {
      final total = update.unit.pageCount;
      await repository.saveProgress(
        UnitProgress(
          unitId: update.unit.id,
          position: total > 0 ? total - 1 : 0,
          total: total,
          completed: true,
          started: true,
          updatedAt: now,
        ),
      );
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).updatesMarkedRead)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final updates = ref.watch(libraryUpdatesProvider);
    final progress = ref.watch(libraryRefreshProvider);
    final lastRefresh = ref.watch(libraryAutoRefreshProvider);

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
                        l10n.updatesTitle,
                        style: BestType.pageTitle(context),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.updatesSubtitle,
                        style: BestType.body(context),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: l10n.updatesRefreshNow,
                  onPressed: progress.running ? null : () => _refresh(ref),
                  icon: const Icon(Icons.refresh_rounded),
                ),
                IconButton(
                  tooltip: l10n.updatesMarkAllRead,
                  onPressed: (updates.value ?? const <LibraryUpdate>[]).isEmpty
                      ? null
                      : () => _markRead(
                            context,
                            ref,
                            updates.value ?? const <LibraryUpdate>[],
                          ),
                  icon: const Icon(Icons.done_all_rounded),
                ),
              ],
            ),
          ),
          if (lastRefresh != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
              child: Text(
                l10n.updatesLastRefresh(shortDateTime(
                  lastRefresh.millisecondsSinceEpoch,
                )),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if (progress.running) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: progress.total == 0 ? null : progress.fraction,
              minHeight: 2,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
              child: Text(
                l10n.updatesRefreshProgress(progress.settled, progress.total),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _refresh(ref),
              child: updates.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(
                      height: 360,
                      child: EmptyState(
                        icon: Icons.cloud_off_rounded,
                        title: l10n.updatesEmptyTitle,
                        body: '$error',
                        action: FilledButton(
                          onPressed: () => _refresh(ref),
                          child: Text(l10n.updatesRefresh),
                        ),
                      ),
                    ),
                  ],
                ),
                data: (rows) {
                  if (rows.isEmpty) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: 380,
                          child: EmptyState(
                            icon: Icons.auto_awesome_outlined,
                            title: l10n.updatesEmptyTitle,
                            body: l10n.updatesEmptyBody,
                            action: FilledButton.icon(
                              onPressed: progress.running
                                  ? null
                                  : () => _refresh(ref),
                              icon: const Icon(Icons.refresh_rounded),
                              label: Text(l10n.updatesRefresh),
                            ),
                          ),
                        ),
                      ],
                    );
                  }
                  final groups = <String, List<LibraryUpdate>>{};
                  for (final update in rows) {
                    groups.putIfAbsent(update.media.id, () => []).add(update);
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: groups.length,
                    itemBuilder: (context, index) {
                      final group = groups.values.elementAt(index);
                      return _UpdateGroup(
                        updates: group,
                        onOpenWork: () =>
                            openSeries(context, ref, group.first.media),
                        onOpenUnit: (update) =>
                            openUnit(context, ref, update.media, update.unit),
                        onMarkRead: (update) =>
                            _markRead(context, ref, [update]),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UpdateGroup extends StatelessWidget {
  const _UpdateGroup({
    required this.updates,
    required this.onOpenWork,
    required this.onOpenUnit,
    required this.onMarkRead,
  });

  final List<LibraryUpdate> updates;
  final VoidCallback onOpenWork;
  final ValueChanged<LibraryUpdate> onOpenUnit;
  final ValueChanged<LibraryUpdate> onMarkRead;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final media = updates.first.media;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(BestRadius.lg),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          children: [
            InkWell(
              onTap: onOpenWork,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(BestRadius.lg),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(BestRadius.sm),
                      child: SizedBox(
                        width: 44,
                        height: 64,
                        child: BestCover(
                          title: media.displayTitle,
                          url: media.coverUrl,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            media.displayTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: BestType.cardTitle(context),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l10n.updatesChapterCount(updates.length),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            for (final update in updates)
              InkWell(
                onTap: () => onOpenUnit(update),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(68, 6, 4, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              update.unit.displayTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (update.firstSeenAt > 0)
                              Text(
                                shortDate(update.firstSeenAt),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: l10n.updatesMarkAllRead,
                        onPressed: () => onMarkRead(update),
                        icon: const Icon(Icons.check_rounded, size: 18),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
