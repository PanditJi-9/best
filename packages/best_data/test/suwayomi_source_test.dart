import 'dart:convert';

import 'package:best_data/best_data.dart';
import 'package:best_domain/best_domain.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

const _jsonHeaders = {'content-type': 'application/json; charset=utf-8'};

const _sources = [
  {
    'id': '2499283573021220255',
    'name': 'MangaDex',
    'lang': 'en',
    'displayName': 'MangaDex (EN)',
    'iconUrl': '/api/v1/extension/icon/tachiyomi.en.mangadex',
    'supportsLatest': true,
    'isNsfw': false,
    'baseUrl': 'https://mangadex.org',
  },
  {
    'id': '99',
    'name': 'Adult Source',
    'lang': 'en',
    'displayName': 'Adult Source',
    'iconUrl': 'https://example.test/icon.png',
    'supportsLatest': false,
    'isNsfw': true,
    'baseUrl': 'https://example.test',
  },
];

const _manga = {
  'id': 42,
  'sourceId': '2499283573021220255',
  'url': '/manga/abc',
  'title': 'Blue Echo',
  'thumbnailUrl': '/api/v1/manga/42/thumbnail',
  'artist': 'A. Artist',
  'author': 'A. Author',
  'description': 'A test work.',
  'genre': ['Fantasy', 'Drama', 'Extra1', 'Extra2', 'Extra3', 'Extra4', 'Extra5',
    'Extra6', 'Extra7', 'Extra8', 'Extra9'],
  'status': 'ONGOING',
};

/// Answers exactly the paths the adapter is expected to call, and records them
/// so a test can assert the client never invents an endpoint.
class _Server {
  _Server();

  final List<Uri> calls = [];

  late final http.Client client = MockClient((request) async {
    calls.add(request.url);
    // A reverse-proxy prefix is the server's path, not part of the API.
    final path = request.url.path.replaceFirst('/suwayomi', '');

    if (path == '/api/v1/source/list') {
      return http.Response(jsonEncode(_sources), 200, headers: _jsonHeaders);
    }
    if (path == '/api/v1/source/2499283573021220255/popular/1') {
      return http.Response(
        jsonEncode({
          'mangaList': [_manga],
          'hasNextPage': true,
        }),
        200,
        headers: _jsonHeaders,
      );
    }
    if (path == '/api/v1/source/2499283573021220255/search') {
      final term = request.url.queryParameters['searchTerm'];
      return http.Response(
        jsonEncode({
          'mangaList': [
            {..._manga, 'title': 'Result for $term'},
          ],
          'hasNextPage': false,
        }),
        200,
        headers: _jsonHeaders,
      );
    }
    if (path == '/api/v1/manga/42/full') {
      return http.Response(jsonEncode(_manga), 200, headers: _jsonHeaders);
    }
    if (path == '/api/v1/manga/42/chapters') {
      return http.Response(
        jsonEncode([
          {
            'id': 7,
            'url': '/chapter/2',
            'name': 'The second one',
            'uploadDate': 1700000000,
            'chapterNumber': 2,
            'mangaId': 42,
            'index': 2,
            'fetchedAt': 1700000000,
            'downloaded': false,
            'pageCount': 4,
          },
          {
            'id': 6,
            'url': '/chapter/1',
            'name': '',
            'uploadDate': 1690000000000,
            'chapterNumber': 1,
            'mangaId': 42,
            'index': 1,
            'fetchedAt': 1690000000,
            'downloaded': false,
            'pageCount': -1,
          },
        ]),
        200,
        headers: _jsonHeaders,
      );
    }
    if (path == '/api/v1/manga/42/chapter/1') {
      return http.Response(
        jsonEncode({'id': 6, 'index': 1, 'pageCount': 3}),
        200,
        headers: _jsonHeaders,
      );
    }
    if (path == '/api/v1/manga/42/chapter/1/page/0') {
      return http.Response.bytes([1, 2, 3], 200);
    }
    return http.Response('not found', 404);
  });
}

void main() {
  SuwayomiClient build(_Server server, {String url = 'http://10.0.2.2:4567'}) =>
      SuwayomiClient(baseUrl: url, client: server.client);

  test('lists the server sources and hides adult ones', () async {
    final server = _Server();
    final sources = await build(server).sources();

    expect(sources, hasLength(2));
    expect(sources.first.id, '2499283573021220255');
    expect(sources.first.name, 'MangaDex (EN)');
    expect(sources.first.language, 'en');
    expect(sources.first.supportsLatest, isTrue);
    expect(sources.first.nsfw, isFalse);
    expect(sources[1].nsfw, isTrue);
    // A relative icon is resolved against the server, never dropped.
    expect(
      sources.first.iconUrl,
      'http://10.0.2.2:4567/api/v1/extension/icon/tachiyomi.en.mangadex',
    );
    expect(sources[1].iconUrl, 'https://example.test/icon.png');
  });

  test('reads a paged catalogue and maps its fields', () async {
    final server = _Server();
    final client = build(server);
    final page = await client.popular('2499283573021220255');

    expect(page, hasLength(1));
    final media = page.single;
    expect(media.ref.sourceId, 'suwayomi:2499283573021220255');
    expect(media.ref.url, '42');
    expect(media.title, 'Blue Echo');
    expect(media.kind, MediaKind.manga);
    expect(media.author, 'A. Author');
    expect(media.synopsis, 'A test work.');
    expect(media.status, MediaStatus.ongoing);
    expect(media.genres, hasLength(8));
    expect(
      media.coverUrl,
      'http://10.0.2.2:4567/api/v1/manga/42/thumbnail',
    );
  });

  test('sends the search term as a query parameter', () async {
    final server = _Server();
    final results = await build(server).search('2499283573021220255', 'echo');

    expect(results.single.title, 'Result for echo');
    final call = server.calls.last;
    expect(call.path, '/api/v1/source/2499283573021220255/search');
    expect(call.queryParameters['searchTerm'], 'echo');
    expect(call.queryParameters['pageNum'], '1');
  });

  test('reads chapters in order and normalises the two date units', () async {
    final server = _Server();
    final media = Media(
      ref: const SourceRef('suwayomi:2499283573021220255', '42'),
      title: 'Blue Echo',
      kind: MediaKind.manga,
    );
    final units = await build(server).chapters(media);

    expect(units.map((unit) => unit.number), [1, 2]);
    expect(units.first.displayTitle, 'Chapter 1');
    expect(units.last.title, 'The second one');
    expect(units.first.pageCount, 0, reason: '-1 means unknown, not minus one');
    expect(units.last.pageCount, 4);
    // Suwayomi reports seconds; one entry here reports milliseconds.
    expect(units.first.publishedAt, 1690000000000);
    expect(units.last.publishedAt, 1700000000000);
    // The unit url must carry both ids the page endpoint needs.
    expect(units.first.url, '42/1');
    expect(units.first.mediaId, media.id);
  });

  test('builds page URLs from the chapter page count', () async {
    final server = _Server();
    final pages = await build(server).pages(42, 1);

    expect(pages, hasLength(3));
    expect(
      (pages.first as ImageResource).url,
      'http://10.0.2.2:4567/api/v1/manga/42/chapter/1/page/0',
    );
    expect(
      (pages.last as ImageResource).url,
      'http://10.0.2.2:4567/api/v1/manga/42/chapter/1/page/2',
    );
  });

  test('keeps a path prefix for a server behind a reverse proxy', () async {
    final server = _Server();
    final client = build(server, url: 'https://example.test/suwayomi/');
    await client.sources();

    expect(server.calls.last.path, '/suwayomi/api/v1/source/list');
  });

  test('refuses an address that is not http or https', () {
    final server = _Server();
    expect(
      () => build(server, url: 'ftp://example.test'),
      throwsA(isA<SuwayomiException>()),
    );
    expect(
      () => build(server, url: 'not a url'),
      throwsA(isA<SuwayomiException>()),
    );
  });

  test('reports a bad status instead of returning half a catalogue', () async {
    final server = _Server();
    expect(
      () => build(server).manga(999, '2499283573021220255'),
      throwsA(isA<SuwayomiException>()),
    );
  });

  test('a source adapter exposes the server source under its own id', () async {
    final server = _Server();
    final client = build(server);
    final adapter = SuwayomiSource(
      client: client,
      info: (await client.sources()).first,
    );

    expect(adapter.id, 'suwayomi:2499283573021220255');
    expect(adapter.name, 'MangaDex (EN)');
    expect(adapter.language, 'en');

    final media = (await adapter.popular()).single;
    expect((await adapter.details(media)).title, 'Blue Echo');

    final unit = (await adapter.units(media)).first;
    final pages = await adapter.resources(unit);
    expect(pages, hasLength(3));
    expect(unit.url, '42/1');
  });
}
