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

class _SignedSource extends _FakeSource implements PageBytesSource {
  _SignedSource(super.pages, this.fetch);

  final Future<List<int>?> Function(ImageResource page) fetch;
  final requests = <ImageResource>[];

  @override
  Future<List<int>?> pageBytes(ImageResource page) {
    requests.add(page);
    return fetch(page);
  }
}

class _ReadGateRepository extends MemoryLibraryRepository {
  Completer<void>? started;
  Completer<void>? gate;

  @override
  Future<DownloadTask?> downloadFor(String unitId) async {
    final pending = gate;
    if (pending != null) {
      gate = null;
      started!.complete();
      await pending.future;
    }
    return super.downloadFor(unitId);
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
    await repository.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  DownloadManager managerFor(
    http.Client client, {
    int pages = 3,
    SourceAdapter? source,
    bool installed = true,
  }) {
    final manager = DownloadManager(
      repository: repository,
      registry: SourceRegistry.fixed(
        installed ? <SourceAdapter>[source ?? _FakeSource(pages)] : [],
      ),
      client: client,
      root: root,
    );
    addTearDown(manager.dispose);
    addTearDown(client.close);
    return manager;
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
    expect(task.bytes, 12);
    expect(task.directory, isNotNull);

    final files = Directory(task.directory!)
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.img'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    expect(files, hasLength(3));
    expect(files.first.path, endsWith('page_0001.img'));

    final pages = await downloadedPages(task.directory!);
    expect(pages, hasLength(3));
    expect(pages.first, isA<FileResource>());
    expect((pages.first as FileResource).path, files.first.path);
    expect(await directoryBytes(task.directory!), 12);
    final report = await manager.checkStored(unit.id);
    expect(report.verified, 3);
    expect(report.checksummed, isTrue);
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
    expect(paused.bytes, 4);

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
    expect(done.bytes, 12);
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
    expect(task.bytes, 12);
  });

  test('repair fetches only missing, empty and checksum-changed pages',
      () async {
    final requests = <String>[];
    final manager = managerFor(MockClient((request) async {
      requests.add(request.url.path);
      return http.Response.bytes([1, 2, 3, 4], 200);
    }), pages: 5);
    await manager.enqueue(media, unit);
    await manager.pump();
    final saved = (await repository.downloadFor(unit.id))!;
    File page(int index) =>
        File('${saved.directory!}/${downloadedPageName(index)}');
    final retainedTime = DateTime.utc(2000);
    await page(0).setLastModified(retainedTime);
    await page(2).setLastModified(retainedTime);
    await page(1).delete();
    await page(3).writeAsBytes([]);
    await page(4).writeAsBytes([9, 8, 7, 6, 5, 4, 3]);
    requests.clear();

    final check = await manager.checkStored(unit.id);
    expect(check.missing, [1]);
    expect(check.changed, [3, 4]);
    expect(check.available, 2);
    expect(check.verified, 2);
    expect(requests, isEmpty);
    final damaged = (await repository.downloadFor(unit.id))!;
    expect(damaged.isFailed, isTrue);
    expect(damaged.completed, 2);
    expect(damaged.bytes, 15);

    await manager.repair(unit.id);
    await manager.pump();
    expect(
        requests, ['/chapter-1/1.jpg', '/chapter-1/3.jpg', '/chapter-1/4.jpg']);
    final repaired = (await repository.downloadFor(unit.id))!;
    expect(repaired.isFinished, isTrue);
    expect(repaired.directory, saved.directory);
    expect(repaired.completed, 5);
    expect(repaired.bytes, 20);
    expect((await page(0).lastModified()).toUtc(), retainedTime);
    expect((await page(2).lastModified()).toUtc(), retainedTime);
    expect((await manager.checkStored(unit.id)).checksummed, isTrue);
  });

  test('legacy pages are usable but are not claimed as checksum-verified',
      () async {
    var calls = 0;
    final manager = managerFor(MockClient((_) async {
      calls++;
      return http.Response.bytes([1, 2, 3, 4], 200);
    }));
    await manager.enqueue(media, unit);
    await manager.pump();
    final task = (await repository.downloadFor(unit.id))!;
    for (var index = 0; index < 3; index++) {
      await File('${task.directory!}/${downloadedPageName(index)}.sha256')
          .delete();
    }
    final report = await manager.checkStored(unit.id);
    expect(report.isComplete, isTrue);
    expect(report.verified, 0);
    expect(report.checksummed, isFalse);
    expect(calls, 3);
    await File('${task.directory!}/${downloadedPageName(1)}').delete();
    await manager.repair(unit.id);
    await manager.pump();
    expect(calls, 4);
    expect((await manager.checkStored(unit.id)).verified, 3);
  });

  test('the source signing client supplies download bytes, not ordinary HTTP',
      () async {
    var plainCalls = 0;
    final source = _SignedSource(3, (page) async => [4, 3, 2, 1]);
    final manager = managerFor(MockClient((_) async {
      plainCalls++;
      return http.Response('Cookies required', 403);
    }), source: source);
    await manager.enqueue(media, unit);
    await manager.pump();
    expect(plainCalls, 0);
    expect(source.requests.map((page) => page.url), [
      'https://fake.test/chapter-1/0.jpg',
      'https://fake.test/chapter-1/1.jpg',
      'https://fake.test/chapter-1/2.jpg',
    ]);
    final task = (await repository.downloadFor(unit.id))!;
    expect(task.isFinished, isTrue);
    expect(await File('${task.directory!}/page_0001.img').readAsBytes(),
        [4, 3, 2, 1]);
  });

  test('a declined signing client falls back to HTTP, while empty bytes fail',
      () async {
    var plainCalls = 0;
    final declined = _SignedSource(1, (_) async => null);
    final manager = managerFor(MockClient((_) async {
      plainCalls++;
      return http.Response.bytes([1], 200);
    }), source: declined);
    await manager.enqueue(media, unit);
    await manager.pump();
    expect(plainCalls, 1);
    expect((await repository.downloadFor(unit.id))!.isFinished, isTrue);

    await manager.cancel(unit.id);
    manager.dispose();
    final empty = _SignedSource(1, (_) async => []);
    final other = managerFor(MockClient((_) async {
      plainCalls++;
      return http.Response.bytes([1], 200);
    }), source: empty);
    await other.enqueue(media, unit);
    await other.pump();
    expect(empty.requests, hasLength(2));
    expect(plainCalls, 1);
    expect((await repository.downloadFor(unit.id))!.isFailed, isTrue);
  });

  test('repair observes the network rule and keeps intact files while waiting',
      () async {
    var calls = 0;
    final manager = managerFor(MockClient((_) async {
      calls++;
      return http.Response.bytes([1, 2, 3, 4], 200);
    }));
    await manager.enqueue(media, unit);
    await manager.pump();
    final task = (await repository.downloadFor(unit.id))!;
    await File('${task.directory!}/page_0002.img').delete();
    manager.mayDownload = () => false;
    await manager.repair(unit.id);
    expect(
        (await repository.downloadFor(unit.id))!.status, DownloadStatus.queued);
    expect(calls, 3);
    expect(await File('${task.directory!}/page_0001.img').readAsBytes(),
        [1, 2, 3, 4]);
    manager.mayDownload = () => true;
    await manager.pump();
    expect(calls, 4);
    expect((await repository.downloadFor(unit.id))!.isFinished, isTrue);
  });

  test('active checks are reported busy, not turned into damaged downloads',
      () async {
    final manager = managerFor(okClient())..mayDownload = () => false;
    await manager.enqueue(media, unit);
    final check = await manager.checkStored(unit.id);
    expect(check.busy, isTrue);
    expect(check.isComplete, isFalse);
    expect((await manager.repair(unit.id)).busy, isTrue);
    expect(
        (await repository.downloadFor(unit.id))!.status, DownloadStatus.queued);
  });

  test('an unknown count is not labelled corruption or silently finalized',
      () async {
    var calls = 0;
    final manager = managerFor(MockClient((_) async {
      calls++;
      return http.Response.bytes([1, 2, 3, 4], 200);
    }));
    await manager.enqueue(media, unit);
    await manager.pump();
    final task = (await repository.downloadFor(unit.id))!;
    await repository.saveDownload(task.copyWith(total: 0));
    final report = await manager.checkStored(unit.id);
    expect(report.isComplete, isFalse);
    expect((await repository.downloadFor(unit.id))!.error,
        DownloadException.countUnknown);
    expect(await downloadedPages(task.directory!), hasLength(3));
    await manager.repair(unit.id);
    await manager.pump();
    expect(calls, 3);
    expect((await repository.downloadFor(unit.id))!.total, 3);
  });

  test('a complete interrupted chapter can be finalized without its source',
      () async {
    final original = managerFor(okClient());
    await original.enqueue(media, unit);
    await original.pump();
    final task = (await repository.downloadFor(unit.id))!;
    await repository.saveDownload(task.copyWith(status: DownloadStatus.paused));
    original.dispose();
    var calls = 0;
    final offline = managerFor(MockClient((_) async {
      calls++;
      return http.Response('No network', 503);
    }), installed: false);
    final report = await offline.repair(unit.id);
    expect(report.isComplete, isTrue);
    expect((await repository.downloadFor(unit.id))!.isFinished, isTrue);
    expect(calls, 0);
  });

  test(
      'a missing source cannot delete good files or claim a damaged repair succeeded',
      () async {
    final original = managerFor(okClient());
    await original.enqueue(media, unit);
    await original.pump();
    final task = (await repository.downloadFor(unit.id))!;
    await File('${task.directory!}/page_0002.img').delete();
    original.dispose();
    final offline = managerFor(okClient(), installed: false);
    final report = await offline.checkStored(unit.id);
    expect(report.missing, [1]);
    await expectLater(
        offline.repair(unit.id), throwsA(isA<SourceNotInstalled>()));
    expect(await File('${task.directory!}/page_0001.img').readAsBytes(),
        [1, 2, 3, 4]);
    expect((await repository.downloadFor(unit.id))!.isFailed, isTrue);
  });

  test('a short source response cannot shrink a stored expected total',
      () async {
    final original = managerFor(okClient(), pages: 5);
    await original.enqueue(media, unit);
    await original.pump();
    final task = (await repository.downloadFor(unit.id))!;
    await File('${task.directory!}/page_0005.img').delete();
    original.dispose();
    var calls = 0;
    final short = managerFor(MockClient((_) async {
      calls++;
      return http.Response.bytes([1], 200);
    }), pages: 3);
    await short.repair(unit.id);
    await short.pump();
    final stopped = (await repository.downloadFor(unit.id))!;
    expect(stopped.total, 5);
    expect(stopped.completed, 4);
    expect(stopped.isFailed, isTrue);
    expect(stopped.error, DownloadException.sourceIncomplete);
    expect(calls, 0);
    expect(await File('${task.directory!}/page_0004.img').exists(), isTrue);
  });

  test('concurrent repairs share one queue entry and one replacement request',
      () async {
    var calls = 0;
    final manager = managerFor(MockClient((_) async {
      calls++;
      return http.Response.bytes([1, 2, 3, 4], 200);
    }));
    await manager.enqueue(media, unit);
    await manager.pump();
    final task = (await repository.downloadFor(unit.id))!;
    await File('${task.directory!}/page_0002.img').delete();
    final reports =
        await Future.wait([manager.repair(unit.id), manager.repair(unit.id)]);
    await manager.pump();
    expect(reports.where((report) => report.busy), hasLength(1));
    expect(calls, 4);
    expect((await repository.downloadFor(unit.id))!.isFinished, isTrue);
  });

  test('cancellation during a request cannot recreate its row or directory',
      () async {
    final started = Completer<void>();
    final gate = Completer<void>();
    final manager = managerFor(MockClient((_) async {
      started.complete();
      await gate.future;
      return http.Response.bytes([1, 2, 3, 4], 200);
    }));
    await manager.enqueue(media, unit);
    await started.future;
    final task = (await repository.downloadFor(unit.id))!;
    await manager.cancel(unit.id);
    gate.complete();
    await manager.pump();
    expect(await repository.downloadFor(unit.id), isNull);
    expect(await Directory(task.directory!).exists(), isFalse);
  });

  test('requeue after cancellation does not inherit an old response or cleanup',
      () async {
    final started = Completer<void>();
    final gate = Completer<void>();
    var calls = 0;
    final manager = managerFor(MockClient((_) async {
      calls++;
      if (calls == 1) {
        started.complete();
        await gate.future;
        return http.Response.bytes([99], 200);
      }
      return http.Response.bytes([1, 2, 3, 4], 200);
    }));
    await manager.enqueue(media, unit);
    await started.future;
    await manager.cancel(unit.id);
    await manager.enqueue(media, unit);
    gate.complete();
    await manager.pump();
    final task = (await repository.downloadFor(unit.id))!;
    expect(task.isFinished, isTrue);
    expect(task.bytes, 12);
    expect(calls, 4);
    expect(await File('${task.directory!}/page_0001.img').readAsBytes(),
        [1, 2, 3, 4]);
    expect((await manager.checkStored(unit.id)).checksummed, isTrue);
  });

  test('a cancelled check cannot overwrite deletion with a failed row',
      () async {
    await repository.close();
    final gated = _ReadGateRepository();
    repository = gated;
    await repository.saveMedia(media);
    await repository.saveUnits([unit]);
    final manager = managerFor(okClient());
    await manager.enqueue(media, unit);
    await manager.pump();
    final task = (await repository.downloadFor(unit.id))!;
    await File('${task.directory!}/page_0002.img').delete();
    gated.started = Completer<void>();
    final gate = Completer<void>();
    gated.gate = gate;
    final checked = expectLater(
        manager.checkStored(unit.id), throwsA(isA<DownloadException>()));
    await gated.started!.future;
    final cancelled = manager.cancel(unit.id);
    gate.complete();
    await checked;
    await cancelled;
    expect(await repository.downloadFor(unit.id), isNull);
    expect(await Directory(task.directory!).exists(), isFalse);
  });
}
