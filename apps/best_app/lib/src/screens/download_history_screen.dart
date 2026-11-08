import 'package:best_domain/best_domain.dart';
import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/generated/app_localizations.dart';
import '../labels.dart';
import '../navigation.dart';
import '../providers.dart';
import '../widgets/download_delete_dialog.dart';
import '../widgets/download_integrity_dialog.dart';

/// Finished chapters, grouped by work the way the Downloads tab used to show
/// them. Each work is a card with its cover and title; its chapters stay folded
/// until the card is opened.
class DownloadHistoryScreen extends ConsumerStatefulWidget {
  const DownloadHistoryScreen({super.key});

  @override
  ConsumerState<DownloadHistoryScreen> createState() =>
      _DownloadHistoryScreenState();
}

class _DownloadHistoryScreenState extends ConsumerState<DownloadHistoryScreen> {
  /// Works whose chapters are showing. Every work starts folded.
  final Set<String> _openWorks = {};

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final tasks = (ref.watch(downloadsProvider).value ?? const <DownloadTask>[])
        .where((task) => task.isFinished)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    // Works are listed by their newest finished chapter, and each work's
    // chapters keep that same order.
    final groups = <String, List<DownloadTask>>{};
    for (final task in tasks) {
      groups.putIfAbsent(task.mediaId, () => <DownloadTask>[]).add(task);
    }
    final sections = groups.values.toList(growable: false);
    final works = <String, Media>{
      for (final entry
          in ref.watch(allLibraryProvider).value ?? const <LibraryEntry>[])
        entry.media.id: entry.media,
    };

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
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              itemCount: sections.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      l10n.downloadsHistorySubtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }
                final group = sections[index - 1];
                final mediaId = group.first.mediaId;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _FinishedGroup(
                    tasks: group,
                    work: works[mediaId],
                    open: _openWorks.contains(mediaId),
                    onToggle: () => _toggle(mediaId),
                    onOpen: (task) => context.push(
                      Routes.reader(
                        sourceId: task.sourceId,
                        url: task.mediaUrl,
                        unitUrl: task.unitUrl,
                      ),
                    ),
                    onDeleteWork: () =>
                        showWorkDownloadsDeleteDialog(context, ref, group),
                    onDelete: (task) =>
                        showDownloadDeleteDialog(context, ref, task),
                    onCheck: (task) =>
                        showDownloadIntegrityDialog(context, task),
                  ),
                );
              },
            ),
    );
  }

  void _toggle(String mediaId) {
    setState(() {
      if (!_openWorks.add(mediaId)) _openWorks.remove(mediaId);
    });
  }
}

/// One work: cover, title and count on the header, its chapters folded below.
class _FinishedGroup extends StatelessWidget {
  const _FinishedGroup({
    required this.tasks,
    required this.work,
    required this.open,
    required this.onToggle,
    required this.onOpen,
    required this.onDeleteWork,
    required this.onDelete,
    required this.onCheck,
  });

  final List<DownloadTask> tasks;
  final Media? work;
  final bool open;
  final VoidCallback onToggle;
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
            InkWell(
              onTap: onToggle,
              child: Padding(
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
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: AnimatedRotation(
                        turns: open ? 0.5 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          Icons.expand_more_rounded,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: open
                  ? Column(
                      children: [
                        Divider(
                            height: 1, color: theme.colorScheme.outlineVariant),
                        for (final task in tasks)
                          _FinishedRow(
                            key: ValueKey('download-${task.unitId}'),
                            task: task,
                            onOpen: () => onOpen(task),
                            onDelete: () => onDelete(task),
                            onCheck: () => onCheck(task),
                          ),
                      ],
                    )
                  : const SizedBox(width: double.infinity),
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
            PopupMenuButton<_FinishedAction>(
              tooltip: l10n.more,
              onSelected: (action) {
                switch (action) {
                  case _FinishedAction.check:
                    onCheck();
                  case _FinishedAction.delete:
                    onDelete();
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                    value: _FinishedAction.check,
                    child: Text(l10n.downloadCheck)),
                PopupMenuItem(
                    value: _FinishedAction.delete,
                    child: Text(l10n.downloadDelete)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _FinishedAction { check, delete }
