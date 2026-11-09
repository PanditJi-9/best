import 'media.dart';
import 'progress.dart';
import 'search_text.dart';
import 'units.dart';
import 'unit_navigation.dart';

enum LibraryFilter {
  all,
  unread,
  inProgress,
  completed,
  favorites,
  planned,
  paused,
  offline,
}

enum LibrarySort { title, recentlyRead, recentlyAdded, random }

/// The library search box understands plain words plus two prefixes:
///
/// * `src:<source id>` keeps one source, so a shelf can be read per catalogue.
/// * `tag:<category>` keeps one category without leaving the search box.
///
/// Commas separate plain/category terms and every term must match (AND).
/// Repeated source prefixes allow any of the named sources. Arabic commas are
/// accepted too, so the same syntax works with the Arabic keyboard.
class LibrarySearch {
  const LibrarySearch._({
    required this.terms,
    required this.sources,
    required this.tags,
  });

  factory LibrarySearch.parse(String raw) {
    final terms = <String>[];
    final sources = <String>{};
    final tags = <String>[];
    for (final part in raw.split(RegExp(r'[,،\n]'))) {
      final text = part.trim();
      if (text.isEmpty) continue;
      final lower = text.toLowerCase();
      if (lower.startsWith('src:')) {
        final value = SearchText.normalize(text.substring(4));
        if (value.isNotEmpty) sources.add(value);
      } else if (lower.startsWith('tag:')) {
        final value = text.substring(4).trim();
        if (value.isNotEmpty) tags.add(value);
      } else {
        terms.add(text);
      }
    }
    return LibrarySearch._(
      terms: List.unmodifiable(terms),
      sources: Set.unmodifiable(sources),
      tags: List.unmodifiable(tags),
    );
  }

  final List<String> terms;
  final Set<String> sources;
  final List<String> tags;

  bool get isEmpty => terms.isEmpty && sources.isEmpty && tags.isEmpty;

  bool matches(Media media) {
    if (sources.isNotEmpty &&
        !sources.contains(SearchText.normalize(media.ref.sourceId))) {
      return false;
    }
    for (final tag in tags) {
      if (!media.tags.any((name) => SearchText.matches(name, tag))) {
        return false;
      }
    }
    for (final term in terms) {
      if (!SearchText.matches(media.displayTitle, term) &&
          !SearchText.matches(media.nativeTitle ?? '', term) &&
          !SearchText.matches(media.author ?? '', term)) {
        return false;
      }
    }
    return true;
  }
}

/// The two shelves a person keeps apart. Reading (manga and its kin) and
/// watching (anime) never share a grid, a tab strip or a category list.
enum LibraryShelf {
  reading,
  watching;

  /// The shelf a work of this kind belongs on. Manga, manhwa, manhua and
  /// webtoons read; everything that plays is watched.
  static LibraryShelf of(MediaKind kind) =>
      kind.isReading ? reading : watching;

  bool contains(MediaKind kind) => of(kind) == this;
}

class LibraryQuery {
  const LibraryQuery({
    this.search = '',
    this.filter = LibraryFilter.all,
    this.sort = LibrarySort.recentlyRead,
    this.tag,
    this.hiddenTags = const {},
    this.includeHidden = false,
    this.shelf,
    this.uncategorized = false,
    this.randomSeed = 0,
  });

  final String search;
  final LibraryFilter filter;
  final LibrarySort sort;

  /// A new seed per shuffle keeps [LibrarySort.random] stable between rebuilds
  /// instead of reordering the shelf on every frame.
  final int randomSeed;

  /// One category (stored as a tag on the work) to narrow the shelf to.
  /// `null` means every category.
  final String? tag;

  /// Categories the person marked hidden. Works in them are left out of the
  /// shelf while [includeHidden] is false — the "nosy people" switch.
  final Set<String> hiddenTags;

  /// The person asked to reveal hidden categories for this session.
  final bool includeHidden;

  /// Only works of this shelf. `null` keeps every shelf (used by counts and
  /// by search across the whole library).
  final LibraryShelf? shelf;

  /// Only works with no category at all: the Default tab.
  final bool uncategorized;

  LibraryQuery copyWith({
    String? search,
    LibraryFilter? filter,
    LibrarySort? sort,
    String? tag,
    bool clearTag = false,
    Set<String>? hiddenTags,
    bool? includeHidden,
    LibraryShelf? shelf,
    bool? uncategorized,
    int? randomSeed,
  }) {
    return LibraryQuery(
      search: search ?? this.search,
      filter: filter ?? this.filter,
      sort: sort ?? this.sort,
      tag: clearTag ? null : (tag ?? this.tag),
      hiddenTags: hiddenTags ?? this.hiddenTags,
      includeHidden: includeHidden ?? this.includeHidden,
      shelf: shelf ?? this.shelf,
      uncategorized: uncategorized ?? this.uncategorized,
      randomSeed: randomSeed ?? this.randomSeed,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LibraryQuery &&
      other.search == search &&
      other.filter == filter &&
      other.sort == sort &&
      other.tag == tag &&
      other.includeHidden == includeHidden &&
      other.shelf == shelf &&
      other.uncategorized == uncategorized &&
      other.randomSeed == randomSeed &&
      other.hiddenTags.length == hiddenTags.length &&
      other.hiddenTags.containsAll(hiddenTags);

  @override
  int get hashCode => Object.hash(
        search,
        filter,
        sort,
        tag,
        includeHidden,
        shelf,
        uncategorized,
        randomSeed,
        Object.hashAllUnordered(hiddenTags),
      );
}

/// A shelf card: the work, how far the reader is, and the last thing opened.
class LibraryEntry {
  const LibraryEntry({
    required this.media,
    required this.totalUnits,
    required this.completedUnits,
    this.offlineUnits = 0,
    this.lastProgress,
  });

  final Media media;
  final int totalUnits;
  final int completedUnits;

  /// Units stored on this device. The shelf filter and the "offline" badge read
  /// this instead of asking the download manager per card.
  final int offlineUnits;
  final UnitProgress? lastProgress;

  double get fraction {
    if (totalUnits <= 0) return 0;
    return (completedUnits / totalUnits).clamp(0.0, 1.0);
  }

  int get unreadUnits => (totalUnits - completedUnits).clamp(0, totalUnits);
}

/// One unread unit that appeared after its work was already on the shelf.
class LibraryUpdate {
  const LibraryUpdate({
    required this.media,
    required this.unit,
    required this.firstSeenAt,
  });

  final Media media;
  final MediaUnit unit;
  final int firstSeenAt;
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

  static List<LibraryEntry> apply(
      Iterable<LibraryEntry> entries, LibraryQuery query) {
    final search = LibrarySearch.parse(query.search);
    final filtered =
        entries.where((entry) => _matches(entry, query, search)).toList();

    filtered.sort((a, b) {
      final byTitle = a.media.displayTitle
          .toLowerCase()
          .compareTo(b.media.displayTitle.toLowerCase());
      return switch (query.sort) {
        LibrarySort.title => byTitle,
        LibrarySort.recentlyRead =>
          _compareDesc(a.media.lastOpenedAt, b.media.lastOpenedAt, byTitle),
        LibrarySort.recentlyAdded =>
          _compareDesc(a.media.addedAt, b.media.addedAt, byTitle),
        LibrarySort.random =>
          _compareRandom(a.media.id, b.media.id, query.randomSeed, byTitle),
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
      if (!UnitNavigation.hasStarted(entry.progress)) continue;
      if (!entry.progress.completed) return entry;
      finished ??= entry;
    }
    return finished;
  }

  static bool _matches(
      LibraryEntry entry, LibraryQuery query, LibrarySearch search) {
    final media = entry.media;
    if (!media.inLibrary) return false;

    final shelf = query.shelf;
    if (shelf != null && !shelf.contains(media.kind)) return false;
    if (query.uncategorized &&
        media.tags.any((tag) => tag.trim().isNotEmpty)) {
      return false;
    }

    if (!search.matches(media)) return false;

    if (query.tag != null && !media.tags.contains(query.tag)) return false;

    if (!query.includeHidden &&
        query.hiddenTags.isNotEmpty &&
        media.tags.any(query.hiddenTags.contains)) {
      return false;
    }

    final started = entry.completedUnits > 0 ||
        UnitNavigation.hasStarted(entry.lastProgress);
    final finished =
        entry.totalUnits > 0 && entry.completedUnits >= entry.totalUnits;
    return switch (query.filter) {
      LibraryFilter.all => true,
      LibraryFilter.favorites => media.favorite,
      LibraryFilter.unread => !started,
      LibraryFilter.inProgress => started && !finished,
      LibraryFilter.completed => finished,
      LibraryFilter.planned => media.state == ReadingState.planned,
      LibraryFilter.paused => media.state == ReadingState.paused,
      LibraryFilter.offline => entry.offlineUnits > 0,
    };
  }

  static int _compareDesc(int a, int b, int fallback) {
    final result = b.compareTo(a);
    return result != 0 ? result : fallback;
  }

  /// A seeded FNV-1a order, identical whenever the same query is applied.
  /// `Object.hash` cannot be used here: its seed is per-isolate.
  static int _compareRandom(String a, String b, int seed, int fallback) {
    if (seed == 0) return fallback;
    final result = _seedHash(a, seed).compareTo(_seedHash(b, seed));
    return result != 0 ? result : fallback;
  }

  static int _seedHash(String value, int seed) {
    var hash = 0x811c9dc5 ^ (seed & 0xffffffff);
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash;
  }
}
