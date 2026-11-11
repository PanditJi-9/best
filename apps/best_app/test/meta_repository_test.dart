import 'package:best_app/src/meta/meta_models.dart';
import 'package:best_app/src/meta/meta_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// MAL serves a table on the top list: one `tr.ranking-list` per work.
const String _topHtml = '''
<table>
<tr class="ranking-list">
  <td class="rank ac" valign="top">
    <span class="lightLink top-anime-rank-text rank1">1</span>
  </td>
  <td class="title al va-t word-break">
    <a class="hoverinfo_trigger fl-l ml12 mr8" href="https://myanimelist.net/anime/52991/Sousou_no_Frieren">
      <img width="50" height="70" class="lazyload" data-src="https://cdn.myanimelist.net/r/50x70/images/anime/1015/138006.jpg" />
    </a>
    <h3 class="fl-l fs14 fw-b anime_ranking_h3"><a href="https://myanimelist.net/anime/52991/Sousou_no_Frieren">Sousou no Frieren</a></h3>
    <div class="information di-ib mt4">
        TV (28 eps)<br>
        Sep 2023 - Mar 2024<br>
        1,540,103 members
    </div>
  </td>
  <td class="score ac fs14"><span class="text on score-label score-9">9.24</span></td>
</tr>
<tr class="ranking-list">
  <td class="rank ac" valign="top">
    <span class="lightLink top-anime-rank-text rank2">2</span>
  </td>
  <td class="title al va-t word-break">
    <a href="https://myanimelist.net/anime/5114/Fullmetal_Alchemist__Brotherhood">
      <img data-src="https://cdn.myanimelist.net/images/anime/1208/94745.jpg" />
    </a>
    <h3 class="fl-l fs14 fw-b anime_ranking_h3"><a href="https://myanimelist.net/anime/5114/Fullmetal_Alchemist__Brotherhood">Fullmetal Alchemist: Brotherhood</a></h3>
    <div class="information di-ib mt4">
        TV (64 eps)<br>
        Apr 2009 - Jul 2010<br>
        2,900,000 members
    </div>
  </td>
  <td class="score ac fs14"><span class="text on score-label score-9">9.09</span></td>
</tr>
</table>
''';

/// MAL search is a table too, but rows start with a `picSurround` poster.
const String _searchHtml = '''
<table>
<tr>
  <td class="borderClass bgColor1" valign="top" width="50">
    <div class="picSurround">
      <a href="https://myanimelist.net/anime/52991/Sousou_no_Frieren">
        <img data-src="https://cdn.myanimelist.net/r/50x70/images/anime/1015/138006.jpg" class="lazyload" />
      </a>
    </div>
  </td>
  <td class="borderClass bgColor0" valign="top">
    <div class="title" style="display: inline-flex;"><a class="hoverinfo_trigger fw-b fl-l" href="https://myanimelist.net/anime/52991/Sousou_no_Frieren"><strong>Sousou no Frieren</strong></a></div>
    <div class="pt4">An elf mage outlives her party and learns to know humans.</div>
  </td><td class="borderClass ac bgColor0" width="45">
    TV
  </td><td class="borderClass ac bgColor0" width="40">
    28
  </td><td class="borderClass ac bgColor0" width="50">
    9.24
  </td>
</tr>
</table>
''';

/// The detail page lists facts in `spaceit_pad` divs.
const String _detailHtml = '''
<html><head>
<meta property="og:title" content="Sousou no Frieren" />
<meta property="og:description" content="An elf mage outlives her party. [Written by MAL Rewrite]" />
<meta property="og:image" content="https://cdn.myanimelist.net/images/anime/1015/138006.jpg" />
</head><body>
<h1><span itemprop="name">Sousou no Frieren</span></h1>
<div class="spaceit_pad"><span class="dark_text">Japanese:</span> 葬送のフリーレン </div>
<div class="spaceit_pad"><span class="dark_text">Type:</span> <a href="/topanime.php?type=tv">TV</a> </div>
<div class="spaceit_pad"><span class="dark_text">Episodes:</span> 28 </div>
<div class="spaceit_pad"><span class="dark_text">Status:</span> Finished Airing </div>
<div class="spaceit_pad"><span class="dark_text">Aired:</span> Sep 29, 2023 to Mar 22, 2024 </div>
<div class="spaceit_pad"><span class="dark_text">Premiered:</span> <a href="/anime/season/2023/fall">Fall 2023</a> </div>
<div class="spaceit_pad"><span class="dark_text">Duration:</span> 24 min. per ep. </div>
<div class="spaceit_pad"><span class="dark_text">Rating:</span> PG-13 - Teens 13 or older </div>
<div class="spaceit_pad"><span class="dark_text">Studios:</span> <a href="/anime/producer/11/Madhouse" title="Madhouse">Madhouse</a> </div>
<div class="spaceit_pad"><span class="dark_text">Source:</span> <a href="#related">Manga</a> </div>
<div class="genres"><span itemprop="genre" style="display: none">Adventure</span><a>Adventure</a><span itemprop="genre" style="display: none">Fantasy</span></div>
<div class="spaceit_pad js-statistics-info"><span class="dark_text">Score:</span>
  <span itemprop="ratingValue" class="score-label score-9">9.24</span><sup>1</sup> (scored by <span itemprop="ratingCount" style="display: none">950539</span>950,539 users)</div>
<div class="spaceit_pad"><span class="dark_text">Ranked:</span> #1<sup>2</sup></div>
<div class="spaceit_pad"><span class="dark_text">Popularity:</span> #95</div>
<div class="spaceit_pad"><span class="dark_text">Members:</span> 1,539,293</div>
<div class="spaceit_pad"><span class="dark_text">Favorites:</span> 94,588</div>
</body></html>
''';

MetaRepository _repository(
  Future<http.Response> Function(http.Request) handler,
) {
  return MetaRepository(client: MockClient(handler));
}

void main() {
  test('the MyAnimeList top list is read from its table layout', () async {
    final repository = _repository((request) async {
      expect(request.url.path, '/topanime.php');
      return http.Response(_topHtml, 200);
    });

    final works = await repository.list(MetaListKind.malTop);

    expect(works, hasLength(2));
    final first = works.first;
    expect(first.title, 'Sousou no Frieren');
    expect(first.source, MetaSource.myAnimeList);
    expect(first.score, 9.24);
    expect(first.scoreSource, 'MyAnimeList');
    expect(first.rank, 1);
    expect(first.votes, 1540103);
    expect(first.format, 'TV');
    expect(first.episodes, 28);
    expect(first.coverUrl, startsWith('https://cdn.myanimelist.net/'));
    expect(
      first.siteUrl,
      'https://myanimelist.net/anime/52991/Sousou_no_Frieren',
    );
    expect(first.malId, 52991);
    expect(works[1].rank, 2);
  });

  test(
    'a top page that cannot be read is a failure, not an empty list',
    () async {
      final repository = _repository(
        (request) async => http.Response('<html>Nothing here</html>', 200),
      );

      expect(
        repository.list(MetaListKind.malTop),
        throwsA(isA<MetaException>()),
      );
    },
  );

  test('the MyAnimeList search page is read from its table layout', () async {
    final repository = _repository((request) async {
      if (request.method == 'POST') {
        return http.Response(
          '{"data":{"Page":{"media":[]}}}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path.contains('anime.php')) {
        return http.Response(_searchHtml, 200);
      }
      return http.Response('<html></html>', 200);
    });

    final results = await repository.search('Frieren');

    expect(results.failures, isEmpty);
    expect(results.anime, hasLength(1));
    final work = results.anime.single;
    expect(work.title, 'Sousou no Frieren');
    expect(work.score, 9.24);
    expect(work.format, 'TV');
    expect(work.episodes, 28);
    expect(work.synopsis, contains('outlives her party'));
  });

  test('the home catalogue includes the highest-rated AniList rail', () async {
    final repository = _repository((request) async {
      if (request.method == 'POST') {
        return http.Response(
          '{"data":{'
          '"trending":{"media":[{"id":1,"type":"ANIME","title":{"romaji":"Trending"}}]},'
          '"airing":{"media":[{"id":2,"type":"ANIME","title":{"romaji":"Airing"}}]},'
          '"top":{"media":[{"id":3,"type":"ANIME","title":{"romaji":"Top Score"},"averageScore":93}]}'
          '}}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path == '/topanime.php') {
        return http.Response(_topHtml, 200);
      }
      if (request.url.path == '/feed/') {
        return http.Response(
          '<rss><channel><item><title>News</title>'
          '<link>https://animecorner.me/example/</link>'
          '<description><![CDATA[A story]]></description></item></channel></rss>',
          200,
        );
      }
      return http.Response('<html></html>', 200);
    });

    final home = await repository.home();

    expect(home.trending.single.title, 'Trending');
    expect(home.airing.single.title, 'Airing');
    expect(home.topAniList.single.title, 'Top Score');
    expect(home.topAniList.single.score, 9.3);
    expect(home.topMal, isNotEmpty);
  });

  test('the MyAnimeList detail page is read from its current layout', () async {
    final repository = _repository((request) async {
      expect(request.url.path, '/anime/52991');
      // The page carries a Japanese title, so the body must be declared UTF-8;
      // http.Response otherwise encodes it as Latin-1.
      return http.Response(
        _detailHtml,
        200,
        headers: {'content-type': 'text/html; charset=utf-8'},
      );
    });

    final work = await repository.detail(MetaSource.myAnimeList, '52991');

    expect(work.title, 'Sousou no Frieren');
    expect(work.score, 9.24);
    expect(work.scoreSource, 'MyAnimeList');
    expect(work.rank, 1);
    expect(work.popularityRank, 95);
    expect(work.favourites, 94588);
    expect(work.votes, 1539293);
    expect(work.format, 'TV');
    expect(work.episodes, 28);
    expect(work.status, 'Finished Airing');
    expect(work.duration, '24 min. per ep.');
    expect(work.year, 2023);
    expect(work.studios, ['Madhouse']);
    expect(work.genres, ['Adventure', 'Fantasy']);
    expect(work.nativeTitle, '葬送のフリーレン');
    expect(work.synopsis, 'An elf mage outlives her party.');
  });
}
