import 'package:best_domain/best_domain.dart';
import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/generated/app_localizations.dart';
import '../navigation.dart';
import '../providers.dart';
import 'download_integrity_dialog.dart';

class ReaderDownloadTile extends ConsumerStatefulWidget {
  const ReaderDownloadTile(
      {super.key, required this.media, required this.unit});

  final Media media;
  final MediaUnit unit;

  @override
  ConsumerState<ReaderDownloadTile> createState() => _ReaderDownloadTileState();
}

class _ReaderDownloadTileState extends ConsumerState<ReaderDownloadTile> {
  bool _busy = false;

  Future<void> _change(DownloadTask? task) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final manager = ref.read(downloadManagerProvider);
      if (task == null) {
        await manager.enqueue(widget.media, widget.unit);
      } else if (task.isActive) {
        await manager.pause(task.unitId);
      } else if (task.isPaused) {
        await manager.resume(task.unitId);
      } else if (task.isFailed) {
        await manager.retry(task.unitId);
      } else {
        await showDownloadIntegrityDialog(context, task);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context).downloadFailed)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final task = ref.watch(downloadForProvider(widget.unit.id)).value;
    final sourceMissing =
        ref.watch(sourceRegistryProvider).byId(widget.media.ref.sourceId) ==
            null;
    final needsSource =
        sourceMissing && task?.isFinished != true && task?.isActive != true;
    final label = switch (task?.status) {
      DownloadStatus.queued => l10n.readerDownloadQueued,
      DownloadStatus.running => l10n.readerDownloading,
      DownloadStatus.paused => l10n.downloadPaused,
      DownloadStatus.failed => downloadFailureLabel(l10n, task?.error),
      DownloadStatus.done => l10n.readerDownloaded,
      null => l10n.readerDownload,
    };
    final action = needsSource
        ? l10n.directoryTitle
        : switch (task?.status) {
            DownloadStatus.queued ||
            DownloadStatus.running =>
              l10n.downloadPause,
            DownloadStatus.paused => l10n.downloadResume,
            DownloadStatus.failed => l10n.downloadRetry,
            DownloadStatus.done => l10n.downloadCheck,
            null => l10n.downloadChapter,
          };
    final icon = needsSource
        ? Icons.extension_outlined
        : switch (task?.status) {
            DownloadStatus.queued ||
            DownloadStatus.running =>
              Icons.pause_rounded,
            DownloadStatus.paused => Icons.play_arrow_rounded,
            DownloadStatus.failed => Icons.refresh_rounded,
            DownloadStatus.done => Icons.fact_check_outlined,
            null => Icons.download_rounded,
          };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(BestRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(BestSpace.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(
                task?.isFinished == true
                    ? Icons.offline_pin_rounded
                    : Icons.download_for_offline_outlined,
                size: 22,
                color: task?.isFinished == true ? BestColors.jade : null),
            const SizedBox(width: BestSpace.md),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(l10n.readerDownload, style: theme.textTheme.titleSmall),
                  Text(label,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: task?.isFailed == true
                              ? theme.colorScheme.error
                              : theme.colorScheme.onSurfaceVariant)),
                  if (task != null && task.total > 0)
                    Text(l10n.downloadProgress(task.completed, task.total),
                        style: theme.textTheme.bodySmall),
                ])),
            if (_busy)
              const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2))
            else
              IconButton(
                tooltip: action,
                onPressed: needsSource
                    ? () => context.push(Routes.sources)
                    : () => _change(task),
                icon: Icon(icon),
              ),
          ]),
          if (task?.isActive == true) ...[
            const SizedBox(height: BestSpace.md),
            LinearProgressIndicator(
                value: task!.total > 0 ? task.progress : null),
          ],
          if (task != null && !task.isActive && !task.isFinished)
            TextButton.icon(
                onPressed: _busy
                    ? null
                    : () => showDownloadIntegrityDialog(context, task),
                icon: const Icon(Icons.fact_check_outlined, size: 18),
                label: Text(l10n.downloadCheck)),
        ]),
      ),
    );
  }
}
