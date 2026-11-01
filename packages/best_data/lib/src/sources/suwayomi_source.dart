import 'dart:convert';

import 'package:best_domain/best_domain.dart';
import 'package:http/http.dart' as http;

/// Raised when a Suwayomi server answers with something the adapter cannot use.
class SuwayomiException implements Exception {
  const SuwayomiException(this.message);

  final String message;

  @override
  String toString() => 'SuwayomiException: $message';
}

/// One source the server hosts, as `/api/v1/source/list` describes it.
class SuwayomiSourceInfo {
  const SuwayomiSourceInfo({
    required this.id,
    required this.name,
    required this.language,
    required this.supportsLatest,
    required this.nsfw,
    this.iconUrl,
  });

  final String id;
  final String name;
  final String language;
  final bool supportsLatest;
  final bool nsfw;
  final String? iconUrl;
}

/// A thin REST client for Suwayomi (the Tachidesk server).
///
/// The server runs the same extension APKs that Mihon, Komikku and Aniyomi
/// load, and its maintainers keep those extensions current. Best never bundles
/// an extension and never scrapes a site: it asks a server the reader runs for
/// the catalogue that server already has.
class SuwayomiClient {
  SuwayomiClient({
    required this.baseUrl,
    required http.Client client,
    this.headers = const {},
  })  : _client = client,
        _base = _parseBase(baseUrl);

  final String baseUrl;
  final http.Client _client;

  /// Sent with every request, for a server behind a reverse proxy.
  final Map<String, String> headers;

  final Uri _base;

  static Uri _parseBase(String raw) {
    final trimmed = raw.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasAuthority || uri.host.isEmpty) {
      throw const SuwayomiException('The server address is not a URL.');
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw const SuwayomiException('The server address must be http or https.');
    }
    return uri;
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final prefix = _base.path.endsWith('/')
        ? _base.path.substring(0, _base.path.length - 1)
        : _base.path;
    return _base.replace(path: '$prefix/api/v1$path', queryParameters: query);
  }

  Map<String, String> get _requestHeaders => {
        'Accept': 'application/json',
        ...headers,
      };

  Future<Object?> _get(Uri uri) async {
    final response = await _client
        .get(uri, headers: _requestHeaders)
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      throw SuwayomiException('HTTP ${response.statusCode} for ${uri.path}');
    }
    if (response.body.isEmpty) return null;
    try {
      return jsonDecode(response.body);
    } on FormatException {
      throw const SuwayomiException('The server did not answer with JSON.');
    }
  }

  Future<List<SuwayomiSourceInfo>> sources() async {
    final json = await _get(_uri('/source/list'));
    if (json is! List) {
      throw const SuwayomiException('The source list is not an array.');
    }
    return [
      for (final entry in json.whereType<Map<String, dynamic>>())
        if (entry['id'] is String && entry['name'] is String)
          SuwayomiSourceInfo(
            id: entry['id'] as String,
            name: (entry['displayName'] ?? entry['name']) as String,
            language: '${entry['lang'] ?? 'all'}',
            supportsLatest: entry['supportsLatest'] == true,
            nsfw: entry['isNsfw'] == true,
            iconUrl: _absolute(entry['iconUrl']),
          ),
    ];
  }

  Future<List<Media>> popular(String sourceId, {int page = 1}) async {
    final json = await _get(_uri('/source/$sourceId/popular/$page'));
    return _list(json, sourceId);
  }

  Future<List<Media>> search(
    String sourceId,
    String query, {
    int page = 1,
  }) async {
    final json = await _get(
      _uri('/source/$sourceId/search', {
        'searchTerm': query,
        'pageNum': '$page',
      }),
    );
    return _list(json, sourceId);
  }

  Future<List<Media>> latest(String sourceId, {int page = 1}) async {
    final json = await _get(_uri('/source/$sourceId/latest/$page'));
    return _list(json, sourceId);
  }

  Future<Media> manga(int id, String sourceId) async {
    final json = await _get(_uri('/manga/$id/full'));
    if (json is! Map<String, dynamic>) {
      throw const SuwayomiException('The work response is not an object.');
    }
    return _media(json, sourceId);
  }

  Future<List<MediaUnit>> chapters(Media media) async {
    final mangaId = int.tryParse(media.ref.url) ?? 0;
    final json = await _get(_uri('/manga/$mangaId/chapters'));
    if (json is! List) {
      throw const SuwayomiException('The chapter list is not an array.');
    }
    final units = <MediaUnit>[];
    for (final entry in json.whereType<Map<String, dynamic>>()) {
      final index = entry['index'];
      final number = entry['chapterNumber'];
      if (index is! int) continue;
      units.add(
        MediaUnit(
          mediaId: media.id,
          // The page endpoint needs both ids, so the unit URL carries them.
          url: '$mangaId/$index',
          number: number is num ? number.toDouble() : index.toDouble(),
          title: (entry['name'] as String?)?.trim().isNotEmpty == true
              ? (entry['name'] as String).trim()
              : 'Chapter $index',
          kind: UnitKind.chapter,
          publishedAt: _epoch(entry['uploadDate']),
          // -1 means the server has not fetched the pages yet; Best treats
          // that as unknown rather than a negative count.
          pageCount: (entry['pageCount'] is int && (entry['pageCount'] as int) > 0)
              ? entry['pageCount'] as int
              : 0,
        ),
      );
    }
    units.sort((a, b) => a.number.compareTo(b.number));
    return units;
  }

  Future<List<MediaResource>> pages(int mangaId, int chapterIndex) async {
    // This call also makes the server fetch the pages, so pageCount is set.
    final json = await _get(_uri('/manga/$mangaId/chapter/$chapterIndex'));
    if (json is! Map<String, dynamic>) {
      throw const SuwayomiException('The chapter response is not an object.');
    }
    final count = json['pageCount'];
    if (count is! int || count <= 0) {
      throw const SuwayomiException('The server reported no pages.');
    }
    return [
      for (var index = 0; index < count; index++)
        ImageResource(
          _uri('/manga/$mangaId/chapter/$chapterIndex/page/$index').toString(),
          headers: headers,
        ),
    ];
  }

  List<Media> _list(Object? json, String sourceId) {
    final raw = json is Map<String, dynamic> ? json['mangaList'] : json;
    if (raw is! List) {
      throw const SuwayomiException('The catalogue response has no list.');
    }
    return [
      for (final entry in raw.whereType<Map<String, dynamic>>())
        _media(entry, sourceId),
    ];
  }

  Media _media(Map<String, dynamic> json, String sourceId) {
    final id = json['id'];
    if (id is! int) {
      throw const SuwayomiException('A work is missing its id.');
    }
    final genres = json['genre'];
    return Media(
      ref: SourceRef('suwayomi:$sourceId', '$id'),
      title: (json['title'] as String?)?.trim().isNotEmpty == true
          ? (json['title'] as String).trim()
          : 'Untitled',
      kind: MediaKind.manga,
      coverUrl: _absolute(json['thumbnailUrl']),
      synopsis: (json['description'] as String?)?.trim(),
      author: (json['author'] as String?)?.trim(),
      status: _status(json['status']),
      genres: genres is List
          ? List.unmodifiable(genres.whereType<String>().take(8))
          : const [],
    );
  }

  String? _absolute(Object? raw) {
    if (raw is! String) return null;
    final value = raw.trim();
    if (value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri == null) return null;
    if (uri.hasScheme) return value;
    return _base.resolve(value).toString();
  }

  int _epoch(Object? raw) {
    if (raw is! num) return 0;
    // Suwayomi sends seconds; Best stores milliseconds.
    return raw > 100000000000 ? raw.toInt() : raw.toInt() * 1000;
  }

  MediaStatus _status(Object? raw) => switch ('$raw') {
        'ONGOING' => MediaStatus.ongoing,
        'COMPLETED' || 'PUBLISHING_FINISHED' => MediaStatus.completed,
        'ON_HIATUS' => MediaStatus.hiatus,
        'CANCELLED' => MediaStatus.cancelled,
        _ => MediaStatus.unknown,
      };
}

/// One server source exposed as a Best adapter.
class SuwayomiSource implements SourceAdapter {
  SuwayomiSource({required this.client, required this.info});

  final SuwayomiClient client;
  final SuwayomiSourceInfo info;

  @override
  String get id => 'suwayomi:${info.id}';

  @override
  String get name => info.name;

  @override
  String get language => info.language;

  @override
  Future<List<Media>> popular({int page = 1}) =>
      client.popular(info.id, page: page);

  @override
  Future<List<Media>> search(String query, {int page = 1}) =>
      client.search(info.id, query, page: page);

  @override
  Future<Media> details(Media media) =>
      client.manga(int.tryParse(media.ref.url) ?? 0, info.id);

  @override
  Future<List<MediaUnit>> units(Media media) => client.chapters(media);

  @override
  Future<List<MediaResource>> resources(MediaUnit unit) {
    final parts = unit.url.split('/');
    return client.pages(
      int.tryParse(parts.first) ?? 0,
      int.tryParse(parts.last) ?? 0,
    );
  }
}
