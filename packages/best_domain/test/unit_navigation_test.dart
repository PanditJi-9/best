import 'package:best_domain/best_domain.dart';
import 'package:test/test.dart';

void main() {
  MediaUnit unit(double n,
          {String? title, String? url, String memo = '', int date = 0}) =>
      MediaUnit(
        mediaId: 'source::work',
        url: url ?? 'chapter-$n',
        number: n,
        title: title ?? 'Chapter $n',
        kind: UnitKind.chapter,
        pageCount: 10,
        memo: memo,
        publishedAt: date,
      );
  UnitProgress progress(MediaUnit u, int time,
          {int page = 3, bool done = false}) =>
      UnitProgress(
        unitId: u.id,
        position: page,
        total: 10,
        completed: done,
        started: true,
        updatedAt: time,
      );
  final first = unit(1);
  final second = unit(2);
  final third = unit(3);

  test('source order is normalized before start or continuation decisions', () {
    final next = UnitNavigation.continuation([third, second, first], {});
    expect(next!.unit.id, first.id);
    expect(next.kind, UnitContinuationKind.start);
  });

  test(
      'continue resumes the newest unfinished chapter, not the first partial row',
      () {
    final next = UnitNavigation.continuation([
      first,
      second,
      third
    ], {
      first.id: progress(first, 10),
      third.id: progress(third, 20, page: 5),
    });
    expect(next!.unit.id, third.id);
    expect(next.kind, UnitContinuationKind.resume);
    expect(next.progress!.position, 5);
  });

  test(
      'finished chapters advance through actual rows, including a started next chapter',
      () {
    final saved = {
      first.id: progress(first, 100, done: true),
      second.id: progress(second, 90, done: true),
      third.id: progress(third, 10, page: 4),
    };
    final next = UnitNavigation.continuation([third, second, first], saved);
    expect(next!.unit.id, third.id);
    expect(next.kind, UnitContinuationKind.resume);
    saved.remove(third.id);
    expect(UnitNavigation.continuation([first, second, third], saved)!.kind,
        UnitContinuationKind.next);
  });

  test('a saved first-page position is real continuation, not an unopened work',
      () {
    final next = UnitNavigation.continuation([
      first,
      second,
      third
    ], {
      third.id: progress(third, 100, page: 0),
    });
    expect(next!.unit.id, third.id);
    expect(next.kind, UnitContinuationKind.resume);
    expect(UnitNavigation.hasStarted(next.progress), isTrue);
  });

  test(
      'legacy untouched page-zero rows are not inferred as opened from a page count',
      () {
    final saved =
        UnitProgress(unitId: third.id, position: 0, total: 10, updatedAt: 100);
    expect(UnitNavigation.hasStarted(saved), isFalse);
    expect(
        UnitNavigation.continuation([first, second, third], {third.id: saved})!
            .kind,
        UnitContinuationKind.start);
    final opened = UnitProgress(
      unitId: third.id,
      position: 0,
      total: 10,
      started: true,
      updatedAt: 200,
    );
    expect(opened.merge(saved).started, isTrue);
  });

  test(
      'all-finished work offers an explicit replay from the first actual chapter',
      () {
    final saved = {
      for (final u in [first, second, third])
        u.id: progress(u, u.number.toInt(), done: true),
    };
    final next = UnitNavigation.continuation([third, second, first], saved);
    expect(next!.unit.id, first.id);
    expect(next.kind, UnitContinuationKind.replay);
    expect(
        UnitNavigation.continuation([first, second, third], saved,
            allowReplay: false),
        isNull);
  });

  test(
      'older unread gaps are described as catch-up, never an invented next chapter',
      () {
    final next = UnitNavigation.continuation([
      first,
      second,
      third
    ], {
      second.id: progress(second, 20, done: true),
      third.id: progress(third, 30, done: true),
    });
    expect(next!.unit.id, first.id);
    expect(next.kind, UnitContinuationKind.catchUp);
  });

  test('an empty source or orphan progress cannot create a chapter', () {
    expect(UnitNavigation.continuation([], {first.id: progress(first, 1)}),
        isNull);
    final next =
        UnitNavigation.continuation([second], {first.id: progress(first, 100)});
    expect(next!.unit.id, second.id);
    expect(next.kind, UnitContinuationKind.start);
  });

  test(
      'duplicate IDs are merged without losing signing memo or renumbering groups',
      () {
    final original = unit(1, memo: '{"mangaPath":"/story/"}');
    final duplicate =
        original.copyWith(title: 'A better chapter label', memo: '');
    final alternative = unit(1, url: 'other-group');
    final ordered =
        UnitNavigation.readingOrder([original, duplicate, alternative]);
    expect(ordered, hasLength(2));
    expect(ordered.first.title, 'A better chapter label');
    expect(ordered.first.memo, original.memo);
    expect(ordered.last.id, alternative.id);
  });

  test(
      'unknown numbering uses dates when available and otherwise preserves source order',
      () {
    final a = unit(-1, url: 'a', date: 200);
    final b = unit(-1, url: 'b', date: 100);
    expect(UnitNavigation.readingOrder([a, b]).map((u) => u.id), [b.id, a.id]);
    final unknown = [a.copyWith(publishedAt: 0), b.copyWith(publishedAt: 0)];
    expect(UnitNavigation.hasChronologicalOrder(unknown), isFalse);
    expect(UnitNavigation.readingOrder(unknown).map((u) => u.id), [a.id, b.id]);
  });

  test('chapter search accepts Arabic and Persian numbers and chapter prefixes',
      () {
    for (final query in ['2', '٢', '۲', 'الفصل ٢', 'Chapter 2']) {
      expect(
          UnitNavigation.visible([first, second, third], query: query)
              .single
              .id,
          second.id);
    }
    final arabic = unit(4, title: 'أسرار الغابة');
    expect(
        UnitNavigation.visible([arabic], query: 'اسرار').single.id, arabic.id);
  });

  test('display filters are pure and leave navigation on the full sequence',
      () {
    final units = [first, second, third];
    final saved = {
      first.id: progress(first, 10, done: true),
      second.id: progress(second, 20)
    };
    expect(
        UnitNavigation.visible(units,
                filter: UnitFilter.inProgress, progress: saved)
            .map((u) => u.id),
        [second.id]);
    expect(
        UnitNavigation.visible(units,
                filter: UnitFilter.unread, progress: saved)
            .map((u) => u.id),
        [second.id, third.id]);
    expect(
        UnitNavigation.visible(units, sort: UnitSort.newest).map((u) => u.id),
        [third.id, second.id, first.id]);
    expect(units.map((u) => u.id), [first.id, second.id, third.id]);
  });

  test('only completed download tasks count as downloaded chapters', () {
    DownloadTask task(MediaUnit u, DownloadStatus status) => DownloadTask(
          unitId: u.id,
          mediaId: u.mediaId,
          sourceId: 'source',
          mediaUrl: 'work',
          unitUrl: u.url,
          mediaTitle: 'Work',
          unitTitle: u.title,
          total: 10,
          status: status,
        );
    final downloads = {
      first.id: task(first, DownloadStatus.done),
      second.id: task(second, DownloadStatus.paused),
      third.id: task(third, DownloadStatus.failed),
    };
    expect(
        UnitNavigation.visible([first, second, third],
                filter: UnitFilter.downloaded, downloads: downloads)
            .single
            .id,
        first.id);
  });

  test(
      'library not-started and in-progress filters include first-page sessions logically',
      () {
    final media = Media(
        ref: const SourceRef('test', 'work'),
        title: 'Work',
        kind: MediaKind.manga,
        inLibrary: true);
    final entry = LibraryEntry(
      media: media,
      totalUnits: 3,
      completedUnits: 0,
      lastProgress: progress(first, 10, page: 0),
    );
    expect(
        LibraryPolicy.apply(
            [entry], const LibraryQuery(filter: LibraryFilter.unread)),
        isEmpty);
    expect(
        LibraryPolicy.apply(
            [entry], const LibraryQuery(filter: LibraryFilter.inProgress)),
        [entry]);
  });
}
