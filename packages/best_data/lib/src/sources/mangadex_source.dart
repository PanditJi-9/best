import 'dart:convert';

import 'package:best_domain/best_domain.dart';
import 'package:http/http.dart' as http;

/// Raised when MangaDex answers with something the adapter cannot use.
class MangaDexException implements Exception {
  const MangaDexException(this.message);

  final String message;

  @override
  String toString() => 'MangaDexException: $message';
}

/// A first real catalogue.
///
/// MangaDex is used because it is an actual public API with a documented
/// contract, not a scraped page. The adapter maps its model onto Best's own
/// types; nothing above this file knows the API exists.
class MangaDexSource implements SourceAdapter {
  MangaDexSource({
    required http.Client client,
    String language = 'en',
  })  : _client = client,
        _language = language;

  static const String sourceId = 'mangadex';
  static const String _host = 'api.mangadex.org';
  static const String _uploads = 'https://uploads.mangadex.org';

  static const Map<String, String> _headers = {
    'User-Agent': 'Best/0.8 (https://github.com/PanditJi-9/best)',
    'Accept': 'application/json',
  };

  final http.Client _client;
  final String _language;

  @override
  String get id => sourceId;

  @override
  String get name => 'MangaDex';

  @override
  String get language => _language;

  @override
  Future<List<Media>> popular({int page = 1}) => _list(page: page);

  @override
  Future<List<Media>> search(String query, {int page = 1}) =>
      _list(query: query, page: page);

  Future<List<Media>> _list({String? query, int page = 1}) async {
    final params = <String, dynamic>{
      'limit': '24',
      'offset': '${(page - 1) * 24}',
      'includes[]': ['cover_art', 'author'],
      'contentRating[]': ['safe', 'suggestive'],
      // Only works that actually have a chapter in the reader's language: a
      // beautiful cover with no readable chapter is a dead end.
      'availableTranslatedLanguage[]': [_language],
      'order[followedCount]': 'desc',
    };
    final trimmed = query?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      params['title'] = trimmed;
    }

    final json = await _getJson(Uri.https(_host, '/manga', params));
    final data = json['data'];
    if (data is! List) {
      throw const MangaDexException('The catalogue response has no data list.');
    }
    return data
        .whereType<Map<String, dynamic>>()
        .map(_mediaFromJson)
        .toList(growable: false);
  }

  @override
  Future<Media> details(Media media) async {
    final json = await _getJson(
      Uri.https(_host, '/manga/${media.ref.url}', {
        'includes[]': ['cover_art', 'author'],
      }),
    );
    final data = json['data'];
    if (data is! Map<String, dynamic>) {
      throw const MangaDexException('The work response has no data object.');
    }
    return _mediaFromJson(data);
  }

  @override
  Future<List<MediaUnit>> units(Media media) async {
    // One language per shelf, not a mix: an Arabic reader should not find
    // chapter 3 only in English and chapter 4 only in Arabic. English is the
    // fallback when the work has no chapter in the interface language.
    final units = await _feed(media, _language);
    if (units.isEmpty && _language != 'en') return _feed(media, 'en');
    return units;
  }

  Future<List<MediaUnit>> _feed(Media media, String language) async {
    final units = <MediaUnit>[];
    final seenNumbers = <double>{};
    var offset = 0;

    // A work with more than 2,000 chapters is not a phone-sized read; the cap
    // keeps a hostile or broken response from looping forever.
    while (offset < 2000) {
      final json = await _getJson(
        Uri.https(_host, '/manga/${media.ref.url}/feed', {
          'limit': '100',
          'offset': '$offset',
          'translatedLanguage[]': [language],
          'order[volume]': 'asc',
          'order[chapter]': 'asc',
          'includeExternalUrl': '0',
          'includeEmptyPages': '0',
          'includeFuturePublishAt': '0',
          'includeUnavailable': '0',
        }),
      );

      final data = json['data'];
      if (data is! List || data.isEmpty) break;

      for (final raw in data.whereType<Map<String, dynamic>>()) {
        final attributes = _asMap(raw['attributes']);
        final external = attributes['externalUrl'];
        if (external is String && external.isNotEmpty) continue;

        final id = raw['id'];
        if (id is! String) continue;

        final number = double.tryParse('${attributes['chapter'] ?? ''}') ??
            parseUnitNumber('${attributes['title'] ?? ''}') ??
            0;
        if (!seenNumbers.add(number)) continue;

        final pages = attributes['pages'];
        units.add(
          MediaUnit(
            mediaId: media.id,
            url: id,
            number: number,
            title: _unitTitle(attributes, number),
            kind: UnitKind.chapter,
            publishedAt: _epoch(attributes['publishAt']),
            pageCount: pages is int ? pages : 0,
          ),
        );
      }

      offset += data.length;
      if (data.length < 100) break;
    }

    units.sort((a, b) => a.number.compareTo(b.number));
    return units;
  }

  @override
  Future<List<MediaResource>> resources(MediaUnit unit) async {
    final json = await _getJson(Uri.https(_host, '/at-home/server/${unit.url}'));
    final baseUrl = json['baseUrl'];
    final chapter = _asMap(json['chapter']);
    final hash = chapter['hash'];
    final data = chapter['data'];

    if (baseUrl is! String || hash is! String || data is! List) {
      throw const MangaDexException('The page response is incomplete.');
    }

    return data
        .whereType<String>()
        .map((file) => ImageResource('$baseUrl/data/$hash/$file'))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    var response = await _client.get(uri, headers: _headers);
    // MangaDex throttles bursts. One short retry turns a rate-limit into a
    // slightly slower screen instead of an error page.
    if (response.statusCode == 429 || response.statusCode == 503) {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      response = await _client.get(uri, headers: _headers);
    }
    if (response.statusCode != 200) {
      throw MangaDexException('HTTP ${response.statusCode} for ${uri.path}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const MangaDexException('The response is not a JSON object.');
    }
    return decoded;
  }

  Media _mediaFromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || id.isEmpty) {
      throw const MangaDexException('A work is missing its id.');
    }
    final attributes = _asMap(json['attributes']);
    final originalLanguage = attributes['originalLanguage'];

    return Media(
      ref: SourceRef(sourceId, id),
      title: _localized(attributes['title']) ?? id,
      nativeTitle: _nativeTitle(attributes['altTitles']),
      kind: _kind(originalLanguage is String ? originalLanguage : null),
      coverUrl: _cover(json['relationships'], id),
      synopsis: _localized(attributes['description']),
      year: attributes['year'] is int ? attributes['year'] as int : null,
      status: _status(attributes['status']),
      genres: _genres(attributes['tags']),
    );
  }

  String? _localized(Object? raw) {
    if (raw is! Map) return null;
    final map = raw.cast<String, dynamic>();
    for (final key in [_language, 'en', 'ar']) {
      final value = map[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    for (final value in map.values) {
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  String? _nativeTitle(Object? raw) {
    if (raw is! List) return null;
    for (final entry in raw) {
      if (entry is! Map) continue;
      for (final key in const ['ja', 'ko', 'zh']) {
        final value = entry[key];
        if (value is String && value.trim().isNotEmpty) return value.trim();
      }
    }
    return null;
  }

  List<String> _genres(Object? raw) {
    if (raw is! List) return const [];
    final genres = <String>[];
    for (final tag in raw.whereType<Map<String, dynamic>>()) {
      final attributes = _asMap(tag['attributes']);
      final name = _localized(attributes['name']);
      if (name != null) genres.add(name);
    }
    return List.unmodifiable(genres.take(8));
  }

  String? _cover(Object? raw, String id) {
    if (raw is! List) return null;
    for (final entry in raw.whereType<Map<String, dynamic>>()) {
      if (entry['type'] != 'cover_art') continue;
      final attributes = _asMap(entry['attributes']);
      final file = attributes['fileName'];
      if (file is String && file.isNotEmpty) {
        // 512 keeps a hero sharp on a phone without shipping a 1 MB cover.
        return '$_uploads/covers/$id/$file.512.jpg';
      }
    }
    return null;
  }

  String _unitTitle(Map<String, dynamic> attributes, double number) {
    final title = attributes['title'];
    if (title is String && title.trim().isNotEmpty) return title.trim();
    final rounded = number == number.roundToDouble()
        ? number.toInt().toString()
        : number.toString();
    return 'Chapter $rounded';
  }

  int _epoch(Object? raw) {
    if (raw is! String) return 0;
    return DateTime.tryParse(raw)?.millisecondsSinceEpoch ?? 0;
  }

  MediaKind _kind(String? originalLanguage) => switch (originalLanguage) {
        'ko' => MediaKind.manhwa,
        'zh' || 'zh-hk' => MediaKind.manhua,
        _ => MediaKind.manga,
      };

  MediaStatus _status(Object? raw) => switch (raw) {
        'ongoing' => MediaStatus.ongoing,
        'completed' => MediaStatus.completed,
        'hiatus' => MediaStatus.hiatus,
        'cancelled' => MediaStatus.cancelled,
        _ => MediaStatus.unknown,
      };

  static Map<String, dynamic> _asMap(Object? value) =>
      value is Map<String, dynamic> ? value : const {};
}
