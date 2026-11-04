import 'package:best_app/src/providers.dart';
import 'package:best_data/best_data.dart';
import 'package:best_domain/best_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late MemoryLibraryRepository repository;
  late ProviderContainer container;
  final work = Media(
    ref: const SourceRef('test', 'blue'),
    title: 'Blue Echo',
    kind: MediaKind.manhwa,
    inLibrary: true,
  );
  MediaUnit unit(int n) => MediaUnit(
        mediaId: work.id,
        url: 'chapter-$n',
        number: n.toDouble(),
        title: 'Chapter $n',
        kind: UnitKind.chapter,
        pageCount: 20,
      );
  Future<void> progress(int n, int time, {bool done = false}) =>
      repository.saveProgress(UnitProgress(
        unitId: unit(n).id,
        position: done ? 19 : 4,
        total: 20,
        completed: done,
        updatedAt: time,
      ));

  setUp(() async {
    repository = MemoryLibraryRepository();
    container = ProviderContainer(overrides: [
      repositoryProvider.overrideWithValue(repository),
    ]);
    await repository.saveMedia(work);
    // Incoming source order is deliberately reversed.
    await repository.saveUnits([unit(4), unit(3), unit(2), unit(1)]);
  });
  tearDown(() async {
    container.dispose();
    await repository.close();
  });

  test('global library search ignores and preserves tab filters', () async {
    final controller = container.read(libraryQueryProvider.notifier);
    controller.setSearch('unrelated');
    controller.setFilter(LibraryFilter.favorites);
    controller.setSort(LibrarySort.title);
    final before = container.read(libraryQueryProvider);
    final found =
        await container.read(librarySearchProvider('  Blue  ').future);
    expect(found.single.media.id, work.id);
    expect(container.read(libraryQueryProvider), before);
    expect(await container.read(libraryProvider.future), isEmpty);
    expect(await container.read(librarySearchProvider(' ').future), isEmpty);
  });

  test('resume describes exactly the most recently started chapter', () async {
    await progress(1, 10);
    await progress(2, 20);
    final slots = await container.read(resumeProvider.future);
    expect(slots, hasLength(1));
    expect(slots.single.unit.id, unit(2).id);
    expect(slots.single.progress!.position, 4);
    expect(slots.single.isNext, isFalse);
  });

  test('next up skips finished chapters in stored numeric order', () async {
    await progress(1, 100, done: true);
    await progress(2, 90, done: true);
    final slot = (await container.read(resumeProvider.future)).single;
    expect(slot.unit.id, unit(3).id);
    expect(slot.isNext, isTrue);
    expect(slot.progress, isNull);
    expect(await repository.progressFor(unit(3).id), isNull);
  });

  test('an already started next chapter resumes its own progress', () async {
    await progress(1, 100, done: true);
    await progress(2, 90, done: true);
    await progress(3, 10);
    final slot = (await container.read(resumeProvider.future)).single;
    expect(slot.unit.id, unit(3).id);
    expect(slot.isNext, isFalse);
    expect(slot.progress!.position, 4);
  });

  test('nothing unread produces no invented next chapter', () async {
    for (var n = 1; n <= 4; n++) {
      await progress(n, n, done: true);
    }
    expect(await container.read(resumeProvider.future), isEmpty);
    expect(await repository.unitsFor(work.id), hasLength(4));
  });

  test('a completed single-page chapter advances from page zero', () async {
    await repository.saveProgress(UnitProgress(
      unitId: unit(1).id,
      position: 0,
      total: 1,
      completed: true,
      updatedAt: 100,
    ));
    final slot = (await container.read(resumeProvider.future)).single;
    expect(slot.unit.id, unit(2).id);
    expect(slot.isNext, isTrue);
    expect(slot.progress, isNull);
  });
}
