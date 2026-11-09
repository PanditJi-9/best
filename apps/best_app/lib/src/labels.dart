import 'package:best_domain/best_domain.dart';
import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';

import 'l10n/generated/app_localizations.dart';

String kindLabel(AppLocalizations l10n, MediaKind kind) => switch (kind) {
      MediaKind.manga => l10n.kindManga,
      MediaKind.manhwa => l10n.kindManhwa,
      MediaKind.manhua => l10n.kindManhua,
      MediaKind.webtoon => l10n.kindWebtoon,
      MediaKind.anime => l10n.kindAnime,
      MediaKind.drama => l10n.kindDrama,
      MediaKind.film => l10n.kindFilm,
    };

String statusLabel(AppLocalizations l10n, MediaStatus status) =>
    switch (status) {
      MediaStatus.ongoing => l10n.statusOngoing,
      MediaStatus.completed => l10n.statusCompleted,
      MediaStatus.hiatus => l10n.statusHiatus,
      MediaStatus.cancelled => l10n.statusCancelled,
      MediaStatus.unknown => l10n.statusUnknown,
    };

String filterLabel(AppLocalizations l10n, LibraryFilter filter) =>
    switch (filter) {
      LibraryFilter.all => l10n.filterAll,
      LibraryFilter.unread => l10n.filterUnread,
      LibraryFilter.inProgress => l10n.filterInProgress,
      LibraryFilter.completed => l10n.filterCompleted,
      LibraryFilter.favorites => l10n.filterFavorites,
      LibraryFilter.planned => l10n.filterPlanned,
      LibraryFilter.paused => l10n.filterPaused,
      LibraryFilter.offline => l10n.filterOffline,
    };

/// The person's plan, in the words the shelf uses for it.
String stateLabel(AppLocalizations l10n, ReadingState state) => switch (state) {
      ReadingState.none => '',
      ReadingState.reading => l10n.stateReading,
      ReadingState.planned => l10n.statePlanned,
      ReadingState.paused => l10n.statePaused,
    };

String sortLabel(AppLocalizations l10n, LibrarySort sort) => switch (sort) {
      LibrarySort.title => l10n.sortTitle,
      LibrarySort.recentlyRead => l10n.sortRecentlyRead,
      LibrarySort.recentlyAdded => l10n.sortRecentlyAdded,
      LibrarySort.random => l10n.sortRandom,
    };

String themeLabel(AppLocalizations l10n, ThemeMode mode) => switch (mode) {
      ThemeMode.system => l10n.themeSystem,
      ThemeMode.light => l10n.themeLight,
      ThemeMode.dark => l10n.themeDark,
    };

String shortNumber(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toString();
}

/// A chapter or episode label that speaks the app's language.
///
/// Sources often ship "Episode 1" or "Chapter 12" as a title. In an Arabic
/// interface that is a raw English fallback, not a title, so a generic label
/// is rebuilt from the unit's number. A real title is left untouched.
final RegExp _genericUnitTitle = RegExp(
  r'^(?:chapter|episode|ch|ep|chap)\.?\s*#?\s*(\d+(?:\.\d+)?)$',
  caseSensitive: false,
);

/// A title that is only a number ("0", "12.5") names no chapter by itself.
final RegExp _bareNumber = RegExp(r'^[0-9٠-٩]+([.,][0-9٠-٩]+)?$');

String unitTitle(AppLocalizations l10n, MediaUnit unit) {
  final title = unit.title.trim();
  final match = _genericUnitTitle.firstMatch(title);
  final number = match == null
      ? shortNumber(unit.number)
      : shortNumber(double.tryParse(match.group(1)!) ?? unit.number);
  if (title.isEmpty || match != null || _bareNumber.hasMatch(title)) {
    return unit.kind == UnitKind.chapter
        ? l10n.unitChapterTitle(number)
        : l10n.unitEpisodeTitle(number);
  }
  return title;
}

String shortDate(int epochMillis) {
  if (epochMillis <= 0) return '';
  final date = DateTime.fromMillisecondsSinceEpoch(epochMillis);
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  // A machine date is LTR even inside an Arabic paragraph: without the
  // isolate, bidi reorders 2026-11-07 into 07-11-2026.
  return ltrIsolate('${date.year}-$month-$day');
}

/// Time of day for a history row. The day is already the section header.
String shortTime(int epochMillis) {
  if (epochMillis <= 0) return '';
  final date = DateTime.fromMillisecondsSinceEpoch(epochMillis);
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return ltrIsolate('$hour:$minute');
}

/// Date and 24-hour time for source health evidence.
String shortDateTime(int epochMillis) {
  if (epochMillis <= 0) return '';
  final date = DateTime.fromMillisecondsSinceEpoch(epochMillis);
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return ltrIsolate('${date.year}-$month-$day $hour:$minute');
}

/// Storage sizes are units, not prose: the same "12.4 MB" reads correctly in
/// both languages and matches what the system settings show.
String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final decimals = unit == 0 || value >= 100 ? 0 : 1;
  return '${value.toStringAsFixed(decimals)} ${units[unit]}';
}

/// A clock for video controls and the continue rail.
///
/// Hours appear only when they exist, so an episode reads `24:10` while a film
/// reads `1:42:06`. Digits stay Western in both languages: a scrubber is a
/// number line, not prose.
String formatClock(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  final hours = safe ~/ 3600;
  final minutes = (safe % 3600) ~/ 60;
  final secs = safe % 60;
  final two = secs.toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$two';
  }
  return '$minutes:$two';
}
