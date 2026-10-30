import 'dart:convert';

import 'package:best_data/best_data.dart';
import 'package:best_domain/best_domain.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

Map<String, Object?> _pack({
  String baseUrl = 'https://api.example.com',
  String search = '/search?q={query}&page={page}',
}) {
  return {
    'id': 'example',
    'name': 'Example',
    'language': 'ar',
    'baseUrl': baseUrl,
    'kind': 'manhwa',
    'headers': {'referer': 'https://example.com'},
    'routes': {
      'popular': '/popular?page={page}',
      'search': search,
      'details': '/series/{id}',
      'chapters': '/series/{id}/chapters',
      'pages': '/chapter/{id}/pages',
    },
    'map': {
      'media': {
        'list': 'data',
        'id': 'slug',
        'title': 'title',
        'cover': 'cover',
        'kind': 'type',
        'status': 'status',
        'genres': 'genres',
      },
      'unit': {
        'list': 'chapters',
        'id': 'id',
        'number': 'number',
        'title': 'title',
        'date': 'publishedAt',
        'pages': 'pages',
      },
      'page': {'list': 'pages', 'url': 'url'},
    },
  };
}

JsonSourceAdapter _adapter(
  Map<String, Object?> pack,
  Future<http.Response> Function(http.Request) handler,
) {
  return JsonSourceAdapter(
    pack: SourcePack.parse(jsonEncode(pack)),
    client: MockClient(handler),
  );
}

http.Response _json(Object? body, {int status = 200}) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  group('SourcePack validation', () {
    test('accepts a complete pack and exposes its identity', () {
      final pack = SourcePack.parse(jsonEncode(_pack()));
      expect(pack.id, 'example');
      expect(pack.name, 'Example');
      expect(pack.language, 'ar');
      expect(pack.defaultKind, MediaKind.manhwa);
      expect(pack.headers['referer'], 'https://example.com');
    });

    test('rejects plain http outside loopback', () {
      expect(
        () => SourcePack.parse(
          jsonEncode(_pack(baseUrl: 'http://api.example.com')),
        ),
        throwsA(isA<SourcePackException>()),
      );
    });

    test('allows http on loopback for self-hosted catalogues', () {
      final pack = SourcePack.parse(
        jsonEncode(_pack(baseUrl: 'http://127.0.0.1:8080')),
      );
      expect(pack.baseUrl, 'http://127.0.0.1:8080');
    });

    test('rejects a search route without a query placeholder', () {
      expect(
        () => SourcePack.parse(
          jsonEncode(_pack(search: '/search?page={page}')),
        ),
        throwsA(isA<SourcePackException>()),
      );
    });

    test('rejects an id that could collide with a built-in source', () {
      final bad = _pack()..['id'] = 'Example Pack';
      expect(
        () => SourcePack.parse(jsonEncode(bad)),
        throwsA(isA<SourcePackException>()),
      );
    });

    test('rejects invalid JSON and non-objects', () {
      expect(() => SourcePack.parse('{'), throwsA(isA<SourcePackException>()));
      expect(() => SourcePack.parse('[]'), throwsA(isA<SourcePackException>()));
      expect(() => SourcePack.parse(''), throwsA(isA<SourcePackException>()));
    });

    test('rejects a pack over the size cap', () {
      final huge = 'x' * (kMaxSourcePackBytes + 1);
      expect(
        () => SourcePack.parse(huge),
        throwsA(isA<SourcePackException>()),
      );
    });
  });

  group('JsonSourceAdapter', () {
    test('maps a popular page into media with absolute covers', () async {
      final adapter = _adapter(_pack(), (request) async {
        expect(request.url.path, '/popular');
        expect(request.url.queryParameters['page'], '2');
        expect(request.headers['referer'], 'https://example.com');
        return _json({
          'data': [
            {
              'slug': 'blue-echo',
              'title': 'Blue Echo',
              'cover': '/covers/blue.jpg',
              'type': 'manhwa',
              'status': 'ongoing',
              'genres': ['Action', ' Drama '],
            },
            {'slug': 'no-title'},
          ],
        });
      });

      final results = await adapter.popular(page: 2);
      expect(results, hasLength(1));
      final media = results.single;
      expect(media.ref.sourceId, 'example');
      expect(media.ref.url, 'blue-echo');
      expect(media.title, 'Blue Echo');
      expect(media.kind, MediaKind.manhwa);
      expect(media.status, MediaStatus.ongoing);
      expect(media.genres, ['Action', 'Drama']);
      expect(media.coverUrl, 'https://api.example.com/covers/blue.jpg');
    });

    test('encodes the search term instead of pasting it into the url',
        () async {
      final adapter = _adapter(_pack(), (request) async {
        expect(request.url.queryParameters['q'], 'ظل الغابة & co');
        expect(request.url.queryParameters['page'], '1');
        return _json({'data': <Object?>[]});
      });

      expect(await adapter.search('ظل الغابة & co'), isEmpty);
    });

    test('falls back to the pack kind when a row omits its type', () async {
      final adapter = _adapter(_pack(), (_) async {
        return _json({
          'data': [
            {'slug': 'a', 'title': 'A'},
          ],
        });
      });
      expect((await adapter.popular()).single.kind, MediaKind.manhwa);
    });

    test('maps chapters with fractional numbers and dates', () async {
      final adapter = _adapter(_pack(), (request) async {
        expect(request.url.path, '/series/blue-echo/chapters');
        return _json({
          'chapters': [
            {
              'id': 'c1',
              'number': '12.5',
              'title': 'The crossing',
              'publishedAt': '2026-01-02T03:04:05Z',
              'pages': 18,
            },
            {'id': 'c2'},
          ],
        });
      });

      final media = Media(
        ref: const SourceRef('example', 'blue-echo'),
        title: 'Blue Echo',
        kind: MediaKind.manhwa,
      );
      final units = await adapter.units(media);

      expect(units, hasLength(2));
      expect(units.first.number, 12.5);
      expect(units.first.title, 'The crossing');
      expect(units.first.pageCount, 18);
      expect(units.first.publishedAt, greaterThan(0));
      expect(units.first.mediaId, media.id);
      expect(units.last.number, 2);
      expect(units.last.displayTitle, 'Chapter 2');
    });

    test('resolves page urls and carries request headers', () async {
      final adapter = _adapter(_pack(), (_) async {
        return _json({
          'pages': [
            {'url': '/img/1.jpg'},
            {'url': 'https://cdn.example.net/2.jpg'},
            {'broken': true},
          ],
        });
      });

      final unit = MediaUnit(
        mediaId: 'example::blue-echo',
        url: 'c1',
        number: 1,
        title: 'Chapter 1',
        kind: UnitKind.chapter,
      );
      final pages = await adapter.resources(unit);

      expect(pages, hasLength(2));
      final first = pages.first as ImageResource;
      expect(first.url, 'https://api.example.com/img/1.jpg');
      expect(first.headers['referer'], 'https://example.com');
      expect(
          (pages.last as ImageResource).url, 'https://cdn.example.net/2.jpg');
    });

    test('details keeps the library flags owned by the repository', () async {
      final adapter = _adapter(_pack(), (_) async {
        return _json({
          'slug': 'blue-echo',
          'title': 'Blue Echo (complete)',
          'type': 'manhwa',
        });
      });

      final media = Media(
        ref: const SourceRef('example', 'blue-echo'),
        title: 'Blue Echo',
        kind: MediaKind.manhwa,
        inLibrary: true,
        favorite: true,
        addedAt: 7,
        lastOpenedAt: 9,
      );
      final detailed = await adapter.details(media);

      expect(detailed.title, 'Blue Echo (complete)');
      expect(detailed.inLibrary, isTrue);
      expect(detailed.favorite, isTrue);
      expect(detailed.addedAt, 7);
      expect(detailed.lastOpenedAt, 9);
    });

    test('surfaces transport failures as pack errors', () async {
      final adapter = _adapter(_pack(), (_) async => _json({}, status: 503));
      expect(
        () => adapter.popular(),
        throwsA(isA<SourcePackException>()),
      );
    });

    test('rejects a payload whose list path is not a list', () async {
      final adapter = _adapter(_pack(), (_) async => _json({'data': 'nope'}));
      expect(
        () => adapter.popular(),
        throwsA(isA<SourcePackException>()),
      );
    });
  });
}
