import 'dart:io';

import 'package:best_app/src/providers.dart';
import 'package:best_data/best_data.dart';
import 'package:best_domain/best_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _UnavailableSource implements SourceAdapter {
  @override
  String get id => 'test';
  @override
  String get name => 'Test source';
  @override
  String get language => 'all';
  @override
  Future<Media> details(Media media) async => media;
  @override
  Future<List<Media>> popular({int page = 1}) async => [];
  @override
  Future<List<Media>> search(String query, {int page = 1}) async => [];
  @override
  Future<List<MediaUnit>> units(Media media) async =>
      throw const HttpException('Offline');
  @override
  Future<List<MediaResource>> resources(MediaUnit unit) async =>
      throw const HttpException('Offline');
}

void main() {
  final work = Media(
    ref: const SourceRef('test', 'cached-work'),
    title: 'Cached work',
    kind: MediaKind.manga,
    inLibrary: true,
  );
  final unit = MediaUnit(
    mediaId: work.id,
    url: 'chapter-1',
    number: 1,
    title: 'Chapter 1',
    kind: UnitKind.chapter,
    pageCount: 10,
  );

  Future<(MemoryLibraryRepository, ProviderContainer, Directory)> setup(
    List<SourceAdapter> sources,
  ) async {
    final repository = MemoryLibraryRepository();
    await repository.saveMedia(work);
    await repository.saveUnits([unit]);
    final directory =
        await Directory.systemTemp.createTemp('best-reader-cache-');
    final container = ProviderContainer(overrides: [
      repositoryProvider.overrideWithValue(repository),
      sourceRegistryProvider.overrideWithValue(SourceRegistry.fixed(sources)),
    ]);
    addTearDown(() async {
      container.dispose();
      await repository.close();
      await directory.delete(recursive: true);
    });
    return (repository, container, directory);
  }

  DownloadTask task(Directory directory,
          {DownloadStatus status = DownloadStatus.done}) =>
      DownloadTask(
        unitId: unit.id,
        mediaId: work.id,
        sourceId: 'test',
        mediaUrl: work.ref.url,
        unitUrl: unit.url,
        mediaTitle: work.title,
        unitTitle: unit.title,
        total: 10,
        completed: 2,
        directory: directory.path,
        status: status,
      );

  const key = (sourceId: 'test', url: 'cached-work', unitUrl: 'chapter-1');

  test('stored pages remain readable after removing their source', () async {
    final (repository, container, directory) = await setup([]);
    // Provider recovery checks file availability; decoding is covered by reader
    // widget/render tests and the Android image smoke gate.
    for (var page = 0; page < 10; page++) {
      await File(
              '${directory.path}/page_${(page + 1).toString().padLeft(4, '0')}.img')
          .writeAsBytes([1]);
    }
    await repository.saveDownload(task(directory).copyWith(completed: 10));
    final reader = await container.read(readerProvider(key).future);
    expect(reader.offline, isTrue);
    expect(reader.partial, isFalse);
    expect(reader.totalPages, 10);
    expect(reader.resources, hasLength(10));
    expect(reader.resources.first, isA<FileResource>());
  });

  test('missing sources with no stored pages report an actionable typed error',
      () async {
    final (_, container, _) = await setup([]);
    await expectLater(
      container.read(readerProvider(key).future),
      throwsA(isA<SourceNotInstalled>()),
    );
  });

  test(
      'an interrupted download preserves expected totals and never claims a whole chapter',
      () async {
    final (repository, container, directory) =
        await setup([_UnavailableSource()]);
    await File('${directory.path}/page_0001.img').writeAsBytes([1]);
    await repository.saveDownload(
        task(directory, status: DownloadStatus.paused).copyWith(completed: 1));
    final reader = await container.read(readerProvider(key).future);
    expect(reader.offline, isTrue);
    expect(reader.partial, isTrue);
    expect(reader.totalPages, 10);
    expect(reader.resources, hasLength(1));
  });

  test(
      'a finished task with missing files is shown as partial rather than fabricated completion',
      () async {
    final (repository, container, directory) = await setup([]);
    await File('${directory.path}/page_0001.img').writeAsBytes([1]);
    await repository.saveDownload(task(directory));
    final reader = await container.read(readerProvider(key).future);
    expect(reader.partial, isTrue);
    expect(reader.totalPages, 10);
    expect(reader.resources, hasLength(1));
  });

  test('a gap never moves a later file into the missing page identity',
      () async {
    final (repository, container, directory) = await setup([]);
    for (final number in [1, 3, 10]) {
      await File(
              '${directory.path}/page_${number.toString().padLeft(4, '0')}.img')
          .writeAsBytes([number]);
    }
    await repository.saveDownload(task(directory).copyWith(completed: 3));
    await repository.saveProgress(UnitProgress(
        unitId: unit.id, position: 8, total: 10, started: true, updatedAt: 1));
    final reader = await container.read(readerProvider(key).future);
    expect(reader.resources, hasLength(1));
    expect((reader.resources.single as FileResource).path,
        endsWith('page_0001.img'));
    expect(reader.progress!.position, 8);
    expect(reader.partial, isTrue);
    expect(await File('${directory.path}/page_0003.img').exists(), isTrue);
  });

  test('known task totals cap cached pages without deleting extras', () async {
    final (repository, container, directory) = await setup([]);
    await File('${directory.path}/page_0001.img').writeAsBytes([1]);
    await File('${directory.path}/page_0002.img').writeAsBytes([2]);
    await repository
        .saveDownload(task(directory).copyWith(total: 1, completed: 1));
    final reader = await container.read(readerProvider(key).future);
    expect(reader.resources, hasLength(1));
    expect(reader.totalPages, 1);
    expect(reader.partial, isFalse);
    expect(await File('${directory.path}/page_0002.img').exists(), isTrue);
  });

  test(
      'a legacy zero task count falls back to known chapter metadata, not prefix completion',
      () async {
    final (repository, container, directory) = await setup([]);
    await File('${directory.path}/page_0001.img').writeAsBytes([1]);
    await repository
        .saveDownload(task(directory).copyWith(total: 0, completed: 1));
    final reader = await container.read(readerProvider(key).future);
    expect(reader.partial, isTrue);
    expect(reader.totalPages, 10);
  });
}
