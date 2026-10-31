import 'package:best_domain/best_domain.dart';
import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/generated/app_localizations.dart';
import '../labels.dart';
import '../navigation.dart';
import '../providers.dart';

class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final downloads = ref.watch(downloadsProvider);
    final current = downloads.value ?? const <DownloadTask>[];
    final finished = current.where((task) => task.isFinished).toList();
    final active = current.where((task) => !task.isFinished).toList();
    final totalBytes = current.fold<int>(0, (sum, task) => sum + task.bytes);

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 14, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.downloadsTitle,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1.2,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        totalBytes > 0
                            ? l10n.downloadsStorage(formatBytes(totalBytes))
                            : l10n.downloadsNote,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (finished.isNotEmpty)
                  IconButton(
                    tooltip: l10n.downloadClearFinished,
                    onPressed: () => _clearFinished(context, ref, current),
                    icon: const Icon(Icons.delete_sweep_outlined),
                  ),
              ],
            ),
          ),
          Expanded(
            child: downloads.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Center(
                child: EmptyState(
                  icon: Icons.error_outline,
                  title: l10n.sourceError,
                  body: '$error',
                ),
              ),
              data: (tasks) {
                if (tasks.isEmpty) {
                  return Center(
                    child: SingleChildScrollView(
                      child: EmptyState(
                        icon: Icons.download_for_offline_outlined,
                        eyebrow: l10n.navDownloads.toUpperCase(),
                        title: l10n.downloadsEmptyTitle,
                        body: l10n.downloadsEmptyBody,
                        action: FilledButton.icon(
                          onPressed: () => context.go(Routes.browse),
                          icon: const Icon(Icons.explore_outlined, size: 18),
                          label: Text(l10n.browseTitle),
                        ),
                      ),
                    ),
                  );
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                  children: [
                    StatStrip(
                      stats: [
                        StatItem(
                          value: '${finished.length}',
                          label: l10n.offlineLabel,
                        ),
                        StatItem(
                          value: '${active.length}',
                          label: l10n.downloadsInProgress,
                        ),
                        StatItem(
                          value: formatBytes(totalBytes),
                          label: l10n.storageLabel,
                        ),
                      ],
                    ),
                    if (active.isNotEmpty) ...[
                      SectionHeader(title: l10n.downloadsInProgress),
                      for (final task in active)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _DownloadTile(
                            task: task,
                            onPause: () => ref
                                .read(downloadManagerProvider)
                                .pause(task.unitId),
                            onResume: () => ref
                                .read(downloadManagerProvider)
                                .resume(task.unitId),
                            onRetry: () => ref
                                .read(downloadManagerProvider)
                                .retry(task.unitId),
                            onDelete: () => _delete(context, ref, task),
                            onOpen: null,
                          ),
                        ),
                    ],
                    if (finished.isNotEmpty) ...[
                      SectionHeader(title: l10n.downloadsFinished),
                      for (final task in finished)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _DownloadTile(
                            task: task,
                            onPause: () => ref
                                .read(downloadManagerProvider)
                                .pause(task.unitId),
                            onResume: () => ref
                                .read(downloadManagerProvider)
                                .resume(task.unitId),
                            onRetry: () => ref
                                .read(downloadManagerProvider)
                                .retry(task.unitId),
                            onDelete: () => _delete(context, ref, task),
                            onOpen: () => context.push(
                              Routes.reader(
                                sourceId: task.sourceId,
                                url: task.mediaUrl,
                                unitUrl: task.unitUrl,
                              ),
                            ),
                          ),
                        ),
                    ],
                    const SizedBox(height: 8),
                    _OfflineNote(text: l10n.downloadsNote),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _clearFinished(
    BuildContext context,
    WidgetRef ref,
    List<DownloadTask> tasks,
  ) async {
    final l10n = AppLocalizations.of(context);
    final finished = tasks.where((task) => task.isFinished).toList();
    if (finished.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.downloadClearTitle),
        content: Text(l10n.downloadClearBody(finished.length)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final manager = ref.read(downloadManagerProvider);
    for (final task in finished) {
      await manager.cancel(task.unitId);
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.downloadClearDone)),
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    DownloadTask task,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.downloadDeleteTitle),
        content: Text(l10n.downloadDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(downloadManagerProvider).cancel(task.unitId);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.downloadRemoved)),
    );
  }
}

class _OfflineNote extends StatelessWidget {
  const _OfflineNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.offline_pin_outlined,
            size: 15,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadTile extends StatelessWidget {
  const _DownloadTile({
    required this.task,
    required this.onPause,
    required this.onResume,
    required this.onRetry,
    required this.onDelete,
    required this.onOpen,
  });

  final DownloadTask task;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onRetry;
  final VoidCallback onDelete;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final done = task.isFinished;
    final failed = task.isFailed;

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(BestRadius.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(BestRadius.md),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: done
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            BestColors.jade.withValues(alpha: 0.24),
                            BestColors.gold.withValues(alpha: 0.10),
                          ],
                        )
                      : null,
                  color: done ? null : theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(BestRadius.sm),
                ),
                child: _StatusIcon(task: task),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.mediaTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      task.unitTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 9),
                    if (failed)
                      Text(
                        task.error ?? l10n.downloadFailed,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                          height: 1.4,
                        ),
                      )
                    else ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(BestRadius.pill),
                        child: LinearProgressIndicator(
                          value: done ? 1 : task.progress,
                          minHeight: 4,
                          backgroundColor:
                              theme.colorScheme.outlineVariant.withValues(
                            alpha: 0.5,
                          ),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            done ? BestColors.jade : theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _statusLabel(l10n),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: done
                              ? BestColors.jade
                              : theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 2),
              _Actions(
                task: task,
                onPause: onPause,
                onResume: onResume,
                onRetry: onRetry,
                onDelete: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _statusLabel(AppLocalizations l10n) {
    final label = switch (task.status) {
      DownloadStatus.queued => l10n.downloadQueued,
      DownloadStatus.running => l10n.downloadProgress(
          task.completed,
          task.total,
        ),
      DownloadStatus.paused => l10n.downloadPaused,
      DownloadStatus.done => l10n.downloadDone,
      DownloadStatus.failed => l10n.downloadFailed,
    };
    if (task.bytes <= 0) return label;
    return '$label · ${formatBytes(task.bytes)}';
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.task});

  final DownloadTask task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return switch (task.status) {
      DownloadStatus.done => const Icon(
          Icons.download_done_rounded,
          color: BestColors.jade,
          size: 22,
        ),
      DownloadStatus.failed => Icon(
          Icons.error_outline,
          color: theme.colorScheme.error,
          size: 22,
        ),
      DownloadStatus.paused => Icon(
          Icons.pause_rounded,
          color: theme.colorScheme.onSurfaceVariant,
          size: 22,
        ),
      DownloadStatus.queued => Icon(
          Icons.schedule_rounded,
          color: theme.colorScheme.onSurfaceVariant,
          size: 21,
        ),
      DownloadStatus.running => SizedBox(
          width: 21,
          height: 21,
          child: CircularProgressIndicator(
            value: task.progress,
            strokeWidth: 2.4,
          ),
        ),
    };
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.task,
    required this.onPause,
    required this.onResume,
    required this.onRetry,
    required this.onDelete,
  });

  final DownloadTask task;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onRetry;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (task.isFinished)
          IconButton(
            tooltip: l10n.downloadOpen,
            visualDensity: VisualDensity.compact,
            onPressed: () => _open(context),
            icon: const Icon(Icons.menu_book_outlined, size: 20),
          )
        else if (task.isFailed)
          IconButton(
            tooltip: l10n.downloadRetry,
            visualDensity: VisualDensity.compact,
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 20),
          )
        else if (task.isPaused)
          IconButton(
            tooltip: l10n.downloadResume,
            visualDensity: VisualDensity.compact,
            onPressed: onResume,
            icon: const Icon(Icons.play_arrow_rounded, size: 22),
          )
        else
          IconButton(
            tooltip: l10n.downloadPause,
            visualDensity: VisualDensity.compact,
            onPressed: onPause,
            icon: const Icon(Icons.pause_rounded, size: 20),
          ),
        IconButton(
          tooltip: l10n.downloadDelete,
          visualDensity: VisualDensity.compact,
          onPressed: onDelete,
          icon: Icon(
            Icons.delete_outline,
            size: 20,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  void _open(BuildContext context) {
    // The tile's InkWell handles taps on the row; the button is here so the
    // action stays discoverable next to delete.
    final router = GoRouter.of(context);
    router.push(
      Routes.reader(
        sourceId: task.sourceId,
        url: task.mediaUrl,
        unitUrl: task.unitUrl,
      ),
    );
  }
}
