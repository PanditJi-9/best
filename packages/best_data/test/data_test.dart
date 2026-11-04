import 'dart:io';

import 'package:best_data/best_data.dart';
import 'package:best_domain/best_domain.dart';
import 'package:path/path.dart' as p;
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
      UnitProgress(
          unitId: unit('a', 1).id,
          position: 19,
          total: 20,
          completed: true,
          updatedAt: 10),
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
      UnitProgress(
          unitId: unit('a', 1).id, position: 4, total: 20, updatedAt: 100),
    );
    await repository.saveProgress(
      UnitProgress(
          unitId: unit('b', 1).id, position: 7, total: 20, updatedAt: 300),
    );

    final rows = await repository.continueReading();
    expect(rows.first.media.title, 'b');
    expect(LibraryPolicy.pickContinue(rows)?.media.title, 'b');
  });

  test('continue limit counts works, with deterministic latest chapter ties',
      () async {
    final memory = MemoryLibraryRepository();
    addTearDown(memory.close);
    for (final store in <LibraryRepository>[repository, memory]) {
      await store.saveMedia(work('a'));
      await store.saveMedia(work('b'));
      await store.saveUnits([
        for (var n = 1; n <= 30; n++) unit('a', n),
        unit('b', 1),
      ]);
      for (var n = 1; n <= 30; n++) {
        await store.saveProgress(UnitProgress(
          unitId: unit('a', n).id,
          position: 4,
          total: 20,
          updatedAt: n + 100,
        ));
      }
      await store.saveProgress(UnitProgress(
        unitId: unit('b', 1).id,
        position: 2,
        total: 20,
        updatedAt: 1,
      ));
      final entries = await store.continueReading(limit: 2);
      expect(entries.map((e) => e.media.title), ['a', 'b']);
      expect(entries.first.unit.id, unit('a', 30).id);
      await store.saveProgress(UnitProgress(
        unitId: unit('a', 2).id,
        position: 6,
        total: 20,
        updatedAt: 130,
      ));
      expect((await store.continueReading(limit: 1)).single.unit.id,
          unit('a', 30).id);
    }
  });

  test('completed page zero is latest, untouched page zero is not', () async {
    final memory = MemoryLibraryRepository();
    addTearDown(memory.close);
    for (final store in <LibraryRepository>[repository, memory]) {
      await store.saveMedia(work('a'));
      await store.saveUnits([unit('a', 1), unit('a', 2), unit('a', 3)]);
      await store.saveProgress(UnitProgress(
        unitId: unit('a', 1).id,
        position: 4,
        total: 20,
        updatedAt: 10,
      ));
      await store.saveProgress(UnitProgress(
        unitId: unit('a', 2).id,
        position: 0,
        total: 1,
        completed: true,
        updatedAt: 20,
      ));
      await store.saveProgress(UnitProgress(
        unitId: unit('a', 3).id,
        position: 0,
        total: 20,
        updatedAt: 30,
      ));
      expect((await store.continueReading()).single.unit.id, unit('a', 2).id);
    }
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
      UnitProgress(
          unitId: unit('a', 1).id, position: 3, total: 20, updatedAt: 10),
    );

    await repository.removeFromLibrary('test::a');

    expect(await repository.library(), isEmpty);
    expect(await repository.mediaById('test::a'), isNotNull);
    expect(await repository.progressFor(unit('a', 1).id), isNotNull);
  });

  test('a work-level memo survives the round trip and is never cleared',
      () async {
    const memo = '{"path":"/manga/otherworldly-evil-monarch/"}';
    final media = Media(
      ref: const SourceRef('test', '775'),
      title: 'Otherworldly Evil Monarch',
      kind: MediaKind.manga,
      memo: memo,
      inLibrary: true,
      addedAt: 1,
    );
    await repository.saveMedia(media);
    expect((await repository.mediaById(media.id))!.memo, memo);

    // A later catalogue refresh that knows nothing about the memo must not
    // erase it: the chapter list depends on it.
    await repository.saveMedia(media.copyWith(memo: ''));
    expect((await repository.mediaById(media.id))!.memo, memo);

    final memory = MemoryLibraryRepository();
    await memory.saveMedia(media);
    await memory.saveMedia(media.copyWith(memo: '', title: 'refreshed'));
    final stored = await memory.mediaById(media.id);
    expect(stored!.memo, memo);
    expect(stored.title, 'refreshed');
    await memory.close();
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

  test('stores a download and reads it back', () async {
    final task = DownloadTask(
      unitId: unit('a', 1).id,
      mediaId: 'test::a',
      sourceId: 'test',
      mediaUrl: 'a',
      unitUrl: 'unit-1',
      mediaTitle: 'a',
      unitTitle: 'Chapter 1',
      total: 20,
      completed: 4,
      bytes: 4096,
      status: DownloadStatus.paused,
      directory: '/tmp/a',
      updatedAt: 7,
    );
    await repository.saveDownload(task);

    final stored = await repository.downloadFor(task.unitId);
    expect(stored, isNotNull);
    expect(stored!.status, DownloadStatus.paused);
    expect(stored.completed, 4);
    expect(stored.bytes, 4096);
    expect(stored.mediaUrl, 'a');
    expect(stored.unitUrl, 'unit-1');
    expect(await repository.downloads(), hasLength(1));

    await repository.deleteDownload(task.unitId);
    expect(await repository.downloadFor(task.unitId), isNull);
  });

  test('a chapter memo survives storage and a memo-less refresh', () async {
    await repository.saveMedia(work('a'));
    await repository.saveUnits([
      MediaUnit(
        mediaId: 'test::a',
        url: 'unit-1',
        number: 1,
        title: 'Chapter 1',
        kind: UnitKind.chapter,
        memo: '{"mangaPath":"/manga/a"}',
      ),
    ]);

    expect((await repository.unitsFor('test::a')).single.memo,
        '{"mangaPath":"/manga/a"}');

    // A later catalogue refresh that omits the memo must not erase the value
    // the reader needs when it opens the chapter.
    await repository.saveUnits([unit('a', 1)]);
    expect((await repository.unitsFor('test::a')).single.memo,
        '{"mangaPath":"/manga/a"}');
  });

  test('the in-memory library keeps a memo when a refresh omits it', () async {
    final memory = MemoryLibraryRepository();
    await memory.saveMedia(work('a'));
    await memory.saveUnits([
      MediaUnit(
        mediaId: 'test::a',
        url: 'unit-1',
        number: 1,
        title: 'Chapter 1',
        kind: UnitKind.chapter,
        memo: '{"mangaPath":"/manga/a"}',
      ),
    ]);
    await memory.saveUnits([unit('a', 1)]);

    expect((await memory.unitsFor('test::a')).single.memo,
        '{"mangaPath":"/manga/a"}');
  });

  test('upgrading a version 4 database adds the unit memo column', () async {
    final folder = await Directory.systemTemp.createTemp('best-memo-migrate');
    addTearDown(() async {
      if (await folder.exists()) await folder.delete(recursive: true);
    });
    final path = p.join(folder.path, 'best.db');

    final old = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 4,
        onCreate: (db, version) async {
          await db.execute('CREATE TABLE media (id TEXT PRIMARY KEY)');
          await db.execute('''
            CREATE TABLE unit (
              id TEXT PRIMARY KEY,
              media_id TEXT NOT NULL,
              url TEXT NOT NULL,
              kind TEXT NOT NULL,
              number REAL NOT NULL,
              title TEXT NOT NULL,
              published_at INTEGER NOT NULL DEFAULT 0,
              page_count INTEGER NOT NULL DEFAULT 0,
              UNIQUE (media_id, url)
            )
          ''');
          await db.execute("INSERT INTO media (id) VALUES ('test::a')");
          await db.execute('''
            INSERT INTO unit (id, media_id, url, kind, number, title)
            VALUES ('test::a::unit-1', 'test::a', 'unit-1', 'chapter', 1, 'Chapter 1')
          ''');
        },
      ),
    );
    await old.close();

    final upgraded = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    final migrated = SqfliteLibraryRepository(upgraded.db);
    addTearDown(migrated.close);

    final before = (await migrated.unitsFor('test::a')).single;
    expect(before.title, 'Chapter 1');
    expect(before.memo, '');

    await migrated
        .saveUnits([before.copyWith(memo: '{"mangaPath":"/manga/a"}')]);
    expect((await migrated.unitsFor('test::a')).single.memo,
        '{"mangaPath":"/manga/a"}');
  });

  test('upgrading a version 1 database adds the downloads table', () async {
    final folder = await Directory.systemTemp.createTemp('best-migrate-test');
    addTearDown(() async {
      if (await folder.exists()) await folder.delete(recursive: true);
    });
    final path = p.join(folder.path, 'best.db');

    final old = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('CREATE TABLE media (id TEXT PRIMARY KEY)');
        },
      ),
    );
    await old.close();

    final upgraded = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    final migrated = SqfliteLibraryRepository(upgraded.db);
    addTearDown(migrated.close);

    await migrated.saveDownload(
      DownloadTask(
        unitId: 'test::a::unit-1',
        mediaId: 'test::a',
        sourceId: 'test',
        mediaUrl: 'a',
        unitUrl: 'unit-1',
        mediaTitle: 'a',
        unitTitle: 'Chapter 1',
        total: 2,
        bytes: 8,
        status: DownloadStatus.queued,
        updatedAt: 1,
      ),
    );

    final rows = await migrated.downloads();
    expect(rows, hasLength(1));
    expect(rows.single.bytes, 8);
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

  test('the guide streams a real sample for episodes', () async {
    final source = DemoSource();
    final works = await source.popular();

    for (final media in works.where((work) => work.kind.isWatching)) {
      final units = await source.units(media);
      expect(units, isNotEmpty);
      expect(units.first.kind, UnitKind.episode);

      final resources = await source.resources(units.first);
      expect(resources, hasLength(1));
      final stream = resources.single;
      expect(stream, isA<VideoResource>());
      expect(
        Uri.parse((stream as VideoResource).url).isScheme('https'),
        isTrue,
        reason: '${media.displayTitle} must stream over TLS',
      );
    }
  });
}
