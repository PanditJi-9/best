import 'package:best_domain/best_domain.dart';
import 'package:test/test.dart';

void main() {
  Media work(String title, MediaKind kind, {List<String> tags = const []}) {
    return Media(
      ref: SourceRef('demo', title),
      title: title,
      kind: kind,
      inLibrary: true,
      tags: tags,
    );
  }

  final entries = [
    LibraryEntry(
      media: work('Manga A', MediaKind.manga, tags: ['Favorites']),
      totalUnits: 0,
      completedUnits: 0,
    ),
    LibraryEntry(
      media: work('Manhwa B', MediaKind.manhwa),
      totalUnits: 0,
      completedUnits: 0,
    ),
    LibraryEntry(
      media: work('Anime C', MediaKind.anime, tags: ['Favorites']),
      totalUnits: 0,
      completedUnits: 0,
    ),
    LibraryEntry(
      media: work('Anime D', MediaKind.anime),
      totalUnits: 0,
      completedUnits: 0,
    ),
  ];

  List<String> titles(LibraryQuery query) {
    return [
      for (final entry in LibraryPolicy.apply(entries, query))
        entry.media.title,
    ];
  }

  group('library shelves', () {
    test('every kind belongs to exactly one shelf', () {
      expect(LibraryShelf.of(MediaKind.manga), LibraryShelf.reading);
      expect(LibraryShelf.of(MediaKind.webtoon), LibraryShelf.reading);
      expect(LibraryShelf.of(MediaKind.anime), LibraryShelf.watching);
      expect(LibraryShelf.of(MediaKind.film), LibraryShelf.watching);
      expect(LibraryShelf.reading.contains(MediaKind.anime), isFalse);
      expect(LibraryShelf.watching.contains(MediaKind.manhwa), isFalse);
    });

    test('a shelf shows only works of its own kind', () {
      expect(
        titles(const LibraryQuery(
          shelf: LibraryShelf.reading,
          sort: LibrarySort.title,
        )),
        ['Manga A', 'Manhwa B'],
      );
      expect(
        titles(const LibraryQuery(
          shelf: LibraryShelf.watching,
          sort: LibrarySort.title,
        )),
        ['Anime C', 'Anime D'],
      );
    });

    test('the Default tab holds only works with no category on that shelf',
        () {
      expect(
        titles(const LibraryQuery(
          shelf: LibraryShelf.reading,
          uncategorized: true,
          sort: LibrarySort.title,
        )),
        ['Manhwa B'],
      );
      expect(
        titles(const LibraryQuery(
          shelf: LibraryShelf.watching,
          uncategorized: true,
          sort: LibrarySort.title,
        )),
        ['Anime D'],
      );
    });

    test('a category tab holds its works of that shelf only', () {
      expect(
        titles(const LibraryQuery(
          shelf: LibraryShelf.reading,
          tag: 'Favorites',
          sort: LibrarySort.title,
        )),
        ['Manga A'],
      );
      expect(
        titles(const LibraryQuery(
          shelf: LibraryShelf.watching,
          tag: 'Favorites',
          sort: LibrarySort.title,
        )),
        ['Anime C'],
      );
    });

    test('without a shelf every kind stays, as counts and search expect', () {
      expect(
        titles(const LibraryQuery(sort: LibrarySort.title)),
        hasLength(4),
      );
    });
  });
}
