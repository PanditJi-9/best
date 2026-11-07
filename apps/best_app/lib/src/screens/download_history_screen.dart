import 'package:best_domain/best_domain.dart';
import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/generated/app_localizations.dart';
import '../labels.dart';
import '../navigation.dart';
import '../providers.dart';

/// A quiet chronological log of finished chapters: what completed, when, and
/// how much space it takes. The Downloads tab groups by work; this is the
/// history the work cards do not show.
class DownloadHistoryScreen extends ConsumerWidget {
  const DownloadHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final tasks = (ref.watch(downloadsProvider).value ?? const <DownloadTask>[])
        .where((task) => task.isFinished)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.downloadsHistory)),
      body: tasks.isEmpty
          ? Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(BestLayout.gutter),
                child: EmptyState(
                  icon: Icons.history_rounded,
                  title: l10n.downloadsHistoryEmptyTitle,
                  body: l10n.downloadsHistoryEmptyBody,
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              itemCount: tasks.length + 1,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      l10n.downloadsHistorySubtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }
                final task = tasks[index - 1];
                return Material(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(BestRadius.md),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => context.push(
                      Routes.reader(
                        sourceId: task.sourceId,
                        url: task.mediaUrl,
                        unitUrl: task.unitUrl,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_rounded,
                              size: 18, color: BestColors.jade),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  task.mediaTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  [
                                    task.unitTitle,
                                    shortDate(task.updatedAt),
                                  ]
                                      .where((part) => part.isNotEmpty)
                                      .join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            formatBytes(task.bytes),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
