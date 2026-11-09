import 'dart:io';

import 'package:best_app/src/reader/page_image_cache.dart';
import 'package:best_domain/best_domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Future<void> _waitForDisk(Directory directory) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    final entries = await directory.list().toList();
    if (entries.whereType<File>().any((file) => file.path.endsWith('.img'))) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('the page image was never written to disk');
}

void main() {
  late Directory directory;
  late int calls;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('best-page-cache-');
    calls = 0;
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  PageImageCache cache(http.Client client) => PageImageCache(
        client: client,
        directory: directory,
      );

  test('a page is fetched once and then served from memory', () async {
    final client = MockClient((request) async {
      calls++;
      return http.Response.bytes(const [1, 2, 3, 4], 200);
    });
    final pages = cache(client);
    const page = ImageResource('https://cdn.test/one.jpg');

    expect(await pages.load(page), const [1, 2, 3, 4]);
    expect(await pages.load(page), const [1, 2, 3, 4]);
    expect(calls, 1);
  });

  test('a new cache instance reuses the file written by the first', () async {
    final client = MockClient((request) async {
      calls++;
      return http.Response.bytes(const [9, 8, 7], 200);
    });
    const page = ImageResource('https://cdn.test/disk.jpg');

    await cache(client).load(page);
    await _waitForDisk(directory);

    final reopened = cache(client);
    expect(await reopened.load(page), const [9, 8, 7]);
    expect(calls, 1);
  });

  test('the same URL with different headers is a different page', () async {
    final client = MockClient((request) async {
      calls++;
      return http.Response.bytes([calls], 200);
    });
    final pages = cache(client);
    const first = ImageResource(
      'https://cdn.test/signed.jpg',
      headers: {'Referer': 'https://a.test'},
    );
    const second = ImageResource(
      'https://cdn.test/signed.jpg',
      headers: {'Referer': 'https://b.test'},
    );

    expect(await pages.load(first), const [1]);
    expect(await pages.load(second), const [2]);
    expect(calls, 2);
  });

  test('evict removes both memory and disk, so a retry refetches', () async {
    final client = MockClient((request) async {
      calls++;
      return http.Response.bytes([calls], 200);
    });
    final pages = cache(client);
    const page = ImageResource('https://cdn.test/retry.jpg');

    expect(await pages.load(page), const [1]);
    await _waitForDisk(directory);
    await pages.evict(page);
    expect(await pages.load(page), const [2]);
    expect(calls, 2);
  });

  test('a failed response is not cached', () async {
    final client = MockClient((request) async {
      calls++;
      return http.Response('', 404);
    });
    final pages = cache(client);
    const page = ImageResource('https://cdn.test/missing.jpg');

    expect(await pages.load(page), isNull);
    expect(await pages.load(page), isNull);
    expect(calls, 2);
  });
}
