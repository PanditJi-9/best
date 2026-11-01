import 'dart:convert';
import 'dart:io';

import 'package:best_domain/best_domain.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// One source an installed extension APK exposes.
///
/// The id is the extension's own long — the same number Mihon would compute —
/// so a library built in another reader still lines up here.
class ExtensionSourceInfo {
  const ExtensionSourceInfo({
    required this.sourceId,
    required this.name,
    required this.language,
    required this.packageName,
    required this.supportsLatest,
    required this.nsfw,
    required this.versionName,
    this.kind = 'manga',
  });

  final int sourceId;
  final String name;
  final String language;
  final String packageName;
  final bool supportsLatest;
  final bool nsfw;
  final String versionName;

  /// `anime` for an Aniyomi bundle, `manga` for a Mihon one. The host reads it
  /// from the extension's own manifest keys, so the picker never has to guess.
  final String kind;

  bool get isAnime => kind == 'anime';

  static ExtensionSourceInfo fromMap(Map<String, dynamic> map) {
    return ExtensionSourceInfo(
      sourceId: (map['sourceId'] as num?)?.toInt() ?? 0,
      name: (map['name'] as String?)?.trim().isNotEmpty == true
          ? map['name'] as String
          : 'Extension',
      language: (map['lang'] as String?) ?? '',
      packageName: (map['packageName'] as String?) ?? '',
      supportsLatest: map['supportsLatest'] == true,
      nsfw: map['nsfw'] == true,
      versionName: (map['versionName'] as String?) ?? '',
      kind: (map['kind'] as String?) ?? 'manga',
    );
  }
}

/// An extension APK that is installed but could not produce a source.
///
/// Kept visible instead of swallowed: an extension that silently vanishes is
/// impossible to diagnose from the phone.
class ExtensionProblem {
  const ExtensionProblem({required this.name, required this.message});

  final String name;
  final String message;

  static ExtensionProblem fromMap(Map<String, dynamic> map) {
    return ExtensionProblem(
      name: (map['packageName'] as String?) ??
          (map['fileName'] as String?) ??
          'Extension',
      message: (map['error'] as String?) ?? 'The extension did not load.',
    );
  }
}

class ExtensionCatalog {
  const ExtensionCatalog({required this.sources, required this.problems});

  const ExtensionCatalog.empty()
      : sources = const <ExtensionSourceInfo>[],
        problems = const <ExtensionProblem>[];

  final List<ExtensionSourceInfo> sources;
  final List<ExtensionProblem> problems;

  bool get isEmpty => sources.isEmpty && problems.isEmpty;
}

/// The bridge to the Kotlin extension host.
///
/// Every extension APK is loaded by the app's own `DexClassLoader` against the
/// real `source-api` implementation Best ships, so a source behaves exactly as
/// it does under Mihon: same catalogue, same chapter list, same pages. Best
/// itself never scrapes a site.
class ExtensionHost {
  ExtensionHost({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('app.best/extensions');

  final MethodChannel _channel;

  /// `false` off Android (tests, desktop previews), where the channel is absent.
  static bool get isSupported => Platform.isAndroid;

  Future<ExtensionCatalog> catalog() async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('catalog');
      if (raw == null) return const ExtensionCatalog.empty();
      final sources = (raw['sources'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<dynamic, dynamic>>()
          .map((map) => ExtensionSourceInfo.fromMap(
                map.map((key, value) => MapEntry('$key', value)),
              ))
          .toList(growable: false);
      final problems = (raw['problems'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<dynamic, dynamic>>()
          .map((map) => ExtensionProblem.fromMap(
                map.map((key, value) => MapEntry('$key', value)),
              ))
          .toList(growable: false);
      return ExtensionCatalog(sources: sources, problems: problems);
    } on MissingPluginException {
      return const ExtensionCatalog.empty();
    } on PlatformException {
      return const ExtensionCatalog.empty();
    }
  }

  /// Downloads and installs an extension APK. Returns the package name when the
  /// host accepted it.
  Future<String?> install({required String url, required String fileName}) async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'install',
        <String, dynamic>{'url': url, 'fileName': fileName},
      );
      return raw?['packageName'] as String?;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<bool> remove(String packageName) async {
    try {
      final removed = await _channel.invokeMethod<bool>(
        'remove',
        <String, dynamic>{'packageName': packageName},
      );
      return removed ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<List<Media>> _listing(
    String method,
    int sourceId, {
    int page = 1,
    String? query,
    bool anime = false,
  }) async {
    final raw = await _channel.invokeMapMethod<String, dynamic>(
      method,
      <String, dynamic>{
        'sourceId': sourceId,
        'page': page,
        if (query != null) 'query': query,
      },
    );
    final items = raw?['items'] as List<dynamic>? ?? const <dynamic>[];
    return items
        .whereType<Map<dynamic, dynamic>>()
        .map((map) => _mediaFromMap(
              map.map((key, value) => MapEntry('$key', value)),
              sourceId,
              anime: anime,
            ))
        .toList(growable: false);
  }

  Future<List<Media>> popular(int sourceId, {int page = 1, bool anime = false}) =>
      _listing('popular', sourceId, page: page, anime: anime);

  Future<List<Media>> latest(int sourceId, {int page = 1, bool anime = false}) =>
      _listing('latest', sourceId, page: page, anime: anime);

  Future<List<Media>> search(int sourceId, String query, {int page = 1, bool anime = false}) =>
      _listing('search', sourceId, page: page, query: query, anime: anime);

  Future<Media> details(int sourceId, Media media, {bool anime = false}) async {
    final raw = await _channel.invokeMapMethod<String, dynamic>(
      'details',
      <String, dynamic>{'sourceId': sourceId, 'url': media.ref.url},
    );
    if (raw == null) return media;
    final fresh = _mediaFromMap(raw, sourceId, anime: anime);
    return media.copyWith(
      title: fresh.title.isEmpty ? null : fresh.title,
      coverUrl: fresh.coverUrl,
      synopsis: fresh.synopsis,
      author: fresh.author,
      status: fresh.status,
      genres: fresh.genres.isEmpty ? null : fresh.genres,
    );
  }

  Future<List<MediaUnit>> chapters(int sourceId, Media media) async {
    final raw = await _channel.invokeMethod<List<dynamic>>(
      'chapters',
      <String, dynamic>{'sourceId': sourceId, 'url': media.ref.url},
    );
    final list = raw ?? const <dynamic>[];
    final units = <MediaUnit>[];
    for (final entry in list.whereType<Map<dynamic, dynamic>>()) {
      final map = entry.map((key, value) => MapEntry('$key', value));
      final url = (map['url'] as String?) ?? '';
      if (url.isEmpty) continue;
      final number = (map['chapterNumber'] as num?)?.toDouble() ?? -1;
      final title = (map['name'] as String?) ?? '';
      units.add(
        MediaUnit(
          mediaId: media.id,
          url: url,
          number: number > 0 ? number : _numberFromTitle(title, units.length),
          title: title.isEmpty ? 'Chapter ${units.length + 1}' : title,
          kind: media.kind.isReading ? UnitKind.chapter : UnitKind.episode,
          publishedAt: ((map['dateUpload'] as num?)?.toInt() ?? 0) * 1000,
        ),
      );
    }
    return units;
  }

  Future<List<MediaResource>> pages(int sourceId, MediaUnit unit) async {
    final raw = await _channel.invokeMethod<List<dynamic>>(
      'pages',
      <String, dynamic>{'sourceId': sourceId, 'url': unit.url},
    );
    final list = raw ?? const <dynamic>[];
    final resources = <MediaResource>[];
    for (final entry in list.whereType<Map<dynamic, dynamic>>()) {
      final map = entry.map((key, value) => MapEntry('$key', value));
      final url = (map['url'] as String?) ?? '';
      if (url.isEmpty) continue;
      final headers = <String, String>{};
      final rawHeaders = map['headers'];
      if (rawHeaders is Map) {
        rawHeaders.forEach((key, value) {
          if (value is List && value.isNotEmpty) {
            headers['$key'] = '${value.first}';
          } else if (value != null) {
            headers['$key'] = '$value';
          }
        });
      }
      // A referer is the difference between a page and a 403 on many sites.
      headers.remove('Host');
      resources.add(ImageResource(url, headers: headers));
    }
    return resources;
  }

  /// Streams for one episode of an anime extension.
  ///
  /// A source may answer with several mirrors; they come back in the order the
  /// extension ranked them, so the player can offer a quality picker without
  /// knowing anything about the site.
  Future<List<MediaResource>> videos(int sourceId, MediaUnit unit) async {
    final raw = await _channel.invokeMethod<List<dynamic>>(
      'videos',
      <String, dynamic>{'sourceId': sourceId, 'url': unit.url},
    );
    final list = raw ?? const <dynamic>[];
    final resources = <MediaResource>[];
    for (final entry in list.whereType<Map<dynamic, dynamic>>()) {
      final map = entry.map((key, value) => MapEntry('$key', value));
      final url = (map['url'] as String?) ?? '';
      if (url.isEmpty) continue;
      final headers = <String, String>{};
      final rawHeaders = map['headers'];
      if (rawHeaders is Map) {
        rawHeaders.forEach((key, value) {
          if (value is List && value.isNotEmpty) {
            headers['$key'] = '${value.first}';
          } else if (value != null) {
            headers['$key'] = '$value';
          }
        });
      }
      headers.remove('Host');
      resources.add(
        VideoResource(
          url,
          headers: headers,
          mimeType: _mimeFor(url),
        ),
      );
    }
    return resources;
  }

  /// Guesses the container from the url so the player picks the right decoder.
  static String? _mimeFor(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
    if (path.endsWith('.m3u8')) return 'application/x-mpegURL';
    if (path.endsWith('.mpd')) return 'application/dash+xml';
    if (path.endsWith('.mp4') || path.endsWith('.m4v')) return 'video/mp4';
    if (path.endsWith('.webm')) return 'video/webm';
    return null;
  }

  static double _numberFromTitle(String title, int fallbackIndex) {
    final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(title);
    if (match != null) {
      return double.tryParse(match.group(1)!) ?? (fallbackIndex + 1).toDouble();
    }
    return (fallbackIndex + 1).toDouble();
  }

  static Media _mediaFromMap(Map<String, dynamic> map, int sourceId, {bool anime = false}) {
    final genres = ((map['genre'] as String?) ?? '')
        .split(',')
        .map((genre) => genre.trim())
        .where((genre) => genre.isNotEmpty)
        .toList(growable: false);
    return Media(
      ref: SourceRef('mihon:$sourceId', (map['url'] as String?) ?? ''),
      title: ((map['title'] as String?) ?? '').trim(),
      kind: anime ? MediaKind.anime : MediaKind.manga,
      coverUrl: (map['thumbnailUrl'] as String?)?.trim().isEmpty == true
          ? null
          : map['thumbnailUrl'] as String?,
      synopsis: map['description'] as String?,
      author: (map['author'] as String?) ?? (map['artist'] as String?),
      status: _statusFrom(map['status'] as num?),
      genres: genres,
    );
  }

  static MediaStatus _statusFrom(num? status) {
    return switch (status?.toInt()) {
      1 => MediaStatus.ongoing,
      2 => MediaStatus.completed,
      5 => MediaStatus.cancelled,
      6 => MediaStatus.hiatus,
      _ => MediaStatus.unknown,
    };
  }
}

/// A [SourceAdapter] over one extension source.
class ExtensionSourceAdapter implements SourceAdapter {
  ExtensionSourceAdapter({required this.host, required this.info});

  final ExtensionHost host;
  final ExtensionSourceInfo info;

  @override
  String get id => 'mihon:${info.sourceId}';

  @override
  String get name => info.name;

  @override
  String get language => info.language.isEmpty ? 'all' : info.language;

  @override
  Future<List<Media>> popular({int page = 1}) =>
      host.popular(info.sourceId, page: page, anime: info.isAnime);

  @override
  Future<List<Media>> search(String query, {int page = 1}) =>
      host.search(info.sourceId, query, page: page, anime: info.isAnime);

  @override
  Future<Media> details(Media media) =>
      host.details(info.sourceId, media, anime: info.isAnime);

  @override
  Future<List<MediaUnit>> units(Media media) =>
      host.chapters(info.sourceId, media);

  @override
  Future<List<MediaResource>> resources(MediaUnit unit) => info.isAnime
      ? host.videos(info.sourceId, unit)
      : host.pages(info.sourceId, unit);
}

/// One entry in an extension repository's index.
class ExtensionEntry {
  const ExtensionEntry({
    required this.name,
    required this.packageName,
    required this.apkUrl,
    required this.language,
    required this.version,
    required this.nsfw,
  });

  final String name;
  final String packageName;
  final String apkUrl;
  final String language;
  final String version;
  final bool nsfw;

  String get fileName {
    final tail = apkUrl.split('/').last;
    return tail.endsWith('.apk') ? tail : '$packageName.apk';
  }
}

/// Reads a Mihon-style extension repository index.
///
/// Both shapes in the wild are accepted: the flat array (`index.min.json`) and
/// the object with `extensionList.extensions` (`index.json`).
class ExtensionRepository {
  ExtensionRepository({required this.indexUrl, required http.Client client})
      : _client = client;

  /// The maintained Mihon repository. Its index is the list Mihon itself reads.
  static const String defaultIndexUrl =
      'https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.json';

  /// The anime side of the same idea. Aniyomi's official list was retired, so
  /// this is the community fork that still builds and signs Aniyomi bundles.
  static const String defaultAnimeIndexUrl =
      'https://raw.githubusercontent.com/yuzono/anime-repo/repo/index.min.json';

  final String indexUrl;
  final http.Client _client;

  Future<List<ExtensionEntry>> fetch() async {
    final response = await _client.get(
      Uri.parse(indexUrl),
      headers: const {'Accept': 'application/json'},
    );
    if (response.statusCode != 200) {
      throw StateError('The extension repository answered ${response.statusCode}.');
    }
    final decoded = jsonDecode(response.body);
    final rawList = switch (decoded) {
      final List<dynamic> list => list,
      final Map<String, dynamic> map =>
        ((map['extensionList'] as Map<String, dynamic>?)?['extensions']
                as List<dynamic>?) ??
            const <dynamic>[],
      _ => const <dynamic>[],
    };
    return rawList
        .whereType<Map<String, dynamic>>()
        .map((entry) => _entryFrom(entry, indexUrl))
        .whereType<ExtensionEntry>()
        .toList(growable: false);
  }

  static ExtensionEntry? _entryFrom(Map<String, dynamic> map, String indexUrl) {
    final name = (map['name'] as String?)?.trim();
    final pkg = (map['pkg'] as String?) ?? (map['packageName'] as String?);
    final resources = map['resources'];
    final apkUrl = (map['apk'] as String?) ??
        (resources is Map ? resources['apkUrl'] as String? : null);
    if (name == null || name.isEmpty || pkg == null || apkUrl == null) {
      return null;
    }
    // The flat index carries a bare file name; the full one carries a url.
    final absolute = apkUrl.startsWith('http')
        ? apkUrl
        : '${indexUrl.substring(0, indexUrl.lastIndexOf('/'))}/apk/$apkUrl';
    final warning = map['contentWarning'];
    return ExtensionEntry(
      name: name,
      packageName: pkg,
      apkUrl: absolute,
      language: (map['lang'] as String?) ?? _languageFrom(map['sources']),
      version: (map['version'] as String?) ??
          (map['versionName'] as String?) ??
          '',
      nsfw: map['nsfw'] == 1 ||
          map['nsfw'] == true ||
          (warning is String && warning != 'CONTENT_WARNING_NONE'),
    );
  }

  /// The first language the bundle declares, so a picker can group by it.
  static String _languageFrom(Object? sources) {
    if (sources is List) {
      for (final entry in sources.whereType<Map<String, dynamic>>()) {
        final lang = entry['language'] as String?;
        if (lang != null && lang.isNotEmpty) return lang;
      }
    }
    return 'all';
  }
}

/// Installs the starter set on a first launch, so Browse is not empty and the
/// reader never has to visit a repository.
///
/// The set is a small, explicit allowlist of long-lived sources rather than
/// "whatever the index lists first": an extension that dies is a dead shelf, so
/// the choice is deliberate and the rest stay one tap away in Settings.
class ExtensionInstaller {
  ExtensionInstaller({
    required this.host,
    required this.repository,
    this.animeRepository,
    required this.preferences,
  });

  static const String _bootstrappedKey = 'extensions_bootstrapped_v2';

  /// MangaDex, MangaFire, Weeb Central, MangaKatana and the Arabic 3asq.
  /// Matched by package name against the repository index; anything the
  /// repository no longer carries is skipped without failing the rest.
  static const List<String> starterPackages = <String>[
    'eu.kanade.tachiyomi.extension.all.mangadex',
    'eu.kanade.tachiyomi.extension.all.mangafire',
    'eu.kanade.tachiyomi.extension.en.weebcentral',
    'eu.kanade.tachiyomi.extension.en.mangakatana',
    'eu.kanade.tachiyomi.extension.ar.manga3asq',
  ];

  /// Anime bundles: Aniyomi extensions, a separate repository and ABI.
  /// AniZone, AnimePahe, AniZone's sibling AnimeXin and AnimeKai cover the
  /// shapes in the wild: a v14 bundle, a v16 source, and a source whose only
  /// constructor takes a preference list.
  static const List<String> animeStarterPackages = <String>[
    'eu.kanade.tachiyomi.animeextension.all.anizone',
    'eu.kanade.tachiyomi.animeextension.en.animepahe',
    'eu.kanade.tachiyomi.animeextension.en.kotokai',
    'eu.kanade.tachiyomi.animeextension.all.animexin',
  ];

  final ExtensionHost host;
  final ExtensionRepository repository;
  final ExtensionRepository? animeRepository;
  final SharedPreferences? preferences;

  bool get _bootstrapped => preferences?.getBool(_bootstrappedKey) ?? false;

  /// Installs what is missing from [starterPackages]. Returns how many APKs were
  /// written. Never throws: a first launch on a bad network must still open.
  Future<int> ensureStarterSet({bool force = false}) async {
    if (!ExtensionHost.isSupported) return 0;
    if (_bootstrapped && !force) return 0;
    final catalog = await host.catalog();
    final installed = catalog.sources.map((s) => s.packageName).toSet();

    var written = 0;
    var reachable = 0;
    var pending = 0;
    final batches = <(ExtensionRepository, List<String>)>[
      (repository, starterPackages),
      if (animeRepository != null) (animeRepository!, animeStarterPackages),
    ];
    for (final (source, packages) in batches) {
      List<ExtensionEntry> entries;
      try {
        entries = await source.fetch();
      } catch (_) {
        // One dead index must not cost the reader the other shelf.
        continue;
      }
      reachable++;
      final wanted = entries
          .where((entry) => packages.contains(entry.packageName))
          .where((entry) => !installed.contains(entry.packageName))
          .toList(growable: false);
      pending += wanted.length;
      for (final entry in wanted) {
        final packageName = await host.install(
          url: entry.apkUrl,
          fileName: entry.fileName,
        );
        if (packageName != null) written++;
      }
    }
    // Only remember success, so a launch without a network tries again next time.
    if (written > 0 || (reachable > 0 && pending == 0)) {
      await preferences?.setBool(_bootstrappedKey, true);
    }
    return written;
  }

  /// Everything the repository carries, for the "add sources" sheet.
  Future<List<ExtensionEntry>> available() => repository.fetch();
}
