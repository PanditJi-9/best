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

  Media work(String source, String slug, {bool inLibrary = true}) => Media(
        ref: SourceRef(source, slug),
        title: slug,
        kind: MediaKind.manga,
        inLibrary: inLibrary,
        favorite: true,
        state: ReadingState.reading,
        tags: const ['Action'],
        addedAt: 1,
      );

  List<MediaUnit> units(String mediaId, List<int> numbers) => [
        for (final number in numbers)
          MediaUnit(
            mediaId: mediaId,
            url: 'unit-$number',
            number: number.toDouble(),
            title: 'Chapter $number',
            kind: UnitKind.chapter,
            pageCount: 10,
          ),
      ];

  test('migrates a work and carries its reading positions', () async {
    final old = work('test', 'a');
    final target = work('other', 'b', inLibrary: false);
    await repository.saveMedia(old);
    final oldUnits = units(old.id, [1, 2, 3]);
    await repository.saveUnits(oldUnits);
    await repository.saveProgress(
      UnitProgress(
        unitId: oldUnits[1].id,
        position: 8,
        total: 10,
        completed: true,
        updatedAt: 100,
      ),
    );

    await repository.saveMedia(target);
    final newUnits = units(target.id, [1, 2, 3]);
    await repository.saveUnits(newUnits);
    final plan = MigrationPlan.between(oldUnits, newUnits);
    final carried = plan.carryProgress({
      oldUnits[1].id: UnitProgress(
        unitId: oldUnits[1].id,
        position: 8,
        total: 10,
        completed: true,
        updatedAt: 100,
      ),
    });

    await repository.migrateMedia(
      fromMediaId: old.id,
      target: target.copyWith(
        inLibrary: old.inLibrary,
        favorite: old.favorite,
        state: old.state,
        tags: old.tags,
        addedAt: old.addedAt,
      ),
      carriedProgress: carried,
    );

    final shelf = await repository.library();
    expect(shelf, hasLength(1));
    expect(shelf.single.media.id, target.id);
    expect(shelf.single.media.favorite, isTrue);
    expect(shelf.single.media.state, ReadingState.reading);
    expect(shelf.single.media.tags, contains('Action'));

    final storedOld = await repository.mediaById(old.id);
    expect(storedOld, isNotNull);
    expect(storedOld!.inLibrary, isFalse,
        reason: 'the old row is kept, only its shelf slot is cleared');

    final moved = await repository.progressFor(newUnits[1].id);
    expect(moved, isNotNull);
    expect(moved!.position, 8);
    expect(moved.completed, isTrue);
    expect(moved.updatedAt, 100);
  });

  test('a migration can keep the old entry when asked', () async {
    final old = work('test', 'a');
    final target = work('other', 'b', inLibrary: false);
    await repository.saveMedia(old);
    await repository.saveMedia(target);
    await repository.saveUnits(units(old.id, [1]));
    await repository.saveUnits(units(target.id, [1]));

    await repository.migrateMedia(
      fromMediaId: old.id,
      target: target.copyWith(inLibrary: true),
      carriedProgress: const [],
      removeOldFromLibrary: false,
    );

    final shelf = await repository.library();
    expect(
        shelf.map((entry) => entry.media.id), containsAll([old.id, target.id]));
  });

  test('migration keeps the target categories as well as the old ones',
      () async {
    final old = work('test', 'a').copyWith(tags: const ['Action', 'Weekly']);
    final target = work('other', 'b', inLibrary: false)
        .copyWith(tags: const ['Drama', 'Action']);
    await repository.saveMedia(old);
    await repository.saveMedia(target);

    await repository.migrateMedia(
      fromMediaId: old.id,
      target: target.copyWith(tags: const []),
      carriedProgress: const [],
      removeOldFromLibrary: false,
    );

    final stored = await repository.mediaById(target.id);
    expect(stored!.tags, containsAll(['Drama', 'Action', 'Weekly']));
    expect(stored.tags.where((tag) => tag == 'Action'), hasLength(1));
  });

  test('migration never moves an existing target position backwards', () async {
    final old = work('test', 'a');
    final target = work('other', 'b');
    await repository.saveMedia(old);
    await repository.saveMedia(target);
    final oldUnit = units(old.id, [1]).single;
    final newUnit = units(target.id, [1]).single;
    await repository.saveUnits([oldUnit, newUnit]);
    await repository.saveProgress(
      UnitProgress(
        unitId: newUnit.id,
        position: 7,
        total: 10,
        updatedAt: 500,
      ),
    );

    await repository.migrateMedia(
      fromMediaId: old.id,
      target: target,
      carriedProgress: [
        UnitProgress(
          unitId: newUnit.id,
          position: 2,
          total: 10,
          updatedAt: 100,
        ),
      ],
    );

    final stored = await repository.progressFor(newUnit.id);
    expect(stored!.position, 7);
    expect(stored.updatedAt, 500);
  });

  test('rejects a migration whose source is not stored', () async {
    expect(
      () => repository.migrateMedia(
        fromMediaId: 'missing::x',
        target: work('other', 'b'),
        carriedProgress: const [],
      ),
      throwsStateError,
    );
  });
}
