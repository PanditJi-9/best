import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'meta_models.dart';

/// A failure a person can read. The database is made of four independent
/// services, so the message says which one did not answer.
class MetaException implements Exception {
  const MetaException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _CacheEntry {
  const _CacheEntry(this.value, this.expires, this.generation);

  final Future<Object?> value;
  final DateTime expires;

  /// The refresh counter the entry was created under. A later bump makes it
  /// stale once, instead of disabling the cache for the rest of the session.
  final int generation;
}

/// Reads the four public catalogues and turns them into one shape.
///
/// Rules that keep this honest:
/// * every score keeps the name of the community that published it;
/// * a field a provider does not publish is left null;
/// * one provider failing never blanks the page;
/// * searches are cached, so typing does not hammer anyone's endpoint.
class MetaRepository {
  MetaRepository({required http.Client client}) : _client = client;

  final http.Client _client;
  final Map<String, _CacheEntry> _cache = <String, _CacheEntry>{};

  static const Map<String, String> _headers = {
    'Accept': 'application/json, text/html;q=0.9, */*;q=0.8',
    'User-Agent': 'Best/1.0 (+https://github.com/PanditJi-9/best)',
  };

  static const String _anilistEndpoint = 'https://graphql.anilist.co';
  static const String _malEndpoint = 'https://myanimelist.net';
  static const String _hwaEndpoint = 'https://hwa.so';
  static const String _animeCornerFeed = 'https://animecorner.me/feed/';

  static const String _anilistMediaFields = r'''
    id
    idMal
    type
    title { romaji english native }
    coverImage { extraLarge large color }
    bannerImage
    description(asHtml: false)
    averageScore
    meanScore
    popularity
    favourites
    genres
    status
    format
    episodes
    chapters
    duration
    season
    seasonYear
    countryOfOrigin
    isAdult
    siteUrl
    startDate { year month day }
    endDate { year month day }
    studios(isMain: true) { nodes { name } }
    rankings { rank type allTime context }
    tags { name rank isMediaSpoiler }
    externalLinks { id url site type }
    streamingEpisodes { title thumbnail url site }
    nextAiringEpisode { episode airingAt timeUntilAiring }
  ''';

  Future<MetaHome> home({int generation = 0}) {
    return _cached<MetaHome>(
      'home',
      const Duration(minutes: 6),
      _loadHome,
      generation: generation,
    );
  }

  Future<MetaWork> detail(
    MetaSource source,
    String id, {
    int generation = 0,
  }) {
    return _cached<MetaWork>(
      'detail:${source.name}:$id',
      const Duration(minutes: 30),
      () => switch (source) {
        MetaSource.anilist => _anilistDetail(int.tryParse(id)),
        MetaSource.myAnimeList => _malDetail(int.tryParse(id)),
        MetaSource.hwa => _hwaDetail(id),
        MetaSource.animeCorner => throw const MetaException(
            'Anime Corner publishes articles, not titles.',
          ),
      },
      generation: generation,
    );
  }

  Future<MetaSearchResults> search(String rawQuery, {int generation = 0}) {
    final query = rawQuery.trim();
    if (query.length < 2) {
      return Future<MetaSearchResults>.value(
        MetaSearchResults(query: query),
      );
    }
    return _cached<MetaSearchResults>(
      'search:${query.toLowerCase()}',
      const Duration(minutes: 10),
      () => _loadSearch(query),
      generation: generation,
    );
  }

  Future<List<MetaWork>> list(MetaListKind kind, {int generation = 0}) {
    return _cached<List<MetaWork>>(
      'list:${kind.name}',
      const Duration(minutes: 10),
      () => switch (kind) {
        MetaListKind.anilistTrending => _anilistList('TRENDING_DESC', 30),
        MetaListKind.anilistTop => _anilistList('SCORE_DESC', 30),
        MetaListKind.anilistAiring => _anilistAiring(30),
        MetaListKind.malTop => _malTop(30),
        MetaListKind.hwaTop => _hwaTop(30),
      },
      generation: generation,
    );
  }

  // ---------------------------------------------------------------------------
  // Home

  Future<MetaHome> _loadHome() async {
    final failures = <MetaSource, String>{};

    Future<List<MetaWork>> guard(
      MetaSource source,
      Future<List<MetaWork>> future,
    ) async {
      try {
        return await future;
      } catch (error) {
        failures[source] = _message(error);
        return const <MetaWork>[];
      }
    }

    Future<({List<MetaWork> trending, List<MetaWork> airing})>
        guardAniList() async {
      try {
        return await _anilistHome();
      } catch (error) {
        failures[MetaSource.anilist] = _message(error);
        return (trending: const <MetaWork>[], airing: const <MetaWork>[]);
      }
    }

    Future<List<MetaNews>> guardNews() async {
      try {
        return await _animeCornerNews(4);
      } catch (error) {
        failures[MetaSource.animeCorner] = _message(error);
        return const <MetaNews>[];
      }
    }

    // hwa.so is the slowest catalogue by far (9-18s from a cold page), so it
    // is not part of this wait: the screen fills its shelf from its own
    // provider and the rest of the database opens immediately.
    final results = await Future.wait<Object>([
      guardAniList(),
      guard(MetaSource.myAnimeList, _malTop(10)),
      guardNews(),
    ]);

    final ani =
        results[0] as ({List<MetaWork> trending, List<MetaWork> airing});
    return MetaHome(
      trending: ani.trending,
      airing: ani.airing,
      topMal: results[1] as List<MetaWork>,
      news: results[2] as List<MetaNews>,
      failures: Map.unmodifiable(failures),
    );
  }

  Future<({List<MetaWork> trending, List<MetaWork> airing})>
      _anilistHome() async {
    final data = await _anilist(
      r'''
      query {
        trending: Page(page: 1, perPage: 12) {
          media(type: ANIME, sort: TRENDING_DESC, isAdult: false) {
            ''' +
          _anilistMediaFields +
          r'''
          }
        }
        airing: Page(page: 1, perPage: 12) {
          media(type: ANIME, status: RELEASING, sort: POPULARITY_DESC, isAdult: false) {
            ''' +
          _anilistMediaFields +
          r'''
          }
        }
      }
      ''',
    );

    List<MetaWork> read(String key) {
      final page = data[key];
      if (page is! Map<String, dynamic>) return const <MetaWork>[];
      final media = page['media'];
      if (media is! List) return const <MetaWork>[];
      return media
          .whereType<Map<String, dynamic>>()
          .map(_anilistWork)
          .toList(growable: false);
    }

    return (trending: read('trending'), airing: read('airing'));
  }

  Future<List<MetaWork>> _anilistList(String sort, int limit) async {
    final data = await _anilist(
      '''
      query {
        Page(page: 1, perPage: $limit) {
          media(type: ANIME, sort: $sort, isAdult: false) {
            $_anilistMediaFields
          }
        }
      }
      ''',
    );
    return _anilistPage(data);
  }

  Future<List<MetaWork>> _anilistAiring(int limit) async {
    final data = await _anilist(
      '''
      query {
        Page(page: 1, perPage: $limit) {
          media(type: ANIME, status: RELEASING, sort: POPULARITY_DESC, isAdult: false) {
            $_anilistMediaFields
          }
        }
      }
      ''',
    );
    return _anilistPage(data);
  }

  Future<List<MetaWork>> _anilistSearch(String query) async {
    final data = await _anilist(
      r'''
      query($search: String) {
        Page(page: 1, perPage: 14) {
          media(search: $search, type: ANIME, isAdult: false, sort: SEARCH_MATCH) {
            ''' +
          _anilistMediaFields +
          r'''
          }
        }
      }
      ''',
      variables: {'search': query},
    );
    return _anilistPage(data);
  }

  List<MetaWork> _anilistPage(Map<String, dynamic> data) {
    final page = data['Page'];
    if (page is! Map<String, dynamic>) return const <MetaWork>[];
    final media = page['media'];
    if (media is! List) return const <MetaWork>[];
    return media
        .whereType<Map<String, dynamic>>()
        .map(_anilistWork)
        .toList(growable: false);
  }

  Future<MetaWork> _anilistDetail(int? id) async {
    if (id == null) throw const MetaException('AniList id is missing.');
    final data = await _anilist(
      r'''
      query($id: Int) {
        Media(id: $id, type: ANIME) {
          ''' +
          _anilistMediaFields +
          r'''
          recommendations(perPage: 8, sort: RATING_DESC) {
            nodes {
              mediaRecommendation {
                ''' +
          _anilistMediaFields +
          r'''
              }
            }
          }
        }
      }
      ''',
      variables: {'id': id},
    );
    final media = data['Media'];
    if (media is! Map<String, dynamic>) {
      throw const MetaException('AniList did not return this title.');
    }
    final work = _anilistWork(media);
    final recommendations = <MetaWork>[];
    final recs = media['recommendations'];
    if (recs is Map<String, dynamic>) {
      final nodes = recs['nodes'];
      if (nodes is List) {
        for (final node in nodes.whereType<Map<String, dynamic>>()) {
          final rec = node['mediaRecommendation'];
          if (rec is Map<String, dynamic>) {
            recommendations.add(_anilistWork(rec));
          }
        }
      }
    }
    return _withRecommendations(work, recommendations);
  }

  MetaWork _anilistWork(Map<String, dynamic> media) {
    final title = _map(media['title']);
    final cover = _map(media['coverImage']);
    final rankings = _list(media['rankings']).whereType<Map<String, dynamic>>();
    int? ratedRank;
    int? popularRank;
    for (final ranking in rankings) {
      if (ranking['allTime'] != true) continue;
      if (ranking['type'] == 'RATED') ratedRank ??= _int(ranking['rank']);
      if (ranking['type'] == 'POPULAR') {
        popularRank ??= _int(ranking['rank']);
      }
    }

    final studios = <String>[];
    final studioMap = _map(media['studios']);
    for (final node
        in _list(studioMap['nodes']).whereType<Map<String, dynamic>>()) {
      final name = _string(node['name']);
      if (name != null) studios.add(name);
    }

    final tags = <MetaTag>[];
    for (final tag in _list(media['tags']).whereType<Map<String, dynamic>>()) {
      if (tag['isMediaSpoiler'] == true) continue;
      final name = _string(tag['name']);
      if (name != null) tags.add(MetaTag(name: name, rank: _int(tag['rank'])));
    }
    tags.sort((a, b) => (b.rank ?? 0).compareTo(a.rank ?? 0));

    final links = <MetaLink>[];
    for (final link
        in _list(media['externalLinks']).whereType<Map<String, dynamic>>()) {
      final url = _string(link['url']);
      final site = _string(link['site']);
      if (url != null && site != null) {
        links.add(MetaLink(label: site, url: url, kind: 'official'));
      }
    }
    for (final episode in _list(media['streamingEpisodes'])
        .whereType<Map<String, dynamic>>()) {
      final url = _string(episode['url']);
      final site = _string(episode['site']);
      if (url != null && site != null) {
        links.add(MetaLink(label: site, url: url, kind: 'streaming'));
      }
    }

    final start = _map(media['startDate']);
    final next = _map(media['nextAiringEpisode']);
    final type = _string(media['type']);
    final average = _int(media['averageScore']);
    final duration = _int(media['duration']);

    return MetaWork(
      id: '${media['id']}',
      source: MetaSource.anilist,
      kind: switch (type) {
        'MANGA' => MetaKind.manga,
        'ANIME' => MetaKind.anime,
        _ => MetaKind.unknown,
      },
      title: _firstNonEmpty([
            _string(title['romaji']),
            _string(title['english']),
            _string(title['native']),
          ]) ??
          '—',
      englishTitle: _string(title['english']),
      nativeTitle: _string(title['native']),
      coverUrl: _firstNonEmpty([
        _string(cover['extraLarge']),
        _string(cover['large']),
      ]),
      bannerUrl: _string(media['bannerImage']),
      synopsis: _stripHtml(_string(media['description']) ?? ''),
      genres: _stringList(media['genres']),
      score: average == null ? null : average / 10,
      scoreSource: average == null ? null : 'AniList',
      votes: _int(media['popularity']),
      rank: ratedRank,
      popularityRank: popularRank,
      favourites: _int(media['favourites']),
      format: _string(media['format']),
      status: _string(media['status']),
      episodes: _int(media['episodes']),
      chapters: _int(media['chapters']),
      duration: duration == null ? null : '$duration min',
      year: _int(media['seasonYear']) ?? _int(start['year']),
      season: _string(media['season']),
      country: _string(media['countryOfOrigin']),
      siteUrl: _string(media['siteUrl']),
      malId: _int(media['idMal']),
      anilistId: _int(media['id']),
      studios: studios,
      links: links,
      tags: tags.take(8).toList(growable: false),
      nextEpisode: _int(next['episode']),
      nextEpisodeAt: _int(next['airingAt']),
      isAdult: media['isAdult'] == true,
    );
  }

  MetaWork _withRecommendations(MetaWork work, List<MetaWork> recommendations) {
    return MetaWork(
      id: work.id,
      source: work.source,
      kind: work.kind,
      title: work.title,
      englishTitle: work.englishTitle,
      nativeTitle: work.nativeTitle,
      coverUrl: work.coverUrl,
      bannerUrl: work.bannerUrl,
      synopsis: work.synopsis,
      genres: work.genres,
      score: work.score,
      scoreSource: work.scoreSource,
      votes: work.votes,
      rank: work.rank,
      popularityRank: work.popularityRank,
      favourites: work.favourites,
      format: work.format,
      status: work.status,
      episodes: work.episodes,
      chapters: work.chapters,
      duration: work.duration,
      year: work.year,
      season: work.season,
      country: work.country,
      siteUrl: work.siteUrl,
      malId: work.malId,
      anilistId: work.anilistId,
      slug: work.slug,
      authors: work.authors,
      artists: work.artists,
      studios: work.studios,
      publishers: work.publishers,
      links: work.links,
      tags: work.tags,
      recommendations: recommendations,
      nextEpisode: work.nextEpisode,
      nextEpisodeAt: work.nextEpisodeAt,
      isAdult: work.isAdult,
    );
  }

  // ---------------------------------------------------------------------------
  // MyAnimeList

  Future<List<MetaWork>> _malTop(int limit) async {
    final response =
        await _get(Uri.parse('$_malEndpoint/topanime.php?limit=0'));
    final works =
        _malCards(_text(response)).take(limit).toList(growable: false);
    // A top list is never empty. Zero rows means the page changed shape, and
    // saying so is better than showing a ranking with nothing in it.
    if (works.isEmpty) {
      throw const MetaException(
        'MyAnimeList returned a page Best could not read.',
      );
    }
    return works;
  }

  Future<List<MetaWork>> _malSearch(String query) async {
    final uri = Uri.parse(
      '$_malEndpoint/anime.php?q=${Uri.encodeQueryComponent(query)}&cat=anime',
    );
    final response = await _get(uri);
    final html = _text(response);
    final works = _malSearchCards(html);
    if (works.isNotEmpty) return works.take(10).toList(growable: false);
    return _malSearchLegacy(html).take(10).toList(growable: false);
  }

  /// MAL's search results in the table layout it uses today: one
  /// `picSurround` per row, then type / episodes / score cells.
  List<MetaWork> _malSearchCards(String html) {
    final works = <MetaWork>[];
    final chunks = html.split('<div class="picSurround">');
    for (final chunk in chunks.skip(1)) {
      final link = RegExp(
        r'href="(https://myanimelist\.net/anime/(\d+)/[^"]+)"',
      ).firstMatch(chunk);
      final title = RegExp(r'<strong>([^<]+)</strong>').firstMatch(chunk);
      if (link == null || title == null) continue;
      final cover = RegExp(r'data-src="([^"]+)"').firstMatch(chunk);
      final summary = RegExp(
        r'<div class="pt4">(.*?)</div>',
        dotAll: true,
      ).firstMatch(chunk);
      final type = RegExp(
        r'<td class="borderClass ac bgColor[01]" width="45">\s*([^<]*)</td>',
      ).firstMatch(chunk);
      final episodes = RegExp(
        r'<td class="borderClass ac bgColor[01]" width="40">\s*([^<]*)</td>',
      ).firstMatch(chunk);
      final score = RegExp(
        r'<td class="borderClass ac bgColor[01]" width="50">\s*([0-9.]+)\s*</td>',
      ).firstMatch(chunk);
      final parsedType = _malType(type?.group(1));
      works.add(
        MetaWork(
          id: link.group(2)!,
          source: MetaSource.myAnimeList,
          kind: MetaKind.anime,
          title: _decode(title.group(1)!),
          coverUrl: cover == null ? null : _decode(cover.group(1)!),
          synopsis: summary == null
              ? null
              : _stripHtml(_decode(summary.group(1)!))
                  .replaceAll(RegExp(r'\s*read more\.\s*$'), ''),
          score: score == null ? null : double.tryParse(score.group(1)!),
          scoreSource: score == null ? null : 'MyAnimeList',
          format: parsedType.$1,
          episodes: parsedType.$2 ?? int.tryParse(episodes?.group(1) ?? ''),
          siteUrl: _decode(link.group(1)!),
          malId: int.tryParse(link.group(2)!),
        ),
      );
    }
    return works;
  }

  /// The layout MAL used before the 2026 redesign, kept so a rollback or an
  /// A/B bucket still produces results instead of an empty page.
  List<MetaWork> _malSearchLegacy(String html) {
    final works = <MetaWork>[];
    final chunks = html.split('<div class="box-unit1">');
    for (final chunk in chunks.skip(1)) {
      final link = RegExp(
        r'<a class="box-unit1-btn di-box" href="(https://myanimelist\.net/anime/(\d+)/[^"]+)">',
      ).firstMatch(chunk);
      if (link == null) continue;
      final title = RegExp(r'<li class="title">([^<]+)</li>').firstMatch(chunk);
      if (title == null) continue;
      final score = RegExp(
        r'<span class="di-ib fn-grey5 fs12 pr4">Score</span>\s*([0-9.]+)',
      ).firstMatch(chunk);
      final type = RegExp(
        r'<dd class="fn-grey5 fs12 fw-n pt8">([^<]+)</dd>',
      ).firstMatch(chunk);
      final summary = RegExp(
        r'<li class="text mt8">([^<]*)</li>',
      ).firstMatch(chunk);
      final image = RegExp(r'data-src="([^"]+)"').firstMatch(chunk) ??
          RegExp(r'<img[^>]+src="([^"]+)"').firstMatch(chunk);
      final parsedType = _malType(type?.group(1));
      works.add(
        MetaWork(
          id: link.group(2)!,
          source: MetaSource.myAnimeList,
          kind: MetaKind.anime,
          title: _decode(title.group(1)!),
          coverUrl: image == null ? null : _decode(image.group(1)!),
          synopsis: summary == null ? null : _decode(summary.group(1)!),
          score: score == null ? null : double.tryParse(score.group(1)!),
          scoreSource: score == null ? null : 'MyAnimeList',
          format: parsedType.$1,
          episodes: parsedType.$2,
          siteUrl: _decode(link.group(1)!),
          malId: int.tryParse(link.group(2)!),
        ),
      );
    }
    return works;
  }

  /// MAL's top list in the table layout it uses today: one
  /// `tr.ranking-list` per work.
  List<MetaWork> _malCards(String html) {
    final works = _malRankingCards(html);
    if (works.isNotEmpty) return works;
    return _malRankingLegacy(html);
  }

  List<MetaWork> _malRankingCards(String html) {
    final works = <MetaWork>[];
    final chunks = html.split('<tr class="ranking-list">');
    for (final chunk in chunks.skip(1)) {
      final link = RegExp(
        r'href="(https://myanimelist\.net/anime/(\d+)/[^"]+)"',
      ).firstMatch(chunk);
      final title = RegExp(r'anime_ranking_h3[^>]*>\s*<a[^>]*>([^<]+)</a>')
              .firstMatch(chunk) ??
          RegExp(r'<h3[^>]*>\s*<a[^>]*>([^<]+)</a>').firstMatch(chunk);
      if (link == null || title == null) continue;
      final cover = RegExp(r'data-src="([^"]+)"').firstMatch(chunk);
      final rank =
          RegExp(r'top-anime-rank-text[^"]*">\s*(\d+)').firstMatch(chunk);
      final info = RegExp(
        r'<div class="information di-ib mt4">\s*([^<]+)<br>',
      ).firstMatch(chunk);
      final score = RegExp(
        r'score-label[^"]*">\s*([0-9.]+)\s*<',
      ).firstMatch(chunk);
      final members = RegExp(r'([\d,]+)\s+members').firstMatch(chunk);
      final parsedType = _malType(info?.group(1));
      works.add(
        MetaWork(
          id: link.group(2)!,
          source: MetaSource.myAnimeList,
          kind: MetaKind.anime,
          title: _decode(title.group(1)!),
          coverUrl: cover == null ? null : _decode(cover.group(1)!),
          score: score == null ? null : double.tryParse(score.group(1)!),
          scoreSource: score == null ? null : 'MyAnimeList',
          votes: members == null ? null : _number(members.group(1)!),
          rank: rank == null ? null : int.tryParse(rank.group(1)!),
          format: parsedType.$1,
          episodes: parsedType.$2,
          siteUrl: _decode(link.group(1)!),
          malId: int.tryParse(link.group(2)!),
        ),
      );
    }
    return works;
  }

  /// The tile layout MAL used before the 2026 redesign.
  List<MetaWork> _malRankingLegacy(String html) {
    final works = <MetaWork>[];
    final chunks = html.split('<div class="tile-unit lazyload');
    for (final chunk in chunks.skip(1)) {
      final link = RegExp(
        r'<a href="(https://myanimelist\.net/anime/(\d+)/[^"]+)" class="thumb">',
      ).firstMatch(chunk);
      final title = RegExp(r'<h2 class="title">([^<]+)</h2>').firstMatch(chunk);
      if (link == null || title == null) continue;
      final cover = RegExp(r'data-bg="([^"]+)"').firstMatch(chunk);
      final rank = RegExp(
        r'<div class="rank[^"]*"><span class="text">(\d+)</span>',
      ).firstMatch(chunk);
      final type = RegExp(
        r'<span class="type[^"]*">(.*?)</span>',
        dotAll: true,
      ).firstMatch(chunk);
      final score = RegExp(
        r'<span class="score[^"]*">.*?</i>\s*([0-9.]+)\s*</span>',
        dotAll: true,
      ).firstMatch(chunk);
      final members = RegExp(
        r'<span class="member[^"]*">.*?</i>\s*([\d,]+)\s*</span>',
        dotAll: true,
      ).firstMatch(chunk);
      final parsedType = _malType(type?.group(1));
      works.add(
        MetaWork(
          id: link.group(2)!,
          source: MetaSource.myAnimeList,
          kind: MetaKind.anime,
          title: _decode(title.group(1)!),
          coverUrl: cover == null ? null : _decode(cover.group(1)!),
          score: score == null ? null : double.tryParse(score.group(1)!),
          scoreSource: score == null ? null : 'MyAnimeList',
          votes: members == null ? null : _number(members.group(1)!),
          rank: rank == null ? null : int.tryParse(rank.group(1)!),
          format: parsedType.$1,
          episodes: parsedType.$2,
          siteUrl: _decode(link.group(1)!),
          malId: int.tryParse(link.group(2)!),
        ),
      );
    }
    return works;
  }

  Future<MetaWork> _malDetail(int? id) async {
    if (id == null) throw const MetaException('MyAnimeList id is missing.');
    final response = await _get(
      Uri.parse('$_malEndpoint/anime/$id'),
      timeout: const Duration(seconds: 22),
    );
    final html = _text(response);
    final title = _metaContent(html, 'og:title') ??
        RegExp(r'<title>([^<]+)</title>').firstMatch(html)?.group(1) ??
        'MyAnimeList #$id';
    final description = _metaContent(html, 'og:description') ?? '';
    final cover = RegExp(
          r'<div class="icon-thumb thumbs-zoom" itemprop="image" content="([^"]+)"',
        ).firstMatch(html)?.group(1) ??
        _metaContent(html, 'og:image');
    final score = RegExp(
          r'class="score icon-score[^"]*"[^>]*>.*?</i>\s*([0-9.]+)\s*</span>',
          dotAll: true,
        ).firstMatch(html)?.group(1) ??
        RegExp(r'class="score-label[^"]*">\s*([0-9.]+)')
            .firstMatch(html)
            ?.group(1);
    final rank =
        RegExp(r'Ranked:</span>\s*#(\d+)').firstMatch(html)?.group(1) ??
            RegExp(r'Ranked</span>\s*#(\d+)').firstMatch(html)?.group(1) ??
            RegExp(r'Ranked</td>\s*<td[^>]*>\s*#(\d+)', dotAll: true)
                .firstMatch(html)
                ?.group(1);
    final popularity =
        RegExp(r'Popularity:</span>\s*#(\d+)').firstMatch(html)?.group(1) ??
            RegExp(r'Popularity</td>\s*<td[^>]*>\s*#(\d+)', dotAll: true)
                .firstMatch(html)
                ?.group(1);
    final favourites =
        RegExp(r'Favorites:</span>\s*([\d,]+)').firstMatch(html)?.group(1) ??
            RegExp(r'Favorites</td>\s*<td[^>]*>\s*([\d,]+)', dotAll: true)
                .firstMatch(html)
                ?.group(1);
    final members =
        RegExp(r'Members:</span>\s*([\d,]+)').firstMatch(html)?.group(1) ??
            RegExp(r'\(([\d,]+) users\)').firstMatch(html)?.group(1) ??
            RegExp(r'itemprop="ratingCount"[^>]*>([\d,]+)<')
                .firstMatch(html)
                ?.group(1);
    final type = _malInfo(html, 'Type');
    final episodes = _malInfo(html, 'Episodes');
    final status = _malInfo(html, 'Status');
    final aired = _malInfo(html, 'Aired');
    final premiered = _malInfo(html, 'Premiered');
    final duration = _malInfo(html, 'Duration');
    final source = _malInfo(html, 'Source');
    final rating = _malInfo(html, 'Rating');
    final japanese = RegExp(r'Japanese:</span>\s*([^<]+)')
            .firstMatch(html)
            ?.group(1) ??
        RegExp(r'Japanese</span><br>\s*([^<]+)<br>').firstMatch(html)?.group(1);
    final studios = <String>[];
    final studioBlock = RegExp(
      r'<span class="dark_text">Studios:</span>(.*?)</div>',
      dotAll: true,
    ).firstMatch(html);
    if (studioBlock != null) {
      studios.addAll(
        RegExp(r'title="([^"]+)"')
            .allMatches(studioBlock.group(1)!)
            .map((match) => _decode(match.group(1)!)),
      );
      if (studios.isEmpty) {
        final text = _stripHtml(studioBlock.group(1)!).trim();
        if (text.isNotEmpty) studios.add(text);
      }
    }
    final studioTable = RegExp(
      r'>Studios</td>.*?<span class="studios">(.*?)</span>',
      dotAll: true,
    ).firstMatch(html);
    if (studioTable != null) {
      studios.addAll(
        RegExp(r'<span>([^<]+)</span>')
            .allMatches(studioTable.group(1)!)
            .map((match) => _decode(match.group(1)!)),
      );
    }
    final genres = <String>[];
    for (final match in RegExp(
      r'itemprop="genre" style="display: none">([^<]+)<',
    ).allMatches(html)) {
      final genre = _decode(match.group(1)!);
      if (!genres.contains(genre)) genres.add(genre);
    }
    final year =
        RegExp(r'(\d{4})').firstMatch(premiered ?? aired ?? '')?.group(1);
    final cleanDescription = _stripHtml(description)
        .replaceAll(RegExp(r'\s*\[Written by MAL Rewrite\]\s*$'), '')
        .trim();

    return MetaWork(
      id: '$id',
      source: MetaSource.myAnimeList,
      kind: MetaKind.anime,
      title:
          _decode(title.replaceAll(RegExp(r'\s*-\s*MyAnimeList\.net\s*$'), '')),
      nativeTitle: japanese == null ? null : _decode(japanese.trim()),
      coverUrl: cover,
      synopsis: cleanDescription,
      genres: genres,
      score: score == null ? null : double.tryParse(score),
      scoreSource: score == null ? null : 'MyAnimeList',
      votes: members == null ? null : _number(members),
      rank: rank == null ? null : int.tryParse(rank),
      popularityRank: popularity == null ? null : int.tryParse(popularity),
      favourites: favourites == null ? null : _number(favourites),
      format: type,
      status: status,
      episodes: episodes == null
          ? null
          : int.tryParse(episodes.replaceAll(RegExp(r'[^0-9]'), '')),
      duration: duration,
      year: year == null ? null : int.tryParse(year),
      country: 'JP',
      siteUrl: '$_malEndpoint/anime/$id',
      malId: id,
      studios: studios,
      links: [
        MetaLink(
          label: 'MyAnimeList',
          url: '$_malEndpoint/anime/$id',
          kind: 'official',
        ),
      ],
      tags: [
        if (source != null) MetaTag(name: source),
        if (rating != null) MetaTag(name: rating),
      ],
    );
  }

  String? _malInfo(String html, String label) {
    // Today's page lists facts in `spaceit_pad` divs; older snapshots use a
    // table. Read either, so a MAL rollout cannot blank the detail page.
    final modern = RegExp(
      '<span class="dark_text">$label:</span>(.*?)</div>',
      dotAll: true,
      caseSensitive: false,
    ).firstMatch(html);
    final match = modern ??
        RegExp(
          '>$label</td>\\s*<td[^>]*>(.*?)</td>',
          dotAll: true,
          caseSensitive: false,
        ).firstMatch(html);
    if (match == null) return null;
    final clean = _stripHtml(match.group(1)!);
    return clean.isEmpty ? null : clean;
  }

  (String?, int?) _malType(String? raw) {
    if (raw == null) return (null, null);
    final text = _stripHtml(raw);
    final episodes = RegExp(r'\((\d+)').firstMatch(text)?.group(1) ??
        RegExp(r'(\d+)\s*eps').firstMatch(text)?.group(1);
    final format = text
        .replaceAll(RegExp(r'\(.*'), '')
        .replaceAll(RegExp(r'\d+\s*eps'), '')
        .trim();
    return (
      format.isEmpty ? null : format,
      episodes == null ? null : int.tryParse(episodes)
    );
  }

  // ---------------------------------------------------------------------------
  // hwa.so

  Future<List<MetaWork>> _hwaTop(int limit) async {
    final response = await _get(Uri.parse('$_hwaEndpoint/series?sort=rating'));
    final works =
        _hwaCards(_text(response)).take(limit).toList(growable: false);
    if (works.isEmpty) {
      throw const MetaException('hwa.so returned a page Best could not read.');
    }
    return works;
  }

  Future<List<MetaWork>> _hwaSearch(String query) async {
    final response = await _get(
      Uri.parse('$_hwaEndpoint/search?q=${Uri.encodeQueryComponent(query)}'),
    );
    return _hwaCards(_text(response)).take(14).toList(growable: false);
  }

  List<MetaWork> _hwaCards(String raw) {
    final html = _unescapeJs(raw);
    final parts = html.split('"href":"/series/');
    final works = <MetaWork>[];
    final seen = <String>{};
    for (final part in parts.skip(1)) {
      final slug = part.split('"').first;
      if (slug.isEmpty || slug.contains('?') || !seen.add(slug)) continue;
      final title =
          RegExp(r'"aria-label":"([^"]+)"').firstMatch(part)?.group(1) ??
              RegExp(r'<h3[^>]*title="([^"]+)"').firstMatch(part)?.group(1);
      if (title == null || title.isEmpty) continue;
      final cover =
          RegExp(r'"src":"(/api/media/[^"]+)"').firstMatch(part)?.group(1);
      final score = RegExp(
        r'MangaUpdates rating: ([0-9.]+) out of 10',
      ).firstMatch(part)?.group(1);
      final native = RegExp(
        r'"lang":"ko"[^}]*?"children":"([^"]+)"',
      ).firstMatch(part)?.group(1);
      final status = RegExp(
        r'"data-status":"(\w+)"',
      ).firstMatch(part)?.group(1);
      works.add(
        MetaWork(
          id: slug,
          source: MetaSource.hwa,
          kind: MetaKind.manhwa,
          title: _decode(title),
          nativeTitle: native == null ? null : _decode(native),
          coverUrl: cover == null ? null : '$_hwaEndpoint$cover',
          score: score == null ? null : double.tryParse(score),
          scoreSource: score == null ? null : 'MangaUpdates',
          status: status,
          siteUrl: '$_hwaEndpoint/series/$slug',
          slug: slug,
        ),
      );
    }
    return works;
  }

  Future<MetaWork> _hwaDetail(String slug) async {
    final response = await _get(
      Uri.parse('$_hwaEndpoint/series/$slug'),
      timeout: const Duration(seconds: 22),
    );
    final raw = _text(response);
    final html = _unescapeJs(raw);
    final comic = _jsonLdComic(html);
    if (comic == null) {
      throw const MetaException('hwa.so did not return this series.');
    }

    final title = _string(comic['name']) ?? slug;
    final alternate = _stringList(comic['alternateName']);
    final native = alternate.firstWhere(
      (value) =>
          RegExp(r'[\uAC00-\uD7AF\u3040-\u30FF\u4E00-\u9FFF]').hasMatch(value),
      orElse: () => '',
    );
    final image = _map(comic['image']);
    final description = _string(comic['description']) ?? '';
    final authors = <String>[];
    for (final person
        in _list(comic['author']).whereType<Map<String, dynamic>>()) {
      final name = _string(person['name']);
      if (name != null) authors.add(name);
    }
    final artists = <String>[];
    for (final person
        in _list(comic['contributor']).whereType<Map<String, dynamic>>()) {
      final name = _string(person['name']);
      if (name != null) artists.add(name);
    }
    final publishers = <String>[];
    for (final org
        in _list(comic['publisher']).whereType<Map<String, dynamic>>()) {
      final name = _string(org['name']);
      if (name != null) publishers.add(name);
    }

    final score = RegExp(
          r'MangaUpdates score ([0-9.]+) out of 10',
        ).firstMatch(html)?.group(1) ??
        RegExp(r'MangaUpdates rating: ([0-9.]+) out of 10')
            .firstMatch(html)
            ?.group(1);
    final votes = RegExp(r'([\d.]+)k votes').firstMatch(html)?.group(1);
    final exactVotes = RegExp(r'([\d,]+) votes').firstMatch(html)?.group(1);
    final status = RegExp(r'"data-status":"(\w+)"').firstMatch(html)?.group(1);
    final chapters = RegExp(r'Chapters\s*(\d+)').firstMatch(html)?.group(1);
    final date = _string(comic['datePublished']);
    final links = <MetaLink>[];
    for (final url in _stringList(comic['sameAs'])) {
      final label = _readingPlatform(url);
      if (label != null) {
        links.add(MetaLink(label: label, url: url, kind: 'official'));
      }
    }

    return MetaWork(
      id: slug,
      source: MetaSource.hwa,
      kind: MetaKind.manhwa,
      title: title,
      nativeTitle: native.isEmpty ? null : native,
      coverUrl: image['url'] is String ? image['url'] as String : null,
      bannerUrl: image['url'] is String ? image['url'] as String : null,
      synopsis: _decode(description),
      genres: _stringList(comic['genre']),
      score: score == null ? null : double.tryParse(score),
      scoreSource: score == null ? null : 'MangaUpdates',
      votes: exactVotes != null
          ? _number(exactVotes)
          : votes == null
              ? null
              : (double.parse(votes) * 1000).round(),
      status: status,
      chapters: chapters == null ? null : int.tryParse(chapters),
      year: date != null && date.length >= 4
          ? int.tryParse(date.substring(0, 4))
          : null,
      country: _string(comic['inLanguage']) == 'ko' ? 'KR' : null,
      siteUrl: '$_hwaEndpoint/series/$slug',
      slug: slug,
      authors: authors,
      artists: artists,
      publishers: publishers,
      links: links,
      tags: [
        for (final publisher in publishers.take(3)) MetaTag(name: publisher),
      ],
    );
  }

  Map<String, dynamic>? _jsonLdComic(String html) {
    final marker = html.indexOf('"@type":"ComicSeries"');
    if (marker < 0) return null;
    var start = html.lastIndexOf('{"@context"', marker);
    if (start < 0) return null;
    while (start >= 0) {
      final end = _balancedObjectEnd(html, start);
      if (end > start) {
        try {
          final decoded = jsonDecode(html.substring(start, end));
          if (decoded is Map<String, dynamic>) {
            final graph = decoded['@graph'];
            if (graph is List) {
              for (final node in graph.whereType<Map<String, dynamic>>()) {
                if (node['@type'] == 'ComicSeries') return node;
              }
            }
            if (decoded['@type'] == 'ComicSeries') return decoded;
          }
        } on FormatException {
          // Try an earlier JSON-LD block.
        }
      }
      start = html.lastIndexOf('{"@context"', start - 1);
    }
    return null;
  }

  int _balancedObjectEnd(String text, int start) {
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = start; i < text.length; i++) {
      final char = text[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (char == r'\') {
          escaped = true;
        } else if (char == '"') {
          inString = false;
        }
        continue;
      }
      if (char == '"') {
        inString = true;
      } else if (char == '{') {
        depth++;
      } else if (char == '}') {
        depth--;
        if (depth == 0) return i + 1;
      }
    }
    return -1;
  }

  String? _readingPlatform(String url) {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    const platforms = <String, String>{
      'tapas.io': 'Tapas',
      'manta.net': 'Manta',
      'tappytoon.com': 'Tappytoon',
      'webtoons.com': 'WEBTOON',
      'lezhin.com': 'Lezhin',
      'lezhinfr.com': 'Lezhin',
      'mangaplaza.com': 'MangaPlaza',
      'yenpress.com': 'Yen Press',
      'kodansha.us': 'Kodansha',
      'viz.com': 'VIZ',
      'webcomicsapp.com': 'Webcomics',
      'kakaopage.com': 'KakaoPage',
      'page.kakao.com': 'KakaoPage',
      'webtoon.kakao.com': 'Kakao Webtoon',
      'comikey.com': 'Comikey',
      'mangamirai.com': 'Manga Mirai',
      'pocketcomics.com': 'Pocket Comics',
    };
    for (final entry in platforms.entries) {
      if (host == entry.key || host.endsWith('.${entry.key}')) {
        return entry.value;
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Anime Corner

  Future<List<MetaNews>> _animeCornerNews(int limit) async {
    final response = await _get(Uri.parse(_animeCornerFeed));
    final xml = _text(response);
    final items = <MetaNews>[];
    for (final match
        in RegExp(r'<item>(.*?)</item>', dotAll: true).allMatches(xml)) {
      final item = match.group(1)!;
      final title = _xmlTag(item, 'title');
      final link = _xmlTag(item, 'link');
      if (title == null || link == null) continue;
      final creator = RegExp(
        r'<dc:creator><!\[CDATA\[(.*?)\]\]></dc:creator>',
        dotAll: true,
      ).firstMatch(item)?.group(1);
      final category = RegExp(
        r'<category><!\[CDATA\[(.*?)\]\]></category>',
        dotAll: true,
      ).firstMatch(item)?.group(1);
      final description = RegExp(
        r'<description><!\[CDATA\[(.*?)\]\]></description>',
        dotAll: true,
      ).firstMatch(item)?.group(1);
      final published =
          RegExp(r'<pubDate>(.*?)</pubDate>').firstMatch(item)?.group(1);
      items.add(
        MetaNews(
          title: _decode(title),
          url: _decode(link),
          summary: description == null ? '' : _stripHtml(description),
          category: category == null ? null : _decode(category),
          author: creator == null ? null : _decode(creator),
          publishedAt: published == null ? null : _parseRfc822(published),
        ),
      );
      if (items.length >= limit) break;
    }

    // The feed carries no image. The article's own Open Graph image is the
    // honest thumbnail; if an article does not answer, the card keeps its
    // typographic fallback instead of borrowing another story's art.
    return Future.wait(
      items.map((item) async {
        try {
          final page = await _get(
            Uri.parse(item.url),
            timeout: const Duration(seconds: 9),
          );
          final html = _text(page);
          return MetaNews(
            title: item.title,
            url: item.url,
            summary: _metaContent(html, 'og:description') ?? item.summary,
            imageUrl: _metaContent(html, 'og:image'),
            category: item.category,
            author: item.author,
            publishedAt: item.publishedAt,
          );
        } catch (_) {
          return item;
        }
      }),
    );
  }

  String? _xmlTag(String xml, String tag) {
    final match = RegExp('<$tag>(.*?)</$tag>', dotAll: true).firstMatch(xml);
    if (match == null) return null;
    return match
        .group(1)!
        .replaceAll(RegExp(r'^<!\[CDATA\['), '')
        .replaceAll(RegExp(r'\]\]>$'), '');
  }

  DateTime? _parseRfc822(String raw) {
    final match = RegExp(
      r'(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})\s+(\d{2}):(\d{2}):(\d{2})',
    ).firstMatch(raw);
    if (match == null) return null;
    const months = {
      'Jan': 1,
      'Feb': 2,
      'Mar': 3,
      'Apr': 4,
      'May': 5,
      'Jun': 6,
      'Jul': 7,
      'Aug': 8,
      'Sep': 9,
      'Oct': 10,
      'Nov': 11,
      'Dec': 12,
    };
    final month = months[match.group(2)];
    if (month == null) return null;
    return DateTime.utc(
      int.parse(match.group(3)!),
      month,
      int.parse(match.group(1)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      int.parse(match.group(6)!),
    );
  }

  // ---------------------------------------------------------------------------
  // Search

  Future<MetaSearchResults> _loadSearch(String query) async {
    final failures = <MetaSource, String>{};

    Future<List<MetaWork>> guard(
      MetaSource source,
      Future<List<MetaWork>> future,
    ) async {
      try {
        return await future;
      } catch (error) {
        failures[source] = _message(error);
        return const <MetaWork>[];
      }
    }

    final results = await Future.wait<List<MetaWork>>([
      guard(MetaSource.anilist, _anilistSearch(query)),
      guard(MetaSource.myAnimeList, _malSearch(query)),
      guard(MetaSource.hwa, _hwaSearch(query)),
    ]);
    final anilist = results[0];
    final mal = results[1];
    final hwa = results[2];

    final malIds = anilist.map((work) => work.malId).whereType<int>().toSet();
    final titles = anilist.map((work) => _normalise(work.title)).toSet();
    final anime = <MetaWork>[...anilist];
    for (final work in mal) {
      if (work.malId != null && malIds.contains(work.malId)) continue;
      if (titles.contains(_normalise(work.title))) continue;
      anime.add(work);
    }

    return MetaSearchResults(
      query: query,
      anime: anime,
      manhwa: hwa,
      failures: Map.unmodifiable(failures),
    );
  }

  // ---------------------------------------------------------------------------
  // HTTP + parsing

  Future<Map<String, dynamic>> _anilist(
    String query, {
    Map<String, dynamic>? variables,
  }) async {
    final response = await _client
        .post(
          Uri.parse(_anilistEndpoint),
          headers: {
            ..._headers,
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'query': query, 'variables': variables ?? {}}),
        )
        .timeout(const Duration(seconds: 18));
    if (response.statusCode == 429) {
      throw const MetaException('AniList rate limit reached.');
    }
    if (response.statusCode != 200) {
      throw MetaException('AniList returned HTTP ${response.statusCode}.');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const MetaException('AniList returned an unexpected response.');
    }
    final errors = decoded['errors'];
    if (errors is List && errors.isNotEmpty) {
      final first = errors.first;
      final message = first is Map ? first['message'] : null;
      throw MetaException(
          message is String ? message : 'AniList rejected the query.');
    }
    final data = decoded['data'];
    if (data is! Map<String, dynamic>) {
      throw const MetaException('AniList returned no data.');
    }
    return data;
  }

  Future<http.Response> _get(
    Uri uri, {
    Duration timeout = const Duration(seconds: 18),
  }) async {
    final response = await _client.get(uri, headers: _headers).timeout(timeout);
    if (response.statusCode != 200) {
      throw MetaException('${uri.host} returned HTTP ${response.statusCode}.');
    }
    return response;
  }

  Future<T> _cached<T>(
    String key,
    Duration ttl,
    Future<T> Function() load, {
    int generation = 0,
  }) {
    final now = DateTime.now();
    final existing = _cache[key];
    if (existing != null &&
        existing.expires.isAfter(now) &&
        existing.generation >= generation) {
      return existing.value.then((value) => value as T);
    }
    final future = load().catchError((Object error, StackTrace stack) {
      _cache.remove(key);
      Error.throwWithStackTrace(error, stack);
    });
    _cache[key] = _CacheEntry(future, now.add(ttl), generation);
    return future;
  }

  String _text(http.Response response) => utf8.decode(response.bodyBytes);

  String _message(Object error) {
    if (error is MetaException) return error.message;
    if (error is TimeoutException) return 'Request timed out.';
    return 'The source did not answer.';
  }

  String? _metaContent(String html, String key) {
    for (final match
        in RegExp(r'<meta\b[^>]*>', caseSensitive: false).allMatches(html)) {
      final tag = match.group(0)!;
      if (!tag.contains('"$key"') && !tag.contains("'$key'")) continue;
      final content = RegExp(
        r'''content=(?:"([^"]*)"|'([^']*)')''',
        caseSensitive: false,
      ).firstMatch(tag);
      if (content != null) {
        return _decode(content.group(1) ?? content.group(2) ?? '');
      }
    }
    return null;
  }

  String _unescapeJs(String input) {
    final out = StringBuffer();
    for (var i = 0; i < input.length; i++) {
      final char = input[i];
      if (char != r'\' || i + 1 >= input.length) {
        out.write(char);
        continue;
      }
      final next = input[++i];
      switch (next) {
        case '"':
          out.write('"');
          break;
        case r'\':
          out.write(r'\');
          break;
        case '/':
          out.write('/');
          break;
        case 'n':
          out.write('\n');
          break;
        case 'r':
          out.write('\r');
          break;
        case 't':
          out.write('\t');
          break;
        case 'u':
          if (i + 4 < input.length) {
            final code = int.tryParse(input.substring(i + 1, i + 5), radix: 16);
            if (code != null) {
              out.writeCharCode(code);
              i += 4;
              break;
            }
          }
          out.write(next);
          break;
        default:
          out.write(next);
      }
    }
    return out.toString();
  }

  String _stripHtml(String input) {
    final withBreaks = input.replaceAll(
      RegExp(r'<br\s*/?>', caseSensitive: false),
      '\n',
    );
    final withoutTags = withBreaks.replaceAll(RegExp(r'<[^>]+>'), ' ');
    return _decode(withoutTags)
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n\s*\n+'), '\n\n')
        .trim();
  }

  String _decode(String input) {
    var value = input;
    value = value.replaceAllMapped(
      RegExp(r'&#x([0-9a-fA-F]+);'),
      (match) => String.fromCharCode(int.parse(match.group(1)!, radix: 16)),
    );
    value = value.replaceAllMapped(
      RegExp(r'&#(\d+);'),
      (match) => String.fromCharCode(int.parse(match.group(1)!)),
    );
    return value
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&nbsp;', ' ');
  }

  Map<String, dynamic> _map(Object? value) =>
      value is Map<String, dynamic> ? value : const <String, dynamic>{};

  List<Object?> _list(Object? value) =>
      value is List ? value : const <Object?>[];

  List<String> _stringList(Object? value) {
    if (value is! List) return const <String>[];
    return value.whereType<String>().map(_decode).toList(growable: false);
  }

  String? _string(Object? value) {
    if (value is String && value.trim().isNotEmpty) return value;
    return null;
  }

  int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value);
    return null;
  }

  String? _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      if (value != null && value.trim().isNotEmpty) return value;
    }
    return null;
  }

  int _number(String raw) =>
      int.tryParse(raw.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  String _normalise(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06FF]+'), ' ')
      .trim();
}
