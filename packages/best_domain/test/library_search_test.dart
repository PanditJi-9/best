import 'package:best_domain/best_domain.dart';
import 'package:test/test.dart';

Media _media(
  String url, {
  required String title,
  String source = 'mangadex',
  String? author,
  List<String> tags = const [],
}) =>
    Media(
      ref: SourceRef(source, url),
      title: title,
      kind: MediaKind.manga,
      author: author,
      tags: tags,
      inLibrary: true,
    );

LibraryEntry _entry(Media media) =>
    LibraryEntry(media: media, totalUnits: 0, completedUnits: 0);

void main() {
  test('src: keeps one catalogue and is case folded', () {
    final search = LibrarySearch.parse('src:MangaDex');
    expect(search.matches(_media('a', title: 'Blue Echo')), isTrue);
    expect(
      search.matches(_media('b', title: 'Blue Echo', source: 'suwayomi')),
      isFalse,
    );
  });

  test('commas narrow every term instead of widening the search', () {
    final search = LibrarySearch.parse('blue, echo');
    expect(search.matches(_media('a', title: 'Blue Echo')), isTrue);
    expect(search.matches(_media('b', title: 'Blue Night')), isFalse);
    expect(
      LibrarySearch.parse('kishimoto').matches(
        _media('c', title: 'Naruto', author: 'Masashi Kishimoto'),
      ),
      isTrue,
    );
  });

  test('tag: matches a category without opening the filter sheet', () {
    final search = LibrarySearch.parse('tag:fantasy');
    expect(
      search.matches(_media('a', title: 'Blue Echo', tags: ['Fantasy'])),
      isTrue,
    );
    expect(search.matches(_media('b', title: 'Blue Echo')), isFalse);
  });

  test('operators and plain terms combine in one query', () {
    final media = _media('a', title: 'Blue Echo', tags: ['Fantasy']);
    expect(LibrarySearch.parse('src:mangadex, blue, tag:fantasy').matches(media),
        isTrue);
    expect(
      LibrarySearch.parse('src:mangadex, tag:romance').matches(media),
      isFalse,
    );
  });

  test('Arabic commas, empty terms and native titles retain folded search', () {
    final media = _media('a', title: 'Blue Echo', tags: ['أكشن'])
        .copyWith(nativeTitle: 'أسرار الغابة');
    expect(
      LibrarySearch.parse('src:mangadex، اسرار، tag:اكشن').matches(media),
      isTrue,
    );
    expect(LibrarySearch.parse(' , ، \n src: , tag: ').isEmpty, isTrue);
  });

  test('multiple source prefixes allow either source, never an unrelated one',
      () {
    final search = LibrarySearch.parse('src:mangadex, src:suwayomi, blue');
    expect(search.matches(_media('a', title: 'Blue Echo')), isTrue);
    expect(search.matches(_media('b', title: 'Blue', source: 'suwayomi')),
        isTrue);
    expect(search.matches(_media('c', title: 'Blue', source: 'other')), isFalse);
  });

  test('shuffle seed participates in query identity and copy', () {
    const query = LibraryQuery(sort: LibrarySort.random, randomSeed: 11);
    expect(query.copyWith(search: 'blue').randomSeed, 11);
    expect(query.copyWith(), query);
    expect(query.copyWith(randomSeed: 12), isNot(query));
    final entries = [
      _entry(_media('b', title: 'Blue')),
      _entry(_media('a', title: 'Amber')),
    ];
    expect(
      LibraryPolicy.apply(entries, const LibraryQuery(sort: LibrarySort.random))
          .map((entry) => entry.media.title),
      ['Amber', 'Blue'],
    );
  });

  test('a seeded shuffle is stable and keeps every entry', () {
    final entries = [
      for (var index = 0; index < 8; index++)
        _entry(_media('work-$index', title: 'Work $index')),
    ];
    final first = LibraryPolicy.apply(
      entries,
      const LibraryQuery(sort: LibrarySort.random, randomSeed: 11),
    );
    final again = LibraryPolicy.apply(
      entries,
      const LibraryQuery(sort: LibrarySort.random, randomSeed: 11),
    );
    final other = LibraryPolicy.apply(
      entries,
      const LibraryQuery(sort: LibrarySort.random, randomSeed: 12),
    );
    expect(first.map((entry) => entry.media.id),
        again.map((entry) => entry.media.id));
    expect(first.map((entry) => entry.media.id).toSet(), hasLength(8));
    expect(first.map((entry) => entry.media.id),
        isNot(other.map((entry) => entry.media.id)));
  });
}
