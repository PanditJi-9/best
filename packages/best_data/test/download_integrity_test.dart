import 'dart:io';

import 'package:best_data/best_data.dart';
import 'package:best_domain/best_domain.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('best-integrity-');
  });
  tearDown(() => directory.delete(recursive: true));

  File page(int index) =>
      File('${directory.path}/${downloadedPageName(index)}');

  DownloadTask task({int total = 3}) => DownloadTask(
        unitId: 'unit',
        mediaId: 'work',
        sourceId: 'test',
        mediaUrl: 'work',
        unitUrl: 'unit',
        mediaTitle: 'Work',
        unitTitle: 'Chapter 1',
        total: total,
        directory: directory.path,
        status: DownloadStatus.done,
      );

  test('a streaming SHA-256 sidecar matches a known digest', () async {
    await page(0).writeAsBytes([97, 98, 99]);
    await writePageChecksum(page(0));
    expect(await File('${page(0).path}.sha256').readAsString(),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    expect(await storedPageIsIntact(page(0)), isTrue);
    await page(0).writeAsBytes([99, 98, 97]);
    expect(await storedPageIsIntact(page(0)), isFalse);
  });

  test(
      'missing, empty, malformed and legacy pages have distinct honest results',
      () async {
    await page(0).writeAsBytes([1]);
    await page(1).writeAsBytes([]);
    await page(3).writeAsBytes([1]);
    await File('${page(3).path}.sha256').writeAsString('not a checksum');
    final report = await inspectStoredDownload(task(total: 4));
    expect(report.available, 1);
    expect(report.verified, 0);
    expect(report.missing, [2]);
    expect(report.changed, [1, 3]);
    expect(report.isComplete, isFalse);
    expect(await storedPageIsIntact(page(0)), isTrue);
    expect(await storedPageIsIntact(page(1)), isFalse);
    expect(await storedPageIsIntact(page(2)), isFalse);
    expect(await storedPageIsIntact(page(3)), isFalse);
    expect(() => report.changed.add(0), throwsUnsupportedError);
  });

  test('unknown totals cannot fabricate a complete chapter', () async {
    await page(0).writeAsBytes([1]);
    final report = await inspectStoredDownload(task(total: 0));
    expect(report.total, 0);
    expect(report.isComplete, isFalse);
    expect(report.checksummed, isFalse);
  });

  test('a missing directory reports every expected page without throwing',
      () async {
    final report = await inspectStoredDownload(
        task().copyWith(directory: '${directory.path}/gone'));
    expect(report.missing, [0, 1, 2]);
    expect(report.available, 0);
  });

  test('an interrupted inspection cannot claim completion', () async {
    await page(0).writeAsBytes([1]);
    final report =
        await inspectStoredDownload(task(), shouldContinue: () => false);
    expect(report.busy, isTrue);
    expect(report.isComplete, isFalse);
  });

  test('a gap preserves original page numbers and later bytes on disk',
      () async {
    await page(0).writeAsBytes([1]);
    await page(2).writeAsBytes([3]);
    final pages = await downloadedPages(directory.path, expectedCount: 3);
    expect(pages, hasLength(1));
    expect((pages.single as FileResource).path, page(0).path);
    expect(await page(2).readAsBytes(), [3]);
    await page(1).writeAsBytes([2]);
    expect(
        (await downloadedPages(directory.path))
            .map((resource) => (resource as FileResource).path),
        [page(0).path, page(1).path, page(2).path]);
  });

  test('a missing first page or an empty gap never renumbers later files',
      () async {
    await page(1).writeAsBytes([2]);
    expect(await downloadedPages(directory.path), isEmpty);
    await page(0).writeAsBytes([1]);
    await page(1).writeAsBytes([]);
    await page(2).writeAsBytes([3]);
    expect(await downloadedPages(directory.path), hasLength(1));
    expect(await page(2).exists(), isTrue);
  });

  test('known totals cap reading without deleting extra files', () async {
    for (var index = 0; index < 3; index++) {
      await page(index).writeAsBytes([index]);
    }
    expect(
        await downloadedPages(directory.path, expectedCount: 2), hasLength(2));
    expect(await page(2).exists(), isTrue);
    expect(await downloadedPages(directory.path, expectedCount: 0), isEmpty);
    expect(await downloadedPages('${directory.path}/absent'), isEmpty);
  });

  test('byte accounting ignores sidecars, in-flight files and malformed names',
      () async {
    await page(0).writeAsBytes([1, 2, 3]);
    await writePageChecksum(page(0));
    for (final name in [
      'page_0000.img',
      'page_0002.img.part',
      'page_noise.img',
      'other.jpg'
    ]) {
      await File('${directory.path}/$name').writeAsBytes([1, 2, 3, 4]);
    }
    expect(await directoryBytes(directory.path), 3);
    expect(await downloadedPages(directory.path), hasLength(1));
    expect(downloadedPageName(0), 'page_0001.img');
    expect(downloadedPageName(9999), 'page_10000.img');
  });
}
