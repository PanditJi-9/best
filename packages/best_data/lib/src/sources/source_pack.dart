import 'dart:async';
import 'dart:convert';

import 'package:best_domain/best_domain.dart';
import 'package:http/http.dart' as http;

/// A source pack is a declarative description of a JSON catalogue: five routes
/// and three field maps. No code is executed, so installing one cannot read the
/// library, the filesystem or the network beyond the host it names.
///
/// This is the first compatibility tier. HikariManga and Mihon ship scripted
/// sources; a script host needs a sandbox and a review pipeline before it can be
/// safe to load, so the app starts with a format that can be validated in full.
class SourcePackException implements Exception {
  SourcePackException(this.message);

  final String message;

  @override
  String toString() => message;
}

final RegExp _packIdPattern = RegExp(r'^[a-z0-9][a-z0-9._-]{1,39}$');

/// Upper bound on a pack document. A pack is a manifest, not a database.
const int kMaxSourcePackBytes = 48 * 1024;

/// Upper bound on a catalogue response. A source that streams more than this is
/// paginating badly and should be fixed at the source, not buffered on a phone.
const int kMaxSourceResponseBytes = 8 * 1024 * 1024;

class MediaMapping {
  const MediaMapping({
    required this.list,
    required this.id,
    required this.title,
    this.nativeTitle,
    this.cover,
    this.synopsis,
    this.author,
    this.status,
    this.genres,
    this.kind,
  });

  final String list;
  final String id;
  final String title;
  final String? nativeTitle;
  final String? cover;
  final String? synopsis;
  final String? author;
  final String? status;
  final String? genres;
  final String? kind;
}

class UnitMapping {
  const UnitMapping({
    required this.list,
    required this.id,
    this.number,
    this.title,
    this.date,
    this.pages,
  });

  final String list;
  final String id;
  final String? number;
  final String? title;
  final String? date;
  final String? pages;
}

class PageMapping {
  const PageMapping({required this.list, required this.url});

  final String list;
  final String url;
}

class SourcePack {
  SourcePack({
    required this.id,
    required this.name,
    required this.language,
    required this.baseUrl,
    required this.popular,
    required this.search,
    required this.chapters,
    required this.pages,
    required this.media,
    required this.units,
    required this.page,
    this.details,
    this.defaultKind = MediaKind.manga,
    this.defaultUnitKind = UnitKind.chapter,
    this.headers = const {},
    this.iconUrl,
  });

  final String id;
  final String name;

  /// BCP-47 tag such as `ar` or `en`, or `all`.
  final String language;
  final String baseUrl;

  /// Route templates. `{page}`, `{query}` and `{id}` are substituted; `{id}` is
  /// the source's own key for a work, never a display title.
  final String popular;
  final String search;
  final String? details;
  final String chapters;
  final String pages;

  final MediaMapping media;
  final UnitMapping units;
  final PageMapping page;

  final MediaKind defaultKind;
  final UnitKind defaultUnitKind;

  /// Sent with every request and every image load (referer, accept-language).
  final Map<String, String> headers;
  final String? iconUrl;

  Uri resolve(String template, [Map<String, String> variables = const {}]) {
    var path = template;
    for (final entry in variables.entries) {
      final encoded = entry.key == 'query'
          ? Uri.encodeQueryComponent(entry.value)
          : Uri.encodeComponent(entry.value);
      path = path.replaceAll('{${entry.key}}', encoded);
    }
    if (path.contains('{')) {
      throw SourcePackException('Unfilled placeholder in route: $path');
    }
    return Uri.parse(baseUrl).resolve(path);
  }

  static SourcePack parse(String raw) {
    if (raw.trim().isEmpty) {
      throw SourcePackException('The pack is empty.');
    }
    if (raw.length > kMaxSourcePackBytes) {
      throw SourcePackException('The pack is larger than 48 KB.');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw SourcePackException('The pack is not valid JSON.');
    }
    if (decoded is! Map<String, Object?>) {
      throw SourcePackException('The pack must be a JSON object.');
    }
    return SourcePack.fromJson(decoded);
  }

  factory SourcePack.fromJson(Map<String, Object?> json) {
    final id = _string(json, 'id').trim();
    if (!_packIdPattern.hasMatch(id)) {
      throw SourcePackException(
        'The id must be 2-40 lowercase letters, digits, dots, dashes or '
        'underscores.',
      );
    }
    final name = _string(json, 'name').trim();
    if (name.isEmpty) {
      throw SourcePackException('The name cannot be empty.');
    }
    final language = _optionalString(json, 'language')?.trim() ?? 'all';
    final baseUrl = _string(json, 'baseUrl').trim();
    final base = Uri.tryParse(baseUrl);
    if (base == null || !base.hasAuthority) {
      throw SourcePackException('baseUrl must be an absolute URL.');
    }
    final loopback = base.host == 'localhost' || base.host == '127.0.0.1';
    if (base.scheme != 'https' && !(base.scheme == 'http' && loopback)) {
      throw SourcePackException('baseUrl must use https.');
    }

    final routes = _object(json, 'routes');
    final search = _string(routes, 'search');
    if (!search.contains('{query}')) {
      throw SourcePackException('routes.search must contain {query}.');
    }
    final popular = _string(routes, 'popular');
    if (!popular.contains('{page}')) {
      throw SourcePackException('routes.popular must contain {page}.');
    }

    final map = _object(json, 'map');
    final mediaMap = _object(map, 'media');
    final unitMap = _object(map, 'unit');
    final pageMap = _object(map, 'page');

    final headers = <String, String>{};
    final rawHeaders = json['headers'];
    if (rawHeaders != null) {
      if (rawHeaders is! Map<String, Object?>) {
        throw SourcePackException('headers must be an object.');
      }
      for (final entry in rawHeaders.entries) {
        final value = entry.value;
        if (value is! String) {
          throw SourcePackException('Header "${entry.key}" must be a string.');
        }
        if (value.length > 512) {
          throw SourcePackException('Header "${entry.key}" is too long.');
        }
        headers[entry.key] = value;
      }
    }

    return SourcePack(
      id: id,
      name: name,
      language: language,
      baseUrl: baseUrl,
      popular: popular,
      search: search,
      details: _optionalString(routes, 'details'),
      chapters: _string(routes, 'chapters'),
      pages: _string(routes, 'pages'),
      media: MediaMapping(
        list: _string(mediaMap, 'list'),
        id: _string(mediaMap, 'id'),
        title: _string(mediaMap, 'title'),
        nativeTitle: _optionalString(mediaMap, 'nativeTitle'),
        cover: _optionalString(mediaMap, 'cover'),
        synopsis: _optionalString(mediaMap, 'synopsis'),
        author: _optionalString(mediaMap, 'author'),
        status: _optionalString(mediaMap, 'status'),
        genres: _optionalString(mediaMap, 'genres'),
        kind: _optionalString(mediaMap, 'kind'),
      ),
      units: UnitMapping(
        list: _string(unitMap, 'list'),
        id: _string(unitMap, 'id'),
        number: _optionalString(unitMap, 'number'),
        title: _optionalString(unitMap, 'title'),
        date: _optionalString(unitMap, 'date'),
        pages: _optionalString(unitMap, 'pages'),
      ),
      page: PageMapping(
        list: _string(pageMap, 'list'),
        url: _string(pageMap, 'url'),
      ),
      defaultKind: _kindOf(
        _optionalString(json, 'kind'),
        fallback: MediaKind.manga,
      ),
      defaultUnitKind: _unitKindOf(
        _optionalString(json, 'unitKind'),
        fallback: UnitKind.chapter,
      ),
      headers: Map.unmodifiable(headers),
      iconUrl: _optionalString(json, 'iconUrl'),
    );
  }

  static String _string(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is! String || value.trim().isEmpty) {
      throw SourcePackException('Missing "$key".');
    }
    return value;
  }

  static String? _optionalString(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value == null) return null;
    if (value is! String) {
      throw SourcePackException('"$key" must be a string.');
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static Map<String, Object?> _object(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is! Map<String, Object?>) {
      throw SourcePackException('Missing "$key" object.');
    }
    return value;
  }
}

MediaKind _kindOf(String? raw, {required MediaKind fallback}) {
  return switch (raw?.toLowerCase()) {
    'manga' => MediaKind.manga,
    'manhwa' => MediaKind.manhwa,
    'manhua' => MediaKind.manhua,
    'webtoon' => MediaKind.webtoon,
    'anime' => MediaKind.anime,
    'drama' => MediaKind.drama,
    'film' || 'movie' => MediaKind.film,
    _ => fallback,
  };
}

UnitKind _unitKindOf(String? raw, {required UnitKind fallback}) {
  return switch (raw?.toLowerCase()) {
    'chapter' => UnitKind.chapter,
    'episode' => UnitKind.episode,
    _ => fallback,
  };
}

MediaStatus _statusOf(String? raw) {
  return switch (raw?.toLowerCase()) {
    'ongoing' || 'airing' => MediaStatus.ongoing,
    'completed' || 'finished' => MediaStatus.completed,
    'hiatus' => MediaStatus.hiatus,
    'cancelled' || 'canceled' => MediaStatus.cancelled,
    _ => MediaStatus.unknown,
  };
}

Object? _valueAt(Object? root, String path) {
  if (path.isEmpty) return root;
  Object? current = root;
  for (final segment in path.split('.')) {
    if (current is Map<String, Object?>) {
      current = current[segment];
    } else if (current is List<Object?>) {
      final index = int.tryParse(segment);
      if (index == null || index < 0 || index >= current.length) return null;
      current = current[index];
    } else {
      return null;
    }
  }
  return current;
}

String? _stringAt(Object? root, String? path) {
  if (path == null) return null;
  final value = _valueAt(root, path);
  if (value == null) return null;
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  if (value is num || value is bool) return value.toString();
  return null;
}

double? _doubleAt(Object? root, String? path) {
  final value = _valueAt(root, path ?? '');
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}

int? _intAt(Object? root, String? path) {
  final value = _valueAt(root, path ?? '');
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

List<Object?> _listAt(Object? root, String path) {
  final value = _valueAt(root, path);
  if (value is List<Object?>) return value;
  if (value is Map<String, Object?>) return [value];
  throw SourcePackException('Expected a list at "$path".');
}

/// The runtime half: turns a validated pack into the same [SourceAdapter] the
/// built-in catalogues implement, so every screen already works with it.
class JsonSourceAdapter implements SourceAdapter {
  JsonSourceAdapter({
    required this.pack,
    required http.Client client,
    this.timeout = const Duration(seconds: 20),
  }) : _client = client;

  final SourcePack pack;
  final http.Client _client;
  final Duration timeout;

  @override
  String get id => pack.id;

  @override
  String get name => pack.name;

  @override
  String get language => pack.language;

  Map<String, String> get _headers => {
        'accept': 'application/json',
        ...pack.headers,
      };

  Future<Object?> _get(
    String template, [
    Map<String, String> variables = const {},
  ]) async {
    final uri = pack.resolve(template, variables);
    final response = await _client.get(uri, headers: _headers).timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SourcePackException(
        '${pack.name} returned HTTP ${response.statusCode}.',
      );
    }
    if (response.bodyBytes.length > kMaxSourceResponseBytes) {
      throw SourcePackException('${pack.name} returned an oversized response.');
    }
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw SourcePackException('${pack.name} returned invalid JSON.');
    }
  }

  Future<List<Media>> _mediaList(
    String template,
    Map<String, String> variables,
  ) async {
    final root = await _get(template, variables);
    final items = _listAt(root, pack.media.list);
    return [
      for (final item in items.take(120))
        if (_toMedia(item) case final media?) media,
    ];
  }

  Media? _toMedia(Object? item) {
    final url = _stringAt(item, pack.media.id);
    final title = _stringAt(item, pack.media.title);
    if (url == null || title == null) return null;
    final cover = _stringAt(item, pack.media.cover);
    final genres = <String>[];
    final rawGenres = _valueAt(item, pack.media.genres ?? '');
    if (rawGenres is List<Object?>) {
      for (final genre in rawGenres) {
        if (genre is String && genre.trim().isNotEmpty) {
          genres.add(genre.trim());
        }
      }
    }
    return Media(
      ref: SourceRef(pack.id, url),
      title: title,
      kind: _kindOf(
        _stringAt(item, pack.media.kind),
        fallback: pack.defaultKind,
      ),
      nativeTitle: _stringAt(item, pack.media.nativeTitle),
      coverUrl: _absolute(cover),
      synopsis: _stringAt(item, pack.media.synopsis),
      author: _stringAt(item, pack.media.author),
      status: _statusOf(_stringAt(item, pack.media.status)),
      genres: genres,
    );
  }

  String? _absolute(String? url) {
    if (url == null) return null;
    final parsed = Uri.tryParse(url);
    if (parsed == null) return null;
    if (parsed.hasScheme) return url;
    return Uri.parse(pack.baseUrl).resolve(url).toString();
  }

  @override
  Future<List<Media>> popular({int page = 1}) =>
      _mediaList(pack.popular, {'page': '$page'});

  @override
  Future<List<Media>> search(String query, {int page = 1}) =>
      _mediaList(pack.search, {'query': query, 'page': '$page'});

  @override
  Future<Media> details(Media media) async {
    final route = pack.details;
    if (route == null) return media;
    final root = await _get(route, {'id': media.ref.url});
    final mapped = _toMedia(root);
    if (mapped == null) return media;
    // Library state belongs to the repository, never to the catalogue.
    return mapped.copyWith(
      inLibrary: media.inLibrary,
      favorite: media.favorite,
      addedAt: media.addedAt,
      lastOpenedAt: media.lastOpenedAt,
    );
  }

  @override
  Future<List<MediaUnit>> units(Media media) async {
    final root = await _get(pack.chapters, {'id': media.ref.url});
    final items = _listAt(root, pack.units.list);
    final result = <MediaUnit>[];
    for (var index = 0; index < items.length && index < 2000; index++) {
      final item = items[index];
      final url = _stringAt(item, pack.units.id);
      if (url == null) continue;
      final number =
          _doubleAt(item, pack.units.number) ?? (index + 1).toDouble();
      final published = DateTime.tryParse(
        _stringAt(item, pack.units.date) ?? '',
      );
      result.add(
        MediaUnit(
          mediaId: media.id,
          url: url,
          number: number,
          title: _stringAt(item, pack.units.title) ?? '',
          kind: pack.defaultUnitKind,
          publishedAt: published?.millisecondsSinceEpoch ?? 0,
          pageCount: _intAt(item, pack.units.pages) ?? 0,
        ),
      );
    }
    return result;
  }

  @override
  Future<List<MediaResource>> resources(MediaUnit unit) async {
    final root = await _get(pack.pages, {'id': unit.url});
    final items = _listAt(root, pack.page.list);
    final result = <MediaResource>[];
    for (final item in items.take(2000)) {
      final raw = item is String ? item : _stringAt(item, pack.page.url);
      final url = _absolute(raw);
      if (url == null) continue;
      result.add(ImageResource(url, headers: pack.headers));
    }
    return result;
  }
}
