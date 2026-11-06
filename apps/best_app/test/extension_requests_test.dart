import 'dart:async';

import 'package:best_app/src/extension_host.dart';
import 'package:best_domain/best_domain.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('best/extension-requests-test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const response = <String, dynamic>{
    'items': [
      {'url': '/anime/one', 'title': 'One'},
    ],
  };
  late ExtensionHost host;

  setUp(() => host = ExtensionHost(channel: channel));
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('overlapping catalogue reads invoke the extension only once', () async {
    final pending = Completer<Map<String, dynamic>>();
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) {
      calls++;
      return pending.future;
    });
    final requests = [
      host.popular(42, anime: true),
      host.popular(42, anime: true)
    ];
    await Future<void>.delayed(Duration.zero);
    final concurrentCalls = calls;
    pending.complete(response);
    final pages = await Future.wait(requests);
    expect(concurrentCalls, 1);
    expect(pages.every((page) => page.single.kind == MediaKind.anime), isTrue);
  });

  test('completed catalogue reads are not cached over an explicit refresh',
      () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls++;
      return response;
    });
    await host.popular(42, anime: true);
    await host.popular(42, anime: true);
    expect(calls, 2);
  });

  test('failed shared requests are removed so the next read can retry',
      () async {
    final pending = Completer<Map<String, dynamic>>();
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) {
      calls++;
      return calls == 1 ? pending.future : Future.value(response);
    });
    final failure = expectLater(
      Future.wait(
          [host.popular(42, anime: true), host.popular(42, anime: true)]),
      throwsA(isA<PlatformException>()),
    );
    pending.completeError(
        PlatformException(code: 'extension-error', message: 'rate limited'));
    await failure;
    expect((await host.popular(42, anime: true)).single.title, 'One');
    expect(calls, 2);
  });

  test(
      'different sources pages methods queries and media kinds stay independent',
      () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls++;
      return response;
    });
    await Future.wait([
      host.popular(42, anime: true),
      host.popular(43, anime: true),
      host.popular(42, page: 2, anime: true),
      host.popular(42),
      host.latest(42, anime: true),
      host.search(42, 'one', anime: true),
      host.search(42, 'two', anime: true),
    ]);
    expect(calls, 7);
  });

  test('a chapter memo reaches the page request it belongs to', () async {
    const memo = '{"mangaPath":"/manga/otherworldly-evil-monarch"}';
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'chapters') {
        return [
          {
            'url': 'chapter-1',
            'name': 'One',
            'chapterNumber': 1,
            'memo': memo,
          },
        ];
      }
      if (call.method == 'pages') return <dynamic>[];
      return null;
    });

    const media = Media(
      ref: SourceRef('mihon:42', 'manga-x'),
      title: 'X',
      kind: MediaKind.manga,
    );
    final units = await host.chapters(42, media);
    expect(units.single.memo, memo);

    await host.pages(42, units.single);

    expect(calls.last.method, 'pages');
    expect(calls.last.arguments,
        {'sourceId': 42, 'url': 'chapter-1', 'memo': memo});
  });

  test('a work memo travels with the chapter and details requests', () async {
    const memo = '{"path":"/manga/otherworldly-evil-monarch/"}';
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'chapters') {
        return [
          {'url': 'chapter-1', 'name': 'One', 'chapterNumber': 1, 'memo': ''},
        ];
      }
      if (call.method == 'details') {
        return {'url': '775', 'title': 'Otherworldly Evil Monarch'};
      }
      return null;
    });

    const media = Media(
      ref: SourceRef('mihon:42', '775'),
      title: 'Otherworldly Evil Monarch',
      kind: MediaKind.manga,
      memo: memo,
    );
    await host.chapters(42, media);
    expect(calls.last.method, 'chapters');
    expect(calls.last.arguments, {'sourceId': 42, 'url': '775', 'memo': memo});

    final fresh = await host.details(42, media);
    expect(calls.last.method, 'details');
    expect(calls.last.arguments, {'sourceId': 42, 'url': '775', 'memo': memo});
    // A details refresh that carries no memo must not wipe the one we have.
    expect(fresh.memo, memo);
  });

  test('a details refresh cannot replace a real manga path with the site root',
      () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'details') {
        // What a Madara source reports after being handed a bare post id: the
        // path of the page it fetched, which is the site root.
        return {
          'url': '775',
          'title': 'Otherworldly Evil Monarch',
          'memo': '{"path":"/","genres":[]}',
        };
      }
      return null;
    });

    const media = Media(
      ref: SourceRef('mihon:42', '775'),
      title: 'Otherworldly Evil Monarch',
      kind: MediaKind.manga,
      memo: '{"path":"/manga/otherworldly-evil-monarch/"}',
    );
    final fresh = await host.details(42, media);
    expect(fresh.memo, '{"path":"/manga/otherworldly-evil-monarch/"}');
    expect(fresh.title, 'Otherworldly Evil Monarch');
  });

  test('only mihon source references expose an extension id', () {
    expect(extensionSourceIdOf('mihon:1234'), 1234);
    expect(extensionSourceIdOf('mangadex'), isNull);
    expect(extensionSourceIdOf('mihon:not-a-number'), isNull);
    expect(extensionSourceIdOf(''), isNull);
  });

  test('page images are fetched through the extension host with their headers',
      () async {
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    MethodCall? seen;
    messenger.setMockMethodCallHandler(channel, (call) async {
      seen = call;
      return bytes;
    });

    final result = await host.imageBytes(
      42,
      'https://cdn.test/1.jpg',
      headers: const {'Referer': 'https://site.test'},
    );

    expect(result, bytes);
    expect(seen?.method, 'imageBytes');
    expect(seen?.arguments, {
      'sourceId': 42,
      'url': 'https://cdn.test/1.jpg',
      'headers': {'Referer': 'https://site.test'},
    });
  });

  test('a reader without a host falls back instead of failing', () async {
    expect(await host.imageBytes(42, 'https://cdn.test/1.jpg'), isNull);
  });

  test(
      'the offline adapter uses the signed image boundary with the original headers',
      () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return Uint8List.fromList([4, 3, 2, 1]);
    });
    final source = ExtensionSourceAdapter(
        host: host,
        info: ExtensionSourceInfo.fromMap({
          'sourceId': 42,
          'name': 'Test manga',
          'lang': 'en',
          'kind': 'manga',
        }));
    expect(source, isA<PageBytesSource>());
    expect(
        await source.pageBytes(
            const ImageResource('https://cdn.test/signed.jpg', headers: {
          'Referer': 'https://site.test/chapter',
          'X-Test': 'page'
        })),
        [4, 3, 2, 1]);
    expect(calls.single.method, 'imageBytes');
    expect(calls.single.arguments, {
      'sourceId': 42,
      'url': 'https://cdn.test/signed.jpg',
      'headers': {'Referer': 'https://site.test/chapter', 'X-Test': 'page'},
    });
  });
}
