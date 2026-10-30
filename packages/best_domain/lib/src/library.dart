import 'media.dart';
import 'progress.dart';
import 'search_text.dart';
import 'units.dart';

enum LibraryFilter { all, unread, inProgress, completed, favorites }

enum LibrarySort { title, recentlyRead, recentlyAdded }

class LibraryQuery {
  const LibraryQuery({
    this.search = '',
    this.filter = LibraryFilter.all,
    this.sort = LibrarySort.recentlyRead,
  });

  final String search;
  final LibraryFilter filter;
  final LibrarySort sort;

  LibraryQuery copyWith({String? search, LibraryFilter? filter, LibrarySort? sort}) {
    return LibraryQuery(
      search: search ?? this.search,
      filter: filter ?? this.filter,
      sort: sort ?? this.sort,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LibraryQuery &&
      other.search == search &&
      other.filter == filter &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(search, filter, sort);
}

/// A shelf card: the work, how far the reader is, and the last thing opened.
class LibraryEntry {
  const LibraryEntry({
    required this.media,
    required this.totalUnits,
    required this.completedUnits,
    this.lastProgress,
  });

  final Media media;
  final int totalUnits;
  final int completedUnits;
  final UnitProgress? lastProgress;

  double get fraction {
    if (totalUnits <= 0) return 0;
    return (completedUnits / totalUnits).clamp(0.0, 1.0);
  }

  int get unreadUnits => (totalUnits - completedUnits).clamp(0, totalUnits);
}

/// The row the "continue" rail opens directly.
class ContinueEntry {
  const ContinueEntry({
    required this.media,
    required this.unit,
    required this.progress,
  });

  final Media media;
  final MediaUnit unit;
  final UnitProgress progress;
}

/// Pure shelf rules. Kept out of the database so they can be tested without one
/// and reused by the web client.
class LibraryPolicy {
  const LibraryPolicy._();

  static List<LibraryEntry> apply(Iterable<LibraryEntry> entries, LibraryQuery query) {
    final filtered = entries.where((entry) => _matches(entry, query)).toList();

    filtered.sort((a, b) {
      final byTitle = a.media.displayTitle
          .toLowerCase()
          .compareTo(b.media.displayTitle.toLowerCase());
      return switch (query.sort) {
        LibrarySort.title => byTitle,
        LibrarySort.recentlyRead => _compareDesc(a.media.lastOpenedAt, b.media.lastOpenedAt, byTitle),
        LibrarySort.recentlyAdded => _compareDesc(a.media.addedAt, b.media.addedAt, byTitle),
      };
    });

    return List.unmodifiable(filtered);
  }

  /// The unit a person actually had open most recently.
  ///
  /// The caller supplies rows ordered by `progress.updatedAt` descending. A
  /// finished unit is skipped: "continue" must not offer a chapter that is
  /// already done when another one is in progress. If nothing is in progress,
  /// the newest finished unit is returned so the rail still explains where the
  /// reader stopped.
  static ContinueEntry? pickContinue(Iterable<ContinueEntry> entries) {
    ContinueEntry? finished;
    for (final entry in entries) {
      if (entry.progress.position <= 0) continue;
      if (!entry.progress.completed) return entry;
      finished ??= entry;
    }
    return finished;
  }

  static bool _matches(LibraryEntry entry, LibraryQuery query) {
    final media = entry.media;
    if (!media.inLibrary) return false;

    if (!SearchText.matches(media.displayTitle, query.search) &&
        !SearchText.matches(media.nativeTitle ?? '', query.search) &&
        !SearchText.matches(media.author ?? '', query.search)) {
      return false;
    }

    return switch (query.filter) {
      LibraryFilter.all => true,
      LibraryFilter.favorites => media.favorite,
      LibraryFilter.unread => entry.completedUnits == 0,
      LibraryFilter.inProgress =>
        entry.completedUnits > 0 && entry.completedUnits < entry.totalUnits,
      LibraryFilter.completed =>
        entry.totalUnits > 0 && entry.completedUnits >= entry.totalUnits,
    };
  }

  static int _compareDesc(int a, int b, int fallback) {
    final result = b.compareTo(a);
    return result != 0 ? result : fallback;
  }
}
