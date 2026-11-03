import 'dart:async';
import 'dart:typed_data';

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
}
