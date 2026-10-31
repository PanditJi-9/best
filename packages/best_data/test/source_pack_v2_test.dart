import 'package:best_data/best_data.dart';
import 'package:test/test.dart';

void main() {
  const pagePack = '''
{
  "id": "example.manga",
  "name": "Example",
  "baseUrl": "https://example.com",
  "routes": {
    "popular": "/popular/{page}",
    "search": "/search?q={query}",
    "chapters": "/work/{id}/chapters",
    "pages": "/chapter/{id}/pages"
  },
  "map": {
    "media": {"list": "data", "id": "slug", "title": "title"},
    "unit": {"list": "data", "id": "slug", "number": "num"},
    "page": {"list": "data", "url": "image"}
  }
}
''';

  const videoPack = '''
{
  "version": 2,
  "id": "example.stream",
  "name": "Example Stream",
  "language": "ar",
  "baseUrl": "https://stream.example.com",
  "kind": "anime",
  "unitKind": "episode",
  "routes": {
    "popular": "/popular/{page}",
    "search": "/search?q={query}",
    "chapters": "/show/{id}/episodes",
    "pages": "/episode/{id}/pages",
    "watch": "/episode/{id}/streams"
  },
  "map": {
    "media": {"list": "data", "id": "slug", "title": "title"},
    "unit": {"list": "data", "id": "slug", "number": "num"},
    "page": {"list": "data", "url": "image"},
    "video": {"list": "data", "url": "file", "subtitle": "vtt"}
  }
}
''';

  test('a format-1 pack still parses and stays a page pack', () {
    final pack = SourcePack.parse(pagePack);
    expect(pack.version, 1);
    expect(pack.isVideo, isFalse);
    expect(pack.video, isNull);
  });

  test('a format-2 pack carries a watch route and a subtitle field', () {
    final pack = SourcePack.parse(videoPack);
    expect(pack.version, 2);
    expect(pack.isVideo, isTrue);
    expect(pack.defaultKind.name, 'anime');
    expect(pack.defaultUnitKind.name, 'episode');
    expect(pack.video?.subtitle, 'vtt');
  });

  test('a newer format is refused instead of guessed', () {
    expect(
      () => SourcePack.parse('{"version":3,"id":"a.b","name":"x",'
          '"baseUrl":"https://a.b","routes":{"popular":"/p/{page}",'
          '"search":"/s?q={query}","chapters":"/c/{id}","pages":"/p/{id}"},'
          '"map":{"media":{"list":"d","id":"i","title":"t"},'
          '"unit":{"list":"d","id":"i"},"page":{"list":"d","url":"u"}}}'),
      throwsA(isA<SourcePackException>()),
    );
  });

  test('a watch route without a video map is refused', () {
    expect(
      () => SourcePack.parse(videoPack.replaceFirst(
        '"video": {"list": "data", "url": "file", "subtitle": "vtt"}',
        '"page2": {"list": "data", "url": "file"}',
      )),
      throwsA(isA<SourcePackException>()),
    );
  });

  test('encode round-trips through parse', () {
    for (final raw in [pagePack, videoPack]) {
      final pack = SourcePack.parse(raw);
      final again = SourcePack.parse(pack.encode());
      expect(again.id, pack.id);
      expect(again.version, pack.version);
      expect(again.isVideo, pack.isVideo);
      expect(again.baseUrl, pack.baseUrl);
      expect(again.media.title, pack.media.title);
      expect(again.video?.url, pack.video?.url);
    }
  });

  test('an exported pack resolves the same routes', () {
    final pack = SourcePack.parse(SourcePack.parse(videoPack).encode());
    expect(
      pack.resolve(pack.watch!, {'id': 'ep 1'}).toString(),
      'https://stream.example.com/episode/ep%201/streams',
    );
  });
}
