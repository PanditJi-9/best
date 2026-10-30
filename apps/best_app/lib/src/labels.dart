import 'package:best_domain/best_domain.dart';
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
    };

String sortLabel(AppLocalizations l10n, LibrarySort sort) => switch (sort) {
      LibrarySort.title => l10n.sortTitle,
      LibrarySort.recentlyRead => l10n.sortRecentlyRead,
      LibrarySort.recentlyAdded => l10n.sortRecentlyAdded,
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

String shortDate(int epochMillis) {
  if (epochMillis <= 0) return '';
  final date = DateTime.fromMillisecondsSinceEpoch(epochMillis);
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}
