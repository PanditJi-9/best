import 'package:best_data/best_data.dart';
import 'package:best_domain/best_domain.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase database;
  late SqfliteLibraryRepository repository;

  setUp(() async {
    database = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: ':memory:',
    );
    repository = SqfliteLibraryRepository(database.db);
  });

  tearDown(() async {
    await repository.close();
  });

  Media work(String slug, {bool favorite = false, bool inLibrary = true}) {
    return Media(
      ref: SourceRef('test', slug),
      title: slug,
      kind: MediaKind.manhwa,
      inLibrary: inLibrary,
      favorite: favorite,
      addedAt: 1,
    );
  }

  MediaUnit unit(String slug, int number) {
    return MediaUnit(
      mediaId: 'test::$slug',
      url: 'unit-$number',
      number: number.toDouble(),
      title: 'Chapter $number',
      kind: UnitKind.chapter,
      pageCount: 20,
    );
  }

  test('stores a work and counts its units', () async {
    await repository.saveMedia(work('a'));
    await repository.saveUnits([unit('a', 1), unit('a', 2), unit('a', 3)]);
    await repository.saveProgress(
      UnitProgress(unitId: unit('a', 1).id, position: 19, total: 20, completed: true, updatedAt: 10),
    );

    final shelf = await repository.library();
    expect(shelf, hasLength(1));
    expect(shelf.single.totalUnits, 3);
    expect(shelf.single.completedUnits, 1);
    expect(shelf.single.fraction, closeTo(1 / 3, 0.001));
    expect(shelf.single.unreadUnits, 2);
  });

  test('a stale write cannot move progress backwards', () async {
    await repository.saveMedia(work('a'));
    await repository.saveUnits([unit('a', 1)]);
    final id = unit('a', 1).id;

    await repository.saveProgress(
      UnitProgress(unitId: id, position: 8, total: 20, updatedAt: 200),
    );
    await repository.saveProgress(
      UnitProgress(unitId: id, position: 2, total: 20, updatedAt: 100),
    );

    final progress = await repository.progressFor(id);
    expect(progress, isNotNull);
    expect(progress!.position, 8);
    expect(progress.updatedAt, 200);
  });

  test('continue reading orders by the last write', () async {
    await repository.saveMedia(work('a'));
    await repository.saveMedia(work('b'));
    await repository.saveUnits([unit('a', 1), unit('b', 1)]);

    await repository.saveProgress(
      UnitProgress(unitId: unit('a', 1).id, position: 4, total: 20, updatedAt: 100),
    );
    await repository.saveProgress(
      UnitProgress(unitId: unit('b', 1).id, position: 7, total: 20, updatedAt: 300),
    );

    final rows = await repository.continueReading();
    expect(rows.first.media.title, 'b');
    expect(LibraryPolicy.pickContinue(rows)?.media.title, 'b');
  });

  test('a refresh keeps the favorite flag and history', () async {
    await repository.saveMedia(work('a', favorite: true));
    await repository.setInLibrary('test::a', true);

    final refreshed = Media(
      ref: const SourceRef('test', 'a'),
      title: 'A — refreshed',
      kind: MediaKind.manhwa,
      inLibrary: false,
      addedAt: 99,
    );
    await repository.saveMedia(refreshed);

    final stored = await repository.mediaById('test::a');
    expect(stored, isNotNull);
    expect(stored!.title, 'A — refreshed');
    expect(stored.favorite, isTrue);
    expect(stored.inLibrary, isTrue);
    expect(stored.addedAt, 1);
  });

  test('removing from the library keeps the work and its progress', () async {
    await repository.saveMedia(work('a'));
    await repository.saveUnits([unit('a', 1)]);
    await repository.saveProgress(
      UnitProgress(unitId: unit('a', 1).id, position: 3, total: 20, updatedAt: 10),
    );

    await repository.removeFromLibrary('test::a');

    expect(await repository.library(), isEmpty);
    expect(await repository.mediaById('test::a'), isNotNull);
    expect(await repository.progressFor(unit('a', 1).id), isNotNull);
  });

  test('the changes stream fires after a write', () async {
    final event = repository.changes.first;
    await repository.saveMedia(work('a'));
    await event.timeout(const Duration(seconds: 2));
  });

  test('the in-memory repository keeps the same shelf rules', () async {
    final memory = MemoryLibraryRepository();
    final media = Media(
      ref: const SourceRef('test', 'a'),
      title: 'a',
      kind: MediaKind.manhwa,
      inLibrary: true,
      favorite: true,
      addedAt: 1,
    );
    await memory.saveMedia(media);
    await memory.saveUnits([unit('a', 1), unit('a', 2)]);
    await memory.saveProgress(
      UnitProgress(
        unitId: unit('a', 1).id,
        position: 19,
        total: 20,
        completed: true,
        updatedAt: 10,
      ),
    );
    await memory.saveProgress(
      UnitProgress(
        unitId: unit('a', 1).id,
        position: 2,
        total: 20,
        updatedAt: 5,
      ),
    );

    final shelf = await memory.library();
    expect(shelf.single.completedUnits, 1);
    expect(shelf.single.totalUnits, 2);
    expect((await memory.progressFor(unit('a', 1).id))!.position, 19);

    await memory.setInLibrary(media.id, false);
    expect(await memory.library(), isEmpty);
    expect(await memory.mediaById(media.id), isNotNull);
    expect(await memory.progressFor(unit('a', 1).id), isNotNull);
    await memory.close();
  });

  test('the guide has units and generated pages', () async {
    final source = DemoSource();
    final works = await source.popular();
    expect(works, isNotEmpty);

    final reading = works.firstWhere((media) => media.kind.isReading);
    final units = await source.units(reading);
    expect(units, isNotEmpty);

    final pages = await source.resources(units.first);
    expect(pages, hasLength(units.first.pageCount));
    expect(pages.first, isA<SyntheticPage>());
  });
}
