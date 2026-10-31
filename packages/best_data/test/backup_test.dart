import 'package:best_data/best_data.dart';
import 'package:best_domain/best_domain.dart';
import 'package:test/test.dart';

void main() {
  const ref = SourceRef('guide', 'forest-shadow');

  Media work({
    bool inLibrary = true,
    bool favorite = false,
    ReadingState state = ReadingState.none,
    List<String> tags = const [],
  }) {
    return Media(
      ref: ref,
      title: 'ظل الغابة',
      kind: MediaKind.manhwa,
      nativeTitle: 'Forest Shadow',
      author: 'Best',
      year: 2024,
      status: MediaStatus.ongoing,
      genres: const ['fantasy'],
      inLibrary: inLibrary,
      favorite: favorite,
      state: state,
      tags: tags,
      addedAt: 100,
      lastOpenedAt: 200,
    );
  }

  final unit = MediaUnit(
    mediaId: mediaIdOf(ref.sourceId, ref.url),
    url: 'unit-1',
    number: 1,
    title: 'Chapter 1',
    kind: UnitKind.chapter,
    pageCount: 12,
  );

  LibrarySnapshot snapshot() {
    return LibrarySnapshot(
      exportedAt: 1234,
      media: [work(state: ReadingState.reading, tags: const ['favourites'])],
      units: [unit],
      progress: [
        UnitProgress(unitId: unit.id, position: 4, total: 12, updatedAt: 900),
      ],
      activity: [
        const DailyActivity(day: '2026-10-30', pages: 12, minutes: 3, units: 1),
      ],
    );
  }

  group('encode and decode', () {
    test('round-trips the shelf, the plan, lists and activity', () {
      final decoded = LibraryBackup.decode(LibraryBackup.encode(snapshot()));

      expect(decoded.exportedAt, 1234);
      expect(decoded.media, hasLength(1));
      expect(decoded.media.single.title, 'ظل الغابة');
      expect(decoded.media.single.nativeTitle, 'Forest Shadow');
      expect(decoded.media.single.state, ReadingState.reading);
      expect(decoded.media.single.tags, ['favourites']);
      expect(decoded.media.single.favorite, isFalse);
      expect(decoded.units.single.number, 1);
      expect(decoded.progress.single.position, 4);
      expect(decoded.activity.single.pages, 12);
      expect(decoded.activity.single.day, '2026-10-30');
    });

    test('is human-readable JSON with a version', () {
      final encoded = LibraryBackup.encode(snapshot());
      expect(encoded, contains('"format": "best.library"'));
      expect(encoded, contains('"version": 2'));
      expect(encoded, contains('ظل الغابة'));
    });

    test('describes itself for a confirmation dialog', () {
      expect(LibraryBackup.describe(snapshot()), contains('1 works'));
    });

    test('rejects something that is not JSON', () {
      expect(
        () => LibraryBackup.decode('not json'),
        throwsA(isA<BackupException>()),
      );
    });

    test('rejects another app\'s JSON', () {
      expect(
        () => LibraryBackup.decode('{"format":"other","version":1}'),
        throwsA(isA<BackupException>()),
      );
    });

    test('rejects a newer format instead of guessing', () {
      expect(
        () => LibraryBackup.decode('{"format":"best.library","version":9}'),
        throwsA(isA<BackupException>()),
      );
    });

    test('carries installed source packs', () {
      final document = LibraryBackup.decodeDocument(
        LibraryBackup.encode(snapshot(), sources: const ['{"id":"a.b"}']),
      );
      expect(document.sources, ['{"id":"a.b"}']);
      expect(document.snapshot.media, hasLength(1));
    });

    test('a format-1 backup has no sources and still restores', () {
      final document = LibraryBackup.decodeDocument(
        '{"format":"best.library","version":1,"media":[]}',
      );
      expect(document.sources, isEmpty);
      expect(document.isEmpty, isTrue);
    });

    test('tolerates a missing optional section', () {
      final decoded = LibraryBackup.decode(
        '{"format":"best.library","version":1,"media":[]}',
      );
      expect(decoded.units, isEmpty);
      expect(decoded.progress, isEmpty);
      expect(decoded.isEmpty, isTrue);
    });
  });

  group('restoreInto', () {
    test('writes the shelf and the history into an empty repository', () async {
      final repository = MemoryLibraryRepository();
      final report = await restoreInto(repository, snapshot());

      expect(report.media, 1);
      expect(report.units, 1);
      expect(report.progress, 1);

      final restored = await repository.mediaById(work().id);
      expect(restored?.state, ReadingState.reading);
      expect(restored?.tags, ['favourites']);
      expect(await repository.progressFor(unit.id), isNotNull);
      expect(await repository.activity(), hasLength(1));
    });

    test('a stale backup never erases a newer position', () async {
      final repository = MemoryLibraryRepository();
      await repository.saveUnits([unit]);
      await repository.saveProgress(
        UnitProgress(unitId: unit.id, position: 9, total: 12, updatedAt: 5000),
      );

      await restoreInto(repository, snapshot());

      final progress = await repository.progressFor(unit.id);
      expect(progress?.position, 9);
      expect(progress?.updatedAt, 5000);
    });

    test('restoring twice does not double the activity', () async {
      final repository = MemoryLibraryRepository();
      await restoreInto(repository, snapshot());
      await restoreInto(repository, snapshot());

      final days = await repository.activity();
      expect(
        days.single.pages,
        12,
        reason: 'a day is a total, so a second restore of the same file is a no-op',
      );
    });

    test('a favorite and a plan survive a catalogue refresh', () async {
      final repository = MemoryLibraryRepository();
      await repository.saveMedia(work());
      await repository.setFavorite(work().id, true);
      await repository.setReadingState(work().id, ReadingState.planned);

      // A source refresh arrives with no plan and no favorite.
      await repository.saveMedia(
        Media(ref: ref, title: 'ظل الغابة', kind: MediaKind.manhwa),
      );

      final stored = await repository.mediaById(work().id);
      expect(stored?.favorite, isTrue);
      expect(stored?.state, ReadingState.planned);
    });
  });
}
