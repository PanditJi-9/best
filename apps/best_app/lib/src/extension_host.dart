import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:best_domain/best_domain.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// The extension source id inside a `mihon:` source reference, if any.
///
/// A source reference is either a built-in name (`mangadex`) or
/// `mihon:<extension long id>`. Only the second kind can be asked for page
/// images through the extension host.
int? extensionSourceIdOf(String sourceId) {
  if (!sourceId.startsWith('mihon:')) return null;
  return int.tryParse(sourceId.substring('mihon:'.length));
}

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
  const ExtensionCatalog(
      {required this.sources,
      required this.problems,
      this.installed = const []});

  const ExtensionCatalog.empty()
      : sources = const <ExtensionSourceInfo>[],
        problems = const <ExtensionProblem>[],
        installed = const <InstalledExtension>[];

  final List<ExtensionSourceInfo> sources;
  final List<ExtensionProblem> problems;
  final List<InstalledExtension> installed;

  bool get isEmpty => sources.isEmpty && problems.isEmpty && installed.isEmpty;
}

/// Inventory includes APKs that could not load, so they remain removable and
/// eligible for an upstream fix instead of disappearing from the directory.
class InstalledExtension {
  const InstalledExtension(
      {required this.packageName,
      required this.versionCode,
      required this.versionName,
      this.kind = 'manga'});
  final String packageName;
  final int versionCode;
  final String versionName;
  final String kind;

  factory InstalledExtension.fromMap(Map<String, dynamic> map) =>
      InstalledExtension(
          packageName: map['packageName'] as String,
          versionCode: (map['versionCode'] as num?)?.toInt() ?? 0,
          versionName: map['versionName'] as String? ?? '',
          kind: map['kind'] as String? ?? 'manga');
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
  final _listingRequests = <({
    String method,
    int sourceId,
    int page,
    String? query,
    bool anime
  }),
      Future<List<Media>>>{};

  /// `false` off Android (tests, desktop previews), where the channel is absent.
  static bool get isSupported => Platform.isAndroid;

  /// An instance seam for host implementations used in offline tests.
  bool get isAvailable => isSupported;

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
      final installed = (raw['installed'] as List<dynamic>? ?? const [])
          .whereType<Map<dynamic, dynamic>>()
          .map((map) => InstalledExtension.fromMap(
              map.map((key, value) => MapEntry('$key', value))))
          .toList(growable: false);
      return ExtensionCatalog(
          sources: sources, problems: problems, installed: installed);
    } on MissingPluginException {
      return const ExtensionCatalog.empty();
    }
  }

  /// Downloads and installs an extension APK. Returns the package name when the
  /// host accepted it.
  Future<String?> install(
      {required String url,
      required String fileName,
      required String expectedPackage,
      required int expectedVersionCode}) async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'install',
        <String, dynamic>{
          'url': url,
          'fileName': fileName,
          'expectedPackage': expectedPackage,
          'expectedVersionCode': expectedVersionCode
        },
      );
      return raw?['packageName'] as String?;
    } on MissingPluginException {
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
  }) {
    // Registry updates can rebuild Browse while its first request is still
    // running. Share only overlapping reads: duplicate requests can trigger a
    // site's rate limit or run concurrent WebView challenges. A later refresh,
    // including one after failure, must still make a fresh request.
    final key = (
      method: method,
      sourceId: sourceId,
      page: page,
      query: query,
      anime: anime,
    );
    return _listingRequests.putIfAbsent(
      key,
      () => _fetchListing(method, sourceId,
              page: page, query: query, anime: anime)
          .whenComplete(() {
        // Do not return the removed Future: whenComplete would await itself.
        _listingRequests.remove(key);
      }),
    );
  }

  Future<List<Media>> _fetchListing(
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

  Future<List<Media>> popular(int sourceId,
          {int page = 1, bool anime = false}) =>
      _listing('popular', sourceId, page: page, anime: anime);

  Future<List<Media>> latest(int sourceId,
          {int page = 1, bool anime = false}) =>
      _listing('latest', sourceId, page: page, anime: anime);

  Future<List<Media>> search(int sourceId, String query,
          {int page = 1, bool anime = false}) =>
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

  /// One page image, downloaded by the extension's own HTTP client.
  ///
  /// Flutter's client has neither the extension's cookies nor its signing
  /// interceptors, so a CDN can answer 403 to an image that works inside the
  /// extension (MangaFire's did). When the host is not there — tests, desktop —
  /// this answers null and the caller keeps the plain network image path.
  Future<Uint8List?> imageBytes(
    int sourceId,
    String url, {
    Map<String, String> headers = const {},
  }) async {
    try {
      return await _channel.invokeMethod<Uint8List>('imageBytes', <String, dynamic>{
        'sourceId': sourceId,
        'url': url,
        'headers': headers,
      });
    } on MissingPluginException {
      return null;
    }
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

  static Media _mediaFromMap(Map<String, dynamic> map, int sourceId,
      {bool anime = false}) {
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
    this.versionCode = 0,
    this.iconUrl,
    this.kind = 'manga',
    this.contentWarning = 'safe',
    this.sources = const [],
    this.repositoryUrl = '',
  });

  final String name;
  final String packageName;
  final String apkUrl;
  final String language;
  final String version;
  final bool nsfw;
  final int versionCode;
  final String? iconUrl;
  final String kind;
  final String contentWarning;
  final List<ExtensionSite> sources;
  final String repositoryUrl;

  Set<String> get languages =>
      sources.isEmpty ? {language} : sources.map((s) => s.language).toSet();
  bool matches(String query) {
    final term = query.trim().toLowerCase();
    return term.isEmpty ||
        [
          name,
          packageName,
          ...languages,
          for (final site in sources) ...[site.name, site.homeUrl]
        ].any((value) => value.toLowerCase().contains(term));
  }

  String get fileName {
    final tail = apkUrl.split('/').last;
    return tail.endsWith('.apk') ? tail : '$packageName.apk';
  }
}

class ExtensionSite {
  const ExtensionSite(
      {required this.name, required this.language, required this.homeUrl});
  final String name;
  final String language;
  final String homeUrl;
}

/// Reads a Mihon-style extension repository index.
///
/// Both shapes in the wild are accepted: the flat array (`index.min.json`) and
/// the object with `extensionList.extensions` (`index.json`).
class ExtensionRepository {
  ExtensionRepository(
      {required this.indexUrl, required http.Client client, this.preferences})
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
  final SharedPreferences? preferences;
  bool fromCache = false;
  String? lastError;
  Future<List<ExtensionEntry>>? _request;
  String get _cacheKey => 'extension_index_v1:$indexUrl';

  Future<List<ExtensionEntry>> fetch() =>
      _request ??= _fetch().whenComplete(() {
        _request = null;
      });

  Future<List<ExtensionEntry>> _fetch() async {
    try {
      final response = await _client.get(
        Uri.parse(indexUrl),
        headers: const {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw StateError(
            'The extension repository answered ${response.statusCode}.');
      }
      final entries = parse(response.body, indexUrl);
      fromCache = false;
      lastError = null;
      try {
        await preferences?.setString(_cacheKey, response.body);
      } catch (_) {
        // The current index still works if local storage is full.
      }
      return entries;
    } catch (error) {
      lastError = '$error';
      final cached = preferences?.getString(_cacheKey);
      if (cached == null) rethrow;
      final entries = parse(cached, indexUrl);
      fromCache = true;
      return entries;
    }
  }

  static List<ExtensionEntry> parse(String body, String indexUrl) {
    if (body.length > 16 * 1024 * 1024) {
      throw const FormatException('The extension index is too large.');
    }
    final decoded = jsonDecode(body);
    final rawList = switch (decoded) {
      final List<dynamic> list => list,
      final Map<String, dynamic> map => ((map['extensionList']
              as Map<String, dynamic>?)?['extensions'] as List<dynamic>?) ??
          const <dynamic>[],
      _ => const <dynamic>[],
    };
    final entries = rawList
        .whereType<Map<String, dynamic>>()
        .map((entry) => _entryFrom(entry, indexUrl))
        .whereType<ExtensionEntry>()
        .toList(growable: false);
    if (entries.isEmpty) {
      throw const FormatException('The repository has no valid extensions.');
    }
    // One row per APK, never inflate the count with source/language variants.
    return {for (final entry in entries) entry.packageName: entry}
        .values
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  static ExtensionEntry? _entryFrom(Map<String, dynamic> map, String indexUrl) {
    final name = (map['name'] as String?)?.trim();
    final pkg = (map['pkg'] as String?) ?? (map['packageName'] as String?);
    final resources = map['resources'];
    final apkUrl = (map['apk'] as String?) ??
        (resources is Map ? resources['apkUrl'] as String? : null);
    final code = int.tryParse('${map['code'] ?? map['versionCode'] ?? 0}') ?? 0;
    if (name == null ||
        name.isEmpty ||
        pkg == null ||
        apkUrl == null ||
        code <= 0 ||
        !RegExp(r'^eu\.kanade\.tachiyomi\.(?:animeextension|extension)\.[\w.]+$')
            .hasMatch(pkg)) {
      return null;
    }
    // The flat index carries a bare file name; the full one carries a url.
    final absolute = apkUrl.startsWith('http')
        ? apkUrl
        : '${indexUrl.substring(0, indexUrl.lastIndexOf('/'))}/apk/$apkUrl';
    final warning = map['contentWarning'];
    final nsfw = map['nsfw'] == 1 ||
        map['nsfw'] == true ||
        warning == 'CONTENT_WARNING_NSFW';
    final sites = <ExtensionSite>[
      for (final site in (map['sources'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>())
        ExtensionSite(
            name: site['name'] as String? ?? name,
            language:
                site['language'] as String? ?? site['lang'] as String? ?? 'all',
            homeUrl:
                site['homeUrl'] as String? ?? site['baseUrl'] as String? ?? ''),
    ];
    if (sites.isEmpty || Uri.tryParse(absolute)?.scheme != 'https') return null;
    final icon = map['icon'] as String? ??
        (resources is Map ? resources['iconUrl'] as String? : null);
    return ExtensionEntry(
      name: name,
      packageName: pkg,
      apkUrl: absolute,
      language: (map['lang'] as String?) ?? sites.first.language,
      version:
          (map['version'] as String?) ?? (map['versionName'] as String?) ?? '',
      nsfw: nsfw,
      versionCode: code,
      kind: pkg.contains('.animeextension.') ? 'anime' : 'manga',
      contentWarning: nsfw
          ? 'nsfw'
          : warning == 'CONTENT_WARNING_MIXED'
              ? 'mixed'
              : 'safe',
      sources: sites,
      repositoryUrl: indexUrl,
      iconUrl: icon == null
          ? null
          : icon.startsWith('https://')
              ? icon
              : '${indexUrl.substring(0, indexUrl.lastIndexOf('/'))}/icon/$icon',
    );
  }
}

class ExtensionDirectory {
  const ExtensionDirectory(
      {required this.entries, this.cached = false, this.errors = const []});
  final List<ExtensionEntry> entries;
  final bool cached;
  final List<String> errors;
  int get sourceCount => entries.fold(0, (sum, e) => sum + e.sources.length);
}

class ExtensionUpdateResult {
  const ExtensionUpdateResult(
      {this.updated = 0, this.errors = const {}, this.checked = false});
  final int updated;
  final Map<String, String> errors;
  final bool checked;
}

/// Only explicit selections are installed. Index refreshes never activate new
/// sites; automatic checks update the already installed APKs, one at a time.
class ExtensionInstaller {
  ExtensionInstaller({
    required this.host,
    required this.repository,
    this.animeRepository,
    required this.preferences,
  });

  final ExtensionHost host;
  final ExtensionRepository repository;
  final ExtensionRepository? animeRepository;
  final SharedPreferences? preferences;

  Future<void> _mutations = Future.value();
  Future<ExtensionDirectory>? _directoryRequest;
  Future<ExtensionUpdateResult>? _updateRequest;
  DateTime? _lastCheck;

  Future<T> _serial<T>(Future<T> Function() work) {
    final next = _mutations.then((_) => work());
    _mutations = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<ExtensionDirectory> directory() =>
      _directoryRequest ??= _directory().whenComplete(() {
        _directoryRequest = null;
      });

  Future<ExtensionDirectory> _directory() async {
    final errors = <String>[];
    var cached = false;
    final batches = await Future.wait([
      for (final repo in [
        repository,
        if (animeRepository != null) animeRepository!
      ])
        (() async {
          try {
            final entries = await repo.fetch();
            cached |= repo.fromCache;
            if (repo.lastError != null) {
              errors.add('${repo.indexUrl}: ${repo.lastError}');
            }
            return entries;
          } catch (error) {
            errors.add('${repo.indexUrl}: $error');
            return <ExtensionEntry>[];
          }
        })(),
    ]);
    final entries = {
      for (final batch in batches)
        for (final entry in batch) entry.packageName: entry
    }.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return ExtensionDirectory(entries: entries, cached: cached, errors: errors);
  }

  Future<List<ExtensionEntry>> available() async => (await directory()).entries;

  Future<String?> activate(ExtensionEntry entry) => _serial(() => host.install(
      url: entry.apkUrl,
      fileName: entry.fileName,
      expectedPackage: entry.packageName,
      expectedVersionCode: entry.versionCode));

  Future<bool> remove(String packageName) =>
      _serial(() => host.remove(packageName));

  Future<ExtensionUpdateResult> checkUpdates({bool force = false}) =>
      _updateRequest ??=
          _serial(() => _checkUpdates(force: force)).whenComplete(() {
        _updateRequest = null;
      });

  Future<ExtensionUpdateResult> _checkUpdates({required bool force}) async {
    if (!host.isAvailable) return const ExtensionUpdateResult();
    final now = DateTime.now();
    final stamp = _lastCheck ??
        DateTime.fromMillisecondsSinceEpoch(
            preferences?.getInt('extension_update_check_v1') ?? 0);
    if (!force && now.difference(stamp) < const Duration(hours: 6)) {
      return const ExtensionUpdateResult();
    }
    final inventory = (await host.catalog()).installed;
    if (inventory.isEmpty) return const ExtensionUpdateResult();
    final index = await directory();
    final errors = <String, String>{
      for (final error in index.errors) error: error
    };
    var updated = 0;
    for (final installed in inventory) {
      final matches =
          index.entries.where((e) => e.packageName == installed.packageName);
      if (matches.isEmpty) {
        continue; // Retired APKs remain installed, never deleted.
      }
      final entry = matches.first;
      final repo = entry.kind == 'anime' ? animeRepository : repository;
      if (repo == null ||
          repo.fromCache ||
          entry.versionCode <= installed.versionCode) {
        continue;
      }
      try {
        final result = await host.install(
            url: entry.apkUrl,
            fileName: entry.fileName,
            expectedPackage: entry.packageName,
            expectedVersionCode: entry.versionCode);
        if (result == entry.packageName) {
          updated++;
        } else {
          errors[entry.packageName] = 'The extension was not accepted.';
        }
      } catch (error) {
        errors[entry.packageName] = '$error';
      }
    }
    // Failed downloads are eligible on next resume; success checks are throttled.
    _lastCheck = errors.isEmpty
        ? now
        : now.subtract(const Duration(hours: 5, minutes: 55));
    try {
      await preferences?.setInt(
          'extension_update_check_v1', _lastCheck!.millisecondsSinceEpoch);
    } catch (_) {/* Session throttle still applies. */}
    return ExtensionUpdateResult(
        updated: updated, errors: errors, checked: true);
  }
}
