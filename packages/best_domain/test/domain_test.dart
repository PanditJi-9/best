import 'package:best_domain/best_domain.dart';
import 'package:test/test.dart';

void main() {
  group('identity', () {
    test('is deterministic and namespaced by source', () {
      expect(mediaIdOf('mangadex', 'abc'), 'mangadex::abc');
      expect(mediaIdOf('mangadex', 'abc'), mediaIdOf('mangadex', 'abc'));
      expect(mediaIdOf('mangadex', 'abc'), isNot(mediaIdOf('mihon:1', 'abc')));
    });

    test('a source id cannot smuggle the separator', () {
      expect(mediaIdOf('a', 'b::c'), 'a::b::c');
      expect(() => mediaIdOf('a::b', 'c'), throwsArgumentError);
    });

    test('units are namespaced by their work', () {
      final first = MediaUnit(
        mediaId: mediaIdOf('demo', 'one'),
        url: 'ch-1',
        number: 1,
        title: 'Chapter 1',
        kind: UnitKind.chapter,
      );
      expect(first.id, 'demo::one::ch-1');
    });

    test('a chapter keeps the memo its source attached', () {
      const unit = MediaUnit(
        mediaId: 'demo::one',
        url: 'ch-1',
        number: 1,
        title: 'Chapter 1',
        kind: UnitKind.chapter,
        memo: '{"mangaPath":"/manga/one"}',
      );
      expect(unit.memo, '{"mangaPath":"/manga/one"}');
      expect(unit.copyWith(pageCount: 20).memo, '{"mangaPath":"/manga/one"}');
    });

    test('a work keeps the memo its source attached', () {
      // Madara-derived sources put the canonical manga path on the catalogue
      // card and build chapter URLs from it, so it cannot be dropped on the way
      // to the chapter list.
      const media = Media(
        ref: SourceRef('mihon:1', '775'),
        title: 'Otherworldly Evil Monarch',
        kind: MediaKind.manga,
        memo: '{"path":"/manga/otherworldly-evil-monarch/"}',
      );
      expect(media.memo, '{"path":"/manga/otherworldly-evil-monarch/"}');
      expect(media.copyWith(title: 'x').memo, media.memo);
      expect(
        const Media(ref: SourceRef('mihon:1', '1'), title: 'a', kind: MediaKind.manga)
            .memo,
        isEmpty,
      );
    });
  });

  group('progress merge', () {
    const base = UnitProgress(unitId: 'u', position: 3, total: 20, updatedAt: 100);

    test('the later write wins the position', () {
      const newer = UnitProgress(unitId: 'u', position: 9, total: 20, updatedAt: 200);
      expect(base.merge(newer).position, 9);
      expect(newer.merge(base).position, 9);
    });

    test('an older write cannot move a reader backwards', () {
      const newer = UnitProgress(unitId: 'u', position: 9, total: 20, updatedAt: 200);
      const stale = UnitProgress(unitId: 'u', position: 2, total: 20, updatedAt: 50);
      expect(newer.merge(stale).position, 9);
    });

    test('completion is a union and survives a stale backup', () {
      const finished = UnitProgress(
        unitId: 'u',
        position: 19,
        total: 20,
        completed: true,
        updatedAt: 200,
      );
      const stale = UnitProgress(unitId: 'u', position: 4, total: 20, updatedAt: 50);
      final merged = finished.merge(stale);
      expect(merged.completed, isTrue);
      expect(merged.position, 19);
    });

    test('a larger page count is kept', () {
      const short = UnitProgress(unitId: 'u', position: 4, total: 10, updatedAt: 200);
      const long = UnitProgress(unitId: 'u', position: 2, total: 40, updatedAt: 50);
      expect(short.merge(long).total, 40);
    });

    test('a position past the last page is clamped', () {
      const past = UnitProgress(unitId: 'u', position: 99, total: 20, updatedAt: 200);
      expect(base.merge(past).position, 19);
    });

    test('fraction is safe with an unknown total', () {
      const unknown = UnitProgress(unitId: 'u', position: 5, updatedAt: 1);
      expect(unknown.fraction, 0);
      expect(
        const UnitProgress(unitId: 'u', position: 0, total: 0, completed: true, updatedAt: 1)
            .fraction,
        1,
      );
    });
  });

  group('unit number', () {
    test('reads the common shapes', () {
      expect(parseUnitNumber('Chapter 12.5'), 12.5);
      expect(parseUnitNumber('Ch. 12'), 12);
      expect(parseUnitNumber('الفصل ١٢'), 12);
      expect(parseUnitNumber('الحلقة 3'), 3);
      expect(parseUnitNumber('第12話'), 12);
      expect(parseUnitNumber('Vol. 2 Chapter 7'), 7);
      expect(parseUnitNumber('EP 03'), 3);
    });

    test('does not turn a year into a chapter', () {
      expect(parseUnitNumber('2024'), isNull);
      expect(parseUnitNumber('Coming soon'), isNull);
      expect(parseUnitNumber(''), isNull);
    });

    test('takes the first number of a range', () {
      expect(parseUnitNumber('Chapters 12-13'), 12);
      expect(parseUnitNumber('12.5.1'), 12.5);
    });
  });

  group('search folding', () {
    test('folds Arabic variants', () {
      expect(SearchText.normalize('  الفصلُ  الأول  '), 'الفصل الاول');
      expect(SearchText.normalize('إسراء'), 'اسراء');
      expect(SearchText.normalize('مدرسة'), 'مدرسه');
      expect(SearchText.normalize('على'), 'علي');
      expect(SearchText.normalize('١٢٣'), '123');
    });

    test('matches a folded query', () {
      expect(SearchText.matches('مدرسة الأبطال', 'مدرسه'), isTrue);
      expect(SearchText.matches('Blue Lock', 'BLUE'), isTrue);
      expect(SearchText.matches('Blue Lock', ''), isTrue);
      expect(SearchText.matches('Blue Lock', 'red'), isFalse);
    });
  });

  group('library policy', () {
    Media media(
      String title, {
      bool favorite = false,
      int lastOpened = 0,
      int added = 0,
      String? author,
    }) {
      return Media(
        ref: SourceRef('demo', title),
        title: title,
        kind: MediaKind.manhwa,
        inLibrary: true,
        favorite: favorite,
        lastOpenedAt: lastOpened,
        addedAt: added,
        author: author,
      );
    }

    LibraryEntry entry(Media work, int total, int completed) =>
        LibraryEntry(media: work, totalUnits: total, completedUnits: completed);

    test('filters by membership and progress', () {
      final entries = [
        entry(media('A'), 10, 0),
        entry(media('B'), 10, 5),
        entry(media('C'), 10, 10),
        entry(media('D', favorite: true), 10, 2),
      ];

      List<String> titles(LibraryFilter filter) => LibraryPolicy.apply(
            entries,
            LibraryQuery(filter: filter, sort: LibrarySort.title),
          ).map((e) => e.media.title).toList();

      expect(titles(LibraryFilter.all), ['A', 'B', 'C', 'D']);
      expect(titles(LibraryFilter.unread), ['A']);
      expect(titles(LibraryFilter.inProgress), ['B', 'D']);
      expect(titles(LibraryFilter.completed), ['C']);
      expect(titles(LibraryFilter.favorites), ['D']);
    });

    test('searches title, native title and author', () {
      final work = media('مدرسة الأبطال', author: 'كاتب');
      final entries = [entry(work, 4, 1)];
      expect(LibraryPolicy.apply(entries, const LibraryQuery(search: 'مدرسه')), hasLength(1));
      expect(LibraryPolicy.apply(entries, const LibraryQuery(search: 'كاتب')), hasLength(1));
      expect(LibraryPolicy.apply(entries, const LibraryQuery(search: 'nope')), isEmpty);
    });

    test('sorts by recency and title', () {
      final entries = [
        entry(media('B', lastOpened: 100, added: 5), 2, 0),
        entry(media('A', lastOpened: 300, added: 1), 2, 0),
        entry(media('C', lastOpened: 200, added: 9), 2, 0),
      ];
      expect(
        LibraryPolicy.apply(entries, const LibraryQuery(sort: LibrarySort.recentlyRead))
            .map((e) => e.media.title),
        ['A', 'C', 'B'],
      );
      expect(
        LibraryPolicy.apply(entries, const LibraryQuery(sort: LibrarySort.recentlyAdded))
            .map((e) => e.media.title),
        ['C', 'B', 'A'],
      );
      expect(
        LibraryPolicy.apply(entries, const LibraryQuery(sort: LibrarySort.title))
            .map((e) => e.media.title),
        ['A', 'B', 'C'],
      );
    });

    test('continue prefers the newest unfinished unit', () {
      MediaUnit unit(String id, double number) => MediaUnit(
            mediaId: 'demo::$id',
            url: id,
            number: number,
            title: 'Chapter $number',
            kind: UnitKind.chapter,
          );
      ContinueEntry row(String id, double number, int position, bool completed, int at) =>
          ContinueEntry(
            media: media(id),
            unit: unit(id, number),
            progress: UnitProgress(
              unitId: unit(id, number).id,
              position: position,
              total: 20,
              completed: completed,
              updatedAt: at,
            ),
          );

      expect(LibraryPolicy.pickContinue([]), isNull);
      expect(
        LibraryPolicy.pickContinue([
          row('finished', 10, 19, true, 900),
          row('reading', 2, 5, false, 500),
        ])?.unit.number,
        2,
      );
      expect(
        LibraryPolicy.pickContinue([row('finished', 10, 19, true, 900)])?.unit.number,
        10,
      );
    });
  });
}
