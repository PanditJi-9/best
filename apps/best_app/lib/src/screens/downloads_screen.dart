import 'package:best_domain/best_domain.dart';
import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/generated/app_localizations.dart';
import '../labels.dart';
import '../navigation.dart';
import '../network.dart';
import '../providers.dart';
import '../widgets/download_integrity_dialog.dart';

/// Offline reading lives here, apart from the shelf.
///
/// The screen is deliberately quiet: a title, the storage it costs, one history
/// control, the transfers that are still running, and one card per work with
/// its finished chapters folded inside. Searching and filtering a handful of
/// downloads was noise, so they are gone; a per-work menu still removes files.
class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  final Set<String> _busyTasks = {};

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final downloads = ref.watch(downloadsProvider);
    final current = downloads.value ?? const <DownloadTask>[];
    final active =
        current.where((task) => !task.isFinished).toList(growable: false);
    final finished =
        current.where((task) => task.isFinished).toList(growable: false);
    final groups = <String, List<DownloadTask>>{};
    for (final task in finished) {
      groups.putIfAbsent(task.mediaId, () => <DownloadTask>[]).add(task);
    }
    final works = <String, Media>{
      for (final entry
          in ref.watch(libraryProvider).value ?? const <LibraryEntry>[])
        entry.media.id: entry.media,
    };
    final totalBytes = current.fold<int>(0, (sum, task) => sum + task.bytes);
    final settings = ref.watch(settingsProvider);
    final waitingForWifi = settings.wifiOnly &&
        ref.watch(networkProvider).value == NetworkKind.mobile;

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.downloadsTitle,
                          style: BestType.pageTitle(context)),
                      const SizedBox(height: 6),
                      Text(
                        totalBytes > 0
                            ? l10n.downloadsStorage(formatBytes(totalBytes))
                            : l10n.downloadsNote,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: const ValueKey('downloads-history'),
                  tooltip: l10n.downloadsHistory,
                  onPressed: () => context.push(Routes.downloadsHistory),
                  icon: const Icon(Icons.history_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: downloads.when(
              loading: () => const SingleChildScrollView(
                physics: NeverScrollableScrollPhysics(),
                padding: EdgeInsets.all(BestLayout.gutter),
                child: RowListSkeleton(count: 4),
              ),
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
                          onPressed: () => context.push(Routes.sources),
                          icon: const Icon(Icons.extension_outlined, size: 18),
                          label: Text(l10n.homeAddSources),
                        ),
                      ),
                    ),
                  );
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                  children: [
                    if (waitingForWifi && active.any((task) => task.isActive))
                      _WifiBanner(text: l10n.wifiWaiting),
                    if (active.isNotEmpty) ...[
                      SectionHeader(title: l10n.downloadsInProgress),
                      for (final task in active)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _DownloadTile(
                            key: ValueKey('download-${task.unitId}'),
                            task: task,
                            busy: _busyTasks.contains(task.unitId),
                            onPause: () => _change(
                                task,
                                () => ref
                                    .read(downloadManagerProvider)
                                    .pause(task.unitId)),
                            onResume: () => _change(
                                task,
                                () => ref
                                    .read(downloadManagerProvider)
                                    .resume(task.unitId)),
                            onRetry: () => _change(
                                task,
                                () => ref
                                    .read(downloadManagerProvider)
                                    .retry(task.unitId)),
                            onCheck: () =>
                                showDownloadIntegrityDialog(context, task),
                            onDelete: () => _delete(context, ref, task),
                            onOpen: null,
                          ),
                        ),
                    ],
                    if (finished.isNotEmpty) ...[
                      SectionHeader(title: l10n.downloadsFinished),
                      for (final group in groups.values)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _FinishedGroup(
                            tasks: group,
                            work: works[group.first.mediaId],
                            onOpen: (task) => context.push(
                              Routes.reader(
                                sourceId: task.sourceId,
                                url: task.mediaUrl,
                                unitUrl: task.unitUrl,
                              ),
                            ),
                            onDeleteWork: () =>
                                _deleteWork(context, ref, group),
                            onDelete: (task) => _delete(context, ref, task),
                            onCheck: (task) =>
                                showDownloadIntegrityDialog(context, task),
                          ),
                        ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _change(
      DownloadTask task, Future<void> Function() action) async {
    if (!_busyTasks.add(task.unitId)) return;
    setState(() {});
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context).downloadFailed)));
      }
    } finally {
      if (mounted) setState(() => _busyTasks.remove(task.unitId));
    }
  }

  /// Deletes every finished unit of one work in one confirmation.
  Future<void> _deleteWork(
    BuildContext context,
    WidgetRef ref,
    List<DownloadTask> tasks,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.downloadDeleteTitle),
        content: Text(
            l10n.downloadDeleteShown(tasks.length, tasks.first.mediaTitle)),
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
    if (confirmed != true || !context.mounted) return;
    final manager = ref.read(downloadManagerProvider);
    for (final task in tasks) {
      await manager.cancel(task.unitId);
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.downloadRemoved)),
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
    if (confirmed != true || !context.mounted) return;
    await ref.read(downloadManagerProvider).cancel(task.unitId);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.downloadRemoved)),
    );
  }
}

/// One work with its finished chapters folded inside a single card.
class _FinishedGroup extends StatelessWidget {
  const _FinishedGroup({
    required this.tasks,
    required this.work,
    required this.onOpen,
    required this.onDeleteWork,
    required this.onDelete,
    required this.onCheck,
  });

  final List<DownloadTask> tasks;
  final Media? work;
  final ValueChanged<DownloadTask> onOpen;
  final VoidCallback onDeleteWork;
  final ValueChanged<DownloadTask> onDelete;
  final ValueChanged<DownloadTask> onCheck;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final bytes = tasks.fold<int>(0, (sum, task) => sum + task.bytes);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(BestRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(BestRadius.lg),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 50,
                      height: 68,
                      child: BestCover(
                        title: tasks.first.mediaTitle,
                        url: work?.coverUrl,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tasks.first.mediaTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${l10n.downloadChaptersCount(tasks.length)} · '
                          '${formatBytes(bytes)}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.downloadDeleteWork,
                    onPressed: onDeleteWork,
                    icon: const Icon(Icons.delete_sweep_outlined, size: 19),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: theme.colorScheme.outlineVariant),
            for (final task in tasks)
              _FinishedRow(
                key: ValueKey('download-${task.unitId}'),
                task: task,
                onOpen: () => onOpen(task),
                onDelete: () => onDelete(task),
                onCheck: () => onCheck(task),
              ),
          ],
        ),
      ),
    );
  }
}

class _FinishedRow extends StatelessWidget {
  const _FinishedRow({
    super.key,
    required this.task,
    required this.onOpen,
    required this.onDelete,
    required this.onCheck,
  });

  final DownloadTask task;
  final VoidCallback onOpen;
  final VoidCallback onDelete;
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(14, 4, 4, 4),
        child: Row(
          children: [
            const Icon(Icons.check_circle_rounded,
                size: 17, color: BestColors.jade),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                task.unitTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatBytes(task.bytes),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            PopupMenuButton<_DownloadAction>(
              tooltip: l10n.more,
              onSelected: (action) {
                switch (action) {
                  case _DownloadAction.check:
                    onCheck();
                  case _DownloadAction.delete:
                    onDelete();
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                    value: _DownloadAction.check,
                    child: Text(l10n.downloadCheck)),
                PopupMenuItem(
                    value: _DownloadAction.delete,
                    child: Text(l10n.downloadDelete)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DownloadTile extends StatelessWidget {
  const _DownloadTile({
    super.key,
    required this.task,
    required this.busy,
    required this.onPause,
    required this.onResume,
    required this.onRetry,
    required this.onDelete,
    required this.onOpen,
    required this.onCheck,
  });

  final DownloadTask task;
  final bool busy;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onRetry;
  final VoidCallback onDelete;
  final VoidCallback? onOpen;
  final VoidCallback onCheck;

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
                        downloadFailureLabel(l10n, task.error),
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
                busy: busy,
                onPause: onPause,
                onResume: onResume,
                onRetry: onRetry,
                onDelete: onDelete,
                onCheck: onCheck,
                onOpen: onOpen,
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
    required this.busy,
    required this.onPause,
    required this.onResume,
    required this.onRetry,
    required this.onDelete,
    required this.onCheck,
    required this.onOpen,
  });

  final DownloadTask task;
  final bool busy;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onRetry;
  final VoidCallback onDelete;
  final VoidCallback onCheck;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (task.isFinished)
          IconButton(
            tooltip: l10n.downloadOpen,
            onPressed: busy ? null : onOpen,
            icon: const Icon(Icons.menu_book_outlined, size: 20),
          )
        else if (task.isFailed)
          IconButton(
            tooltip: l10n.downloadRetry,
            onPressed: busy ? null : onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 20),
          )
        else if (task.isPaused)
          IconButton(
            tooltip: l10n.downloadResume,
            onPressed: busy ? null : onResume,
            icon: const Icon(Icons.play_arrow_rounded, size: 22),
          )
        else
          IconButton(
            tooltip: l10n.downloadPause,
            onPressed: busy ? null : onPause,
            icon: const Icon(Icons.pause_rounded, size: 20),
          ),
        PopupMenuButton<_DownloadAction>(
          enabled: !busy,
          tooltip: l10n.more,
          onSelected: (action) {
            switch (action) {
              case _DownloadAction.check:
                onCheck();
              case _DownloadAction.delete:
                onDelete();
            }
          },
          itemBuilder: (_) => [
            if (!task.isActive)
              PopupMenuItem(
                  value: _DownloadAction.check,
                  child: Text(l10n.downloadCheck)),
            PopupMenuItem(
                value: _DownloadAction.delete,
                child: Text(l10n.downloadDelete)),
          ],
        ),
      ],
    );
  }
}

enum _DownloadAction { check, delete }

class _WifiBanner extends StatelessWidget {
  const _WifiBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(BestRadius.md),
        color: BestColors.jade.withValues(alpha: 0.12),
        border: Border.all(color: BestColors.jade.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded, size: 16, color: BestColors.jade),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
