import 'dart:async';
import 'dart:io';

import 'package:best_data/best_data.dart';
import 'package:best_domain/best_domain.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

class _FakeSource implements SourceAdapter {
  _FakeSource(this.pages);

  final int pages;
  int resourceCalls = 0;

  @override
  String get id => 'fake';

  @override
  String get name => 'Fake';

  @override
  String get language => 'en';

  @override
  Future<List<Media>> popular({int page = 1}) async => const <Media>[];

  @override
  Future<List<Media>> search(String query, {int page = 1}) async =>
      const <Media>[];

  @override
  Future<Media> details(Media media) async => media;

  @override
  Future<List<MediaUnit>> units(Media media) async => const <MediaUnit>[];

  @override
  Future<List<MediaResource>> resources(MediaUnit unit) async {
    resourceCalls++;
    return <MediaResource>[
      for (var index = 0; index < pages; index++)
        ImageResource('https://fake.test/${unit.url}/$index.jpg'),
    ];
  }
}

void main() {
  late Directory root;
  late MemoryLibraryRepository repository;
  late Media media;
  late MediaUnit unit;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('best-download-test');
    repository = MemoryLibraryRepository();
    media = const Media(
      ref: SourceRef('fake', 'blue-echo'),
      title: 'Blue Echo',
      kind: MediaKind.manhwa,
    );
    unit = MediaUnit(
      mediaId: media.id,
      url: 'chapter-1',
      number: 1,
      title: 'Chapter 1',
      kind: UnitKind.chapter,
      pageCount: 3,
    );
    await repository.saveMedia(media);
    await repository.saveUnits([unit]);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  DownloadManager managerFor(
    http.Client client, {
    int pages = 3,
  }) {
    return DownloadManager(
      repository: repository,
      registry: SourceRegistry.fixed(<SourceAdapter>[_FakeSource(pages)]),
      client: client,
      root: root,
    );
  }

  MockClient okClient() => MockClient((request) async {
        return http.Response.bytes(<int>[1, 2, 3, 4], 200);
      });

  test('downloads every page, persists progress and reads it back', () async {
    final manager = managerFor(okClient());
    await manager.enqueue(media, unit);
    await manager.pump();

    final task = await repository.downloadFor(unit.id);
    expect(task, isNotNull);
    expect(task!.status, DownloadStatus.done);
    expect(task.completed, 3);
    expect(task.total, 3);
    expect(task.directory, isNotNull);

    final files = Directory(task.directory!)
        .listSync()
        .whereType<File>()
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    expect(files, hasLength(3));
    expect(files.first.path, endsWith('page_0001.img'));

    final pages = await downloadedPages(task.directory!);
    expect(pages, hasLength(3));
    expect(pages.first, isA<FileResource>());
    expect((pages.first as FileResource).path, files.first.path);
  });

  test('pause keeps the page already in flight and resume finishes', () async {
    final started = Completer<void>();
    final gate = Completer<void>();
    var first = true;
    final client = MockClient((request) async {
      if (first) {
        first = false;
        started.complete();
        await gate.future;
      }
      return http.Response.bytes(<int>[1, 2, 3, 4], 200);
    });

    final manager = managerFor(client);
    await manager.enqueue(media, unit);
    await started.future;
    await manager.pause(unit.id);
    gate.complete();
    await manager.pump();

    final paused = await repository.downloadFor(unit.id);
    expect(paused!.status, DownloadStatus.paused);
    expect(paused.completed, 1);

    await manager.resume(unit.id);
    await manager.pump();
    final done = await repository.downloadFor(unit.id);
    expect(done!.status, DownloadStatus.done);
    expect(done.completed, 3);
  });

  test('a failed page is reported, then retried from where it stopped',
      () async {
    var failuresLeft = 2;
    final client = MockClient((request) async {
      if (failuresLeft > 0) {
        failuresLeft--;
        return http.Response('server error', 500);
      }
      return http.Response.bytes(<int>[1, 2, 3, 4], 200);
    });

    final manager = managerFor(client);
    await manager.enqueue(media, unit);
    await manager.pump();

    final failed = await repository.downloadFor(unit.id);
    expect(failed!.status, DownloadStatus.failed);
    expect(failed.error, contains('500'));

    await manager.retry(unit.id);
    await manager.pump();

    final done = await repository.downloadFor(unit.id);
    expect(done!.status, DownloadStatus.done);
    expect(done.completed, 3);
  });

  test('cancel removes the row and the bytes', () async {
    final manager = managerFor(okClient());
    await manager.enqueue(media, unit);
    await manager.pump();

    final task = await repository.downloadFor(unit.id);
    final directory = Directory(task!.directory!);
    expect(await directory.exists(), isTrue);

    await manager.cancel(unit.id);
    expect(await repository.downloadFor(unit.id), isNull);
    expect(await directory.exists(), isFalse);
  });

  test('restore queues a task the process left running', () async {
    final manager = managerFor(okClient());
    await repository.saveDownload(
      DownloadTask(
        unitId: unit.id,
        mediaId: media.id,
        sourceId: media.ref.sourceId,
        mediaUrl: media.ref.url,
        unitUrl: unit.url,
        mediaTitle: media.title,
        unitTitle: unit.title,
        total: 3,
        status: DownloadStatus.running,
        updatedAt: 1,
      ),
    );

    await manager.restore();
    await manager.pump();

    final task = await repository.downloadFor(unit.id);
    expect(task!.status, DownloadStatus.done);
    expect(task.completed, 3);
  });
}
