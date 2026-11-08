import 'package:best_domain/best_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';
import '../providers.dart';

/// Asks once, then cancels and removes the files of one download.
Future<void> showDownloadDeleteDialog(
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

/// Asks once, then cancels every listed download of one work.
Future<void> showWorkDownloadsDeleteDialog(
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
