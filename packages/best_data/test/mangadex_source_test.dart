import 'dart:convert';

import 'package:best_data/best_data.dart';
import 'package:best_domain/best_domain.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

const _jsonHeaders = {'content-type': 'application/json; charset=utf-8'};

void main() {
  const manga = {
    'result': 'ok',
    'data': [
      {
        'id': 'abc',
        'type': 'manga',
        'attributes': {
          'title': {'en': 'Blue Echo', 'ja': '青い反響'},
          'altTitles': [
            {'ja': '青い反響'},
          ],
          'description': {'en': 'A test work.'},
          'originalLanguage': 'ko',
          'status': 'ongoing',
          'year': 2025,
          'tags': [
            {
              'attributes': {
                'name': {'en': 'Fantasy'},
              },
            },
          ],
        },
        'relationships': [
          {
            'type': 'cover_art',
            'attributes': {'fileName': 'cover.jpg'},
          },
        ],
      },
    ],
  };

  const feed = {
    'result': 'ok',
    'data': [
      {
        'id': 'ch1',
        'attributes': {
          'chapter': '1',
          'title': '',
          'pages': 3,
          'publishAt': '2025-01-01T00:00:00+00:00',
        },
      },
      {
        'id': 'ch1-dup',
        'attributes': {
          'chapter': '1',
          'title': 'Duplicate scanlator',
          'pages': 3
        },
      },
      {
        'id': 'ch2',
        'attributes': {'chapter': '2.5', 'title': 'Side story', 'pages': 4},
      },
      {
        'id': 'external',
        'attributes': {'chapter': '3', 'externalUrl': 'https://example.com'},
      },
    ],
  };

  const atHome = {
    'baseUrl': 'https://cdn.example',
    'chapter': {
      'hash': 'hash',
      'data': ['1.png', '2.png'],
    },
  };

  MangaDexSource source({void Function(Uri)? onRequest, int status = 200}) {
    final client = MockClient((request) async {
      onRequest?.call(request.url);
      if (status != 200) return http.Response('nope', status);
      final path = request.url.path;
      if (path == '/manga')
        return http.Response(jsonEncode(manga), 200, headers: _jsonHeaders);
      if (path == '/manga/abc/feed')
        return http.Response(jsonEncode(feed), 200, headers: _jsonHeaders);
      if (path == '/at-home/server/ch1')
        return http.Response(jsonEncode(atHome), 200, headers: _jsonHeaders);
      return http.Response('not found', 404);
    });
    return MangaDexSource(client: client, language: 'en');
  }

  test('maps a catalogue row onto the domain', () async {
    final works = await source().popular();
    expect(works, hasLength(1));
    final work = works.single;
    expect(work.title, 'Blue Echo');
    expect(work.nativeTitle, '青い反響');
    expect(work.kind, MediaKind.manhwa);
    expect(work.status, MediaStatus.ongoing);
    expect(work.year, 2025);
    expect(work.genres, ['Fantasy']);
    expect(work.coverUrl,
        'https://uploads.mangadex.org/covers/abc/cover.jpg.256.jpg');
    expect(work.id, 'mangadex::abc');
  });

  test('sends the search term as a title filter', () async {
    Uri? seen;
    final works =
        await source(onRequest: (uri) => seen = uri).search('  blue  ');
    expect(works, hasLength(1));
    expect(seen, isNotNull);
    expect(seen!.queryParameters['title'], 'blue');
  });

  test('parses chapters, dedupes numbers and skips external-only entries',
      () async {
    final work = (await source().popular()).single;
    final units = await source().units(work);

    expect(units.map((unit) => unit.number), [1, 2.5]);
    expect(units.first.title, 'Chapter 1');
    expect(units.last.title, 'Side story');
    expect(units.last.pageCount, 4);
    expect(units.first.id, 'mangadex::abc::ch1');
  });

  test('builds image URLs from the at-home response', () async {
    final work = (await source().popular()).single;
    final unit = (await source().units(work)).first;
    final pages = await source().resources(unit);

    expect(pages, hasLength(2));
    expect(
      (pages.first as ImageResource).url,
      'https://cdn.example/data/hash/1.png',
    );
  });

  test('turns a non-200 answer into a typed failure', () async {
    expect(
      () => source(status: 500).popular(),
      throwsA(isA<MangaDexException>()),
    );
  });
}
