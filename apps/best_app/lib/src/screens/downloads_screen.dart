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

class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

enum _DownloadFilter { all, ready, failed, queue }

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  _DownloadFilter _filter = _DownloadFilter.all;
  final _search = TextEditingController();
  final Set<String> _busyTasks = {};
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _search.clear();
    setState(() {
      _query = '';
      _filter = _DownloadFilter.all;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final downloads = ref.watch(downloadsProvider);
    final current = downloads.value ?? const <DownloadTask>[];
    final query = SearchText.normalize(_query).trim();
    final numberQuery = query.replaceFirst(
      RegExp(r'^(?:chapter|chap\.?|ch\.?|الفصل|فصل)\s*'),
      '',
    );
    final visible = current.where((task) {
      final matches = query.isEmpty ||
          SearchText.matches('${task.mediaTitle} ${task.unitTitle}', query) ||
          (numberQuery != query &&
              numberQuery.isNotEmpty &&
              SearchText.matches(task.unitTitle, numberQuery));
      if (!matches) return false;
      return switch (_filter) {
        _DownloadFilter.all => true,
        _DownloadFilter.ready => task.isFinished,
        _DownloadFilter.queue => !task.isFinished,
        _DownloadFilter.failed => task.isFailed,
      };
    }).toList();
    final finished = visible.where((task) => task.isFinished).toList();
    final active = visible.where((task) => !task.isFinished).toList();
    final allFinished = current.where((task) => task.isFinished).length;
    final allFailed = current.where((task) => task.isFailed).length;
    final totalBytes = current.fold<int>(0, (sum, task) => sum + task.bytes);
    final settings = ref.watch(settingsProvider);
    final waitingForWifi = settings.wifiOnly &&
        ref.watch(networkProvider).value == NetworkKind.mobile;
    final groups = <String, List<DownloadTask>>{};
    for (final task in finished) {
      groups.putIfAbsent(task.mediaId, () => <DownloadTask>[]).add(task);
    }

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
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
                if (finished.isNotEmpty)
                  IconButton(
                    tooltip: l10n.downloadClearFinished,
                    onPressed: () => _clearFinished(context, ref, finished),
                    icon: const Icon(Icons.delete_sweep_outlined),
                  ),
              ],
            ),
          ),
          if (current.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  BestLayout.gutter, BestSpace.md, BestLayout.gutter, 0),
              child: TextField(
                key: const ValueKey('downloads-search'),
                controller: _search,
                textInputAction: TextInputAction.search,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: l10n.downloadsSearch,
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: MaterialLocalizations.of(context)
                              .closeButtonTooltip,
                          onPressed: () {
                            _search.clear();
                            setState(() => _query = '');
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
              ),
            ),
          if (current.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final filter in _DownloadFilter.values)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 8),
                        child: ChoiceChip(
                          selected: _filter == filter,
                          onSelected: (_) => setState(() => _filter = filter),
                          label: Text(switch (filter) {
                            _DownloadFilter.all => l10n.filterAll,
                            _DownloadFilter.ready =>
                              '${l10n.offlineLabel} · $allFinished',
                            _DownloadFilter.queue =>
                              '${l10n.downloadsInProgress} · ${current.length - allFinished}',
                            _DownloadFilter.failed =>
                              '${l10n.downloadsFailedFilter} · $allFailed',
                          }),
                        ),
                      ),
                  ],
                ),
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
                          onPressed: () => context.push(Routes.manga),
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
                    if (visible.isEmpty)
                      EmptyState(
                        icon: Icons.filter_list_rounded,
                        title: l10n.downloadFilterEmpty,
                        body: l10n.downloadFilterEmptyBody,
                        action: TextButton(
                          onPressed: _clearSearch,
                          child: Text(l10n.downloadsClearSearch),
                        ),
                      ),
                    if (_filter != _DownloadFilter.ready &&
                        active.any((task) => task.isActive) &&
                        waitingForWifi)
                      _WifiBanner(text: l10n.wifiWaiting),
                    if (_filter != _DownloadFilter.ready &&
                        active.isNotEmpty) ...[
                      SectionHeader(
                          title: _filter == _DownloadFilter.failed
                              ? l10n.downloadsFailedFilter
                              : l10n.downloadsInProgress),
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
                    if (_filter != _DownloadFilter.queue &&
                        finished.isNotEmpty) ...[
                      SectionHeader(title: l10n.downloadsFinished),
                      for (final group in groups.values) ...[
                        _WorkHeader(
                          title: group.first.mediaTitle,
                          bytes: group.fold<int>(
                            0,
                            (sum, task) => sum + task.bytes,
                          ),
                          unitCount: group.length,
                          onDelete: () => _deleteWork(context, ref, group),
                        ),
                        for (final task in group)
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
    if (confirmed != true || !context.mounted) return;
    final manager = ref.read(downloadManagerProvider);
    for (final task in finished) {
      await manager.cancel(task.unitId);
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.downloadClearDone)),
    );
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

/// The work's own header above its finished chapters: how much it costs on
/// disk, and one control to reclaim it.
class _WorkHeader extends StatelessWidget {
  const _WorkHeader({
    required this.title,
    required this.bytes,
    required this.unitCount,
    required this.onDelete,
  });

  final String title;
  final int bytes;
  final int unitCount;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 2, 0, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${formatBytes(bytes)} · $unitCount',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: AppLocalizations.of(context).downloadDeleteWork,
            onPressed: onDelete,
            icon: const Icon(Icons.delete_sweep_outlined, size: 19),
          ),
        ],
      ),
    );
  }
}

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
