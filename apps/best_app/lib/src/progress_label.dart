import 'package:best_domain/best_domain.dart';

import 'labels.dart';
import 'l10n/generated/app_localizations.dart';

/// The one-line state under a continue card, shared by Home and Library.
///
/// Reading counts pages, watching counts seconds; the label never guesses.
String continueProgressLabel(
  AppLocalizations l10n,
  ContinueEntry entry,
) {
  if (entry.media.kind.isWatching) {
    if (entry.progress.total <= 0) return l10n.continueWatching;
    return l10n.watchProgress(
      formatClock(entry.progress.position),
      formatClock(entry.progress.total),
    );
  }
  if (entry.progress.total <= 0) return l10n.continueReading;
  return l10n.pageOf(
    (entry.progress.position + 1).clamp(1, entry.progress.total),
    entry.progress.total,
  );
}
