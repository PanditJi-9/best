import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

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
    // Page writes are deliberately unawaited so a page can paint before its
    // disk copy finishes. Give those writes a moment before removing the
    // temporary directory; a leftover temp folder is not a test failure.
    for (var attempt = 0; attempt < 20; attempt++) {
      if (!await directory.exists()) return;
      try {
        await directory.delete(recursive: true);
        return;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    }
  });

  PageImageCache cache(http.Client client) =>
      PageImageCache(client: client, directory: directory);

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
    await _waitForDisk(directory);
  });

  test('an authenticated loader is cached without a second request', () async {
    var loads = 0;
    final pages = cache(
      MockClient((request) async {
        fail('the HTTP client must never be used for an extension page');
      }),
    );
    const page = ImageResource('https://ext.test/signed/page.jpg');
    Future<Uint8List?> fetch() async {
      loads++;
      return Uint8List.fromList(const [3, 1, 4]);
    }

    final first = await pages.loadWith(page, fetch);
    expect(first, const [3, 1, 4]);
    expect(identical(pages.memoryBytes(page), first), isTrue);
    expect(await pages.loadWith(page, fetch), const [3, 1, 4]);
    expect(loads, 1);
  });

  test('an authenticated loader survives a new cache instance', () async {
    var loads = 0;
    const page = ImageResource('https://ext.test/signed/disk.jpg');
    Future<Uint8List?> fetch() async {
      loads++;
      return Uint8List.fromList(const [2, 7, 1]);
    }

    await cache(
      MockClient((_) async => http.Response('', 500)),
    ).loadWith(page, fetch);
    await _waitForDisk(directory);

    final reopened = cache(MockClient((_) async => http.Response('', 500)));
    expect(await reopened.loadWith(page, fetch), const [2, 7, 1]);
    expect(loads, 1);
  });

  test('a failed authenticated load is not cached', () async {
    var loads = 0;
    final pages = cache(MockClient((_) async => http.Response('', 500)));
    const page = ImageResource('https://ext.test/signed/missing.jpg');

    expect(
      await pages.loadWith(page, () async {
        loads++;
        return null;
      }),
      isNull,
    );
    expect(
      await pages.loadWith(page, () async {
        loads++;
        return Uint8List.fromList(const [9]);
      }),
      const [9],
    );
    expect(loads, 2);
  });

  test('concurrent loads share one request and the same byte buffer', () async {
    final started = Completer<void>();
    final response = Completer<http.Response>();
    final client = MockClient((request) {
      calls++;
      started.complete();
      return response.future;
    });
    final pages = cache(client);
    const page = ImageResource('https://cdn.test/concurrent.jpg');

    final first = pages.load(page);
    final second = pages.load(page);
    expect(identical(first, second), isTrue);
    await started.future;
    expect(calls, 1);
    response.complete(http.Response.bytes(const [4, 5, 6], 200));

    final results = await Future.wait([
      first,
      second,
    ]).timeout(const Duration(seconds: 5));
    expect(results.first, const [4, 5, 6]);
    expect(identical(results.first, results.last), isTrue);
    expect(identical(await pages.load(page), results.first), isTrue);
    expect(calls, 1);
  });

  test('header insertion order does not change the cache entry', () async {
    final client = MockClient((request) async {
      calls++;
      return http.Response.bytes(const [7, 8], 200);
    });
    final pages = cache(client);
    const first = ImageResource(
      'https://cdn.test/headers.jpg',
      headers: {'Referer': 'https://source.test', 'User-Agent': 'Best'},
    );
    const reordered = ImageResource(
      'https://cdn.test/headers.jpg',
      headers: {'User-Agent': 'Best', 'Referer': 'https://source.test'},
    );

    final bytes = await pages.load(first);
    expect(identical(await pages.load(reordered), bytes), isTrue);
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
