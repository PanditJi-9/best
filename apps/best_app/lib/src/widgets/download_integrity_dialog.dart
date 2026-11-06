import 'dart:async';

import 'package:best_data/best_data.dart';
import 'package:best_domain/best_domain.dart';
import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/generated/app_localizations.dart';
import '../navigation.dart';
import '../providers.dart';

Future<void> showDownloadIntegrityDialog(
  BuildContext context,
  DownloadTask task,
) =>
    showDialog<void>(
      context: context,
      builder: (_) => DownloadIntegrityDialog(task: task),
    );

/// The same local-only check and explicit repair boundary in Downloads and the
/// reader. A file checksum is never presented as an image-decoding guarantee.
class DownloadIntegrityDialog extends ConsumerStatefulWidget {
  const DownloadIntegrityDialog({super.key, required this.task});

  final DownloadTask task;

  @override
  ConsumerState<DownloadIntegrityDialog> createState() =>
      _DownloadIntegrityDialogState();
}

class _DownloadIntegrityDialogState
    extends ConsumerState<DownloadIntegrityDialog> {
  DownloadIntegrityReport? _report;
  Object? _error;
  bool _checking = true;
  bool _repairing = false;
  bool _queued = false;
  bool _finalized = false;

  @override
  void initState() {
    super.initState();
    unawaited(_check());
  }

  Future<void> _check() async {
    if (!mounted) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final report = await ref
          .read(downloadManagerProvider)
          .checkStored(widget.task.unitId);
      if (mounted) setState(() => _report = report);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _repair() async {
    if (_checking || _repairing) return;
    setState(() {
      _repairing = true;
      _error = null;
    });
    try {
      final report =
          await ref.read(downloadManagerProvider).repair(widget.task.unitId);
      if (!mounted) return;
      setState(() {
        _report = report;
        _queued = !report.busy && !report.isComplete;
        _finalized = report.isComplete;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _repairing = false);
    }
  }

  Future<void> _pauseAndCheck() async {
    setState(() => _checking = true);
    try {
      await ref.read(downloadManagerProvider).pause(widget.task.unitId);
      if (!mounted) return;
      await _check();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _checking = false;
        });
      }
    }
  }

  void _openSources() {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.push(Routes.sources);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final report = _report;
    final sourceMissing =
        ref.watch(sourceRegistryProvider).byId(widget.task.sourceId) == null;
    final needsSource =
        sourceMissing && report != null && !report.isComplete && !report.busy;
    final busy = _checking || _repairing;
    final error = _error;
    final removed = error is DownloadException &&
        error.message == DownloadException.removedMessage;
    final canRepair = !busy &&
        _error == null &&
        !_queued &&
        !_finalized &&
        report != null &&
        !report.busy &&
        (!report.isComplete || !widget.task.isFinished) &&
        !needsSource;

    return AlertDialog(
      title: Text(l10n.downloadCheck),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.task.mediaTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall),
            Text(widget.task.unitTitle,
                maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: BestSpace.lg),
            if (busy) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: BestSpace.md),
              Text(_repairing
                  ? l10n.downloadRepairPreparing
                  : l10n.downloadChecking),
            ] else if (_queued) ...[
              Text(l10n.downloadRepairQueued,
                  style: theme.textTheme.titleSmall),
              const SizedBox(height: BestSpace.sm),
              Text(l10n.downloadRepairBody),
              if (ref.watch(settingsProvider).wifiOnly)
                Padding(
                    padding: const EdgeInsets.only(top: BestSpace.sm),
                    child: Text(l10n.wifiOnlyBody)),
            ] else if (report != null) ...[
              Text(
                  report.busy
                      ? l10n.downloadCheckBusy
                      : report.isComplete
                          ? l10n.downloadFilesAvailable
                          : report.total <= 0
                              ? l10n.downloadUnknownTotalTitle
                              : l10n.downloadIntegrityProblems,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: report.hasProblems ? theme.colorScheme.error : null,
                  )),
              const SizedBox(height: BestSpace.sm),
              if (!report.busy) ...[
                if (report.total > 0)
                  Text(l10n.downloadIntegrityCount(
                      report.available, report.total)),
                if (report.verified > 0)
                  Text(l10n.downloadIntegrityVerified(report.verified)),
                if (report.total <= 0) Text(l10n.downloadIntegrityUnknown),
                if (report.missing.isNotEmpty)
                  _pages(l10n.downloadIntegrityMissing(report.missing.length),
                      report.missing),
                if (report.changed.isNotEmpty)
                  _pages(l10n.downloadIntegrityChanged(report.changed.length),
                      report.changed),
                if (report.available > report.verified) ...[
                  const SizedBox(height: BestSpace.sm),
                  Text(l10n.downloadIntegrityLegacy(
                      report.available - report.verified)),
                ],
                const SizedBox(height: BestSpace.md),
                Text(l10n.downloadIntegrityScope,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.5)),
                if (!report.isComplete) ...[
                  const SizedBox(height: BestSpace.sm),
                  Text(l10n.downloadRepairBody),
                ],
                if (needsSource) ...[
                  const SizedBox(height: BestSpace.md),
                  Text(l10n.sourceNotInstalledBody),
                ],
              ],
            ],
            if (_error != null && !busy) ...[
              const SizedBox(height: BestSpace.md),
              Text(
                  removed
                      ? l10n.downloadUnavailable
                      : _error is SourceNotInstalled
                          ? l10n.sourceNotInstalledBody
                          : l10n.downloadCheckFailed,
                  style: TextStyle(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(MaterialLocalizations.of(context).closeButtonLabel)),
        if (_error != null && !busy && !removed)
          TextButton(onPressed: _check, child: Text(l10n.retry)),
        if (!busy && report?.busy == true)
          TextButton(
              onPressed: _pauseAndCheck, child: Text(l10n.downloadPause)),
        if (!busy && (needsSource || _error is SourceNotInstalled))
          FilledButton.icon(
              onPressed: _openSources,
              icon: const Icon(Icons.extension_outlined, size: 18),
              label: Text(l10n.directoryTitle)),
        if (canRepair)
          FilledButton.icon(
              onPressed: _repair,
              icon: const Icon(Icons.build_outlined, size: 18),
              label: Text(l10n.downloadRepair)),
      ],
    );
  }

  Widget _pages(String label, List<int> pages) => Padding(
        padding: const EdgeInsets.only(top: BestSpace.sm),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label),
          Text(
              '${pages.take(12).map((page) => page + 1).join(', ')}${pages.length > 12 ? ' …' : ''}',
              textDirection: TextDirection.ltr,
              style: Theme.of(context).textTheme.bodySmall),
        ]),
      );
}

/// Persisted engine diagnostics are not UI copy, and can contain source URLs.
/// Keep common failures useful and localized without displaying private paths.
String downloadFailureLabel(AppLocalizations l10n, String? error) {
  if (error == DownloadException.storedPagesChanged) {
    return l10n.downloadIntegrityProblems;
  }
  if (error == DownloadException.sourceIncomplete) {
    return l10n.downloadSourceIncomplete;
  }
  if (error == DownloadException.sourceMissing) {
    return l10n.sourceNotInstalledTitle;
  }
  if (error == DownloadException.countUnknown) {
    return l10n.downloadUnknownTotalTitle;
  }
  if (error != null && RegExp(r'^HTTP \d{3}$').hasMatch(error)) {
    return '${l10n.downloadFailed} · $error';
  }
  return l10n.downloadFailed;
}
