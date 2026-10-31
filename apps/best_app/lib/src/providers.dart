import 'dart:async';
import 'dart:io';

import 'package:best_data/best_data.dart';
import 'package:best_domain/best_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'network.dart';

/// Replaced in `main()` after the database is open. A provider that throws
/// until it is overridden is better than a nullable global that fails later.
final Provider<LibraryRepository> repositoryProvider =
    Provider<LibraryRepository>(
  (ref) => throw StateError('repositoryProvider must be overridden in main().'),
);

/// `null` means the platform store is unavailable; settings then live for the
/// session only. Persistence is a convenience, never a reason to fail a launch.
final Provider<SharedPreferences?> preferencesProvider =
    Provider<SharedPreferences?>((ref) => null);

final Provider<http.Client> httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

/// Where finished pages live. `main()` overrides this with the app documents
/// directory; the temp fallback keeps tests and a broken platform store
/// working for the session instead of disabling downloads.
final Provider<Directory> downloadRootProvider = Provider<Directory>((ref) {
  return Directory(p.join(Directory.systemTemp.path, 'best-downloads'));
});

final Provider<DownloadManager> downloadManagerProvider =
    Provider<DownloadManager>((ref) {
  final manager = DownloadManager(
    repository: ref.watch(repositoryProvider),
    registry: ref.watch(sourceRegistryProvider),
    client: ref.watch(httpClientProvider),
    root: ref.watch(downloadRootProvider),
  );
  ref.onDispose(manager.dispose);

  // The queue obeys two app-level rules: the Wi-Fi-only setting and the storage
  // cap. Both are read through closures so changing a setting does not rebuild
  // the manager (and therefore does not drop a download in flight).
  void applyPolicy() {
    final settings = ref.read(settingsProvider);
    final network = ref.read(networkProvider).value ?? NetworkKind.unknown;
    manager.mayDownload = () =>
        !settings.wifiOnly || network != NetworkKind.mobile;
    manager.storageCap = () => settings.storageCapGb * 1024 * 1024 * 1024;
    if (manager.mayDownload()) {
      unawaited(manager.pump().catchError((Object _) {}));
    }
  }

  ref.listen(settingsProvider, (previous, next) => applyPolicy());
  ref.listen(networkProvider, (previous, next) => applyPolicy());
  applyPolicy();

  unawaited(manager.restore().catchError((Object _) {}));
  return manager;
});

/// Packs the person installed, newest last. Broken documents are dropped on
/// load instead of blocking the app: a bad edit must never cost the library.
class SourcePacksController extends Notifier<List<SourcePack>> {
  static const String _key = 'source_packs_v1';
  static const Set<String> _reserved = {'demo', 'mangadex'};

  @override
  List<SourcePack> build() {
    final preferences = ref.watch(preferencesProvider);
    return _parseAll(
      preferences?.getStringList(_key) ?? const <String>[],
    );
  }

  List<SourcePack> _parseAll(List<String> raws) {
    final packs = <SourcePack>[];
    for (final raw in raws) {
      try {
        packs.add(SourcePack.parse(raw));
      } on SourcePackException {
        // Skip, keep the rest.
      }
    }
    return List.unmodifiable(packs);
  }

  /// Returns `null` on success, or a message to show under the field.
  String? add(String raw) {
    final SourcePack pack;
    try {
      pack = SourcePack.parse(raw);
    } on SourcePackException catch (error) {
      return error.message;
    }
    if (_reserved.contains(pack.id)) {
      return 'The id "${pack.id}" is reserved by a built-in source.';
    }
    final preferences = ref.read(preferencesProvider);
    final raws = <String>[
      ...?preferences?.getStringList(_key),
    ]..removeWhere((stored) {
        try {
          return SourcePack.parse(stored).id == pack.id;
        } on SourcePackException {
          return true;
        }
      });
    raws.add(raw.trim());
    unawaited(preferences?.setStringList(_key, raws));
    state = _parseAll(raws);
    return null;
  }

  /// Canonical documents for every installed pack, so a backup or a sync can
  /// carry them. Re-encoding means the stored copy is normalised on the way out.
  List<String> exportAll() =>
      [for (final pack in state) pack.encode()];

  /// Installs packs from a backup, skipping the reserved ids and any document
  /// that does not parse. Returns how many were actually installed.
  int addAll(Iterable<String> raws) {
    var installed = 0;
    for (final raw in raws) {
      if (add(raw) == null) installed++;
    }
    return installed;
  }

  void remove(String id) {
    final preferences = ref.read(preferencesProvider);
    final raws = <String>[
      ...?preferences?.getStringList(_key),
    ]..removeWhere((stored) {
        try {
          return SourcePack.parse(stored).id == id;
        } on SourcePackException {
          return true;
        }
      });
    unawaited(preferences?.setStringList(_key, raws));
    state = _parseAll(raws);
  }
}

final NotifierProvider<SourcePacksController, List<SourcePack>>
    sourcePacksProvider =
    NotifierProvider<SourcePacksController, List<SourcePack>>(
  SourcePacksController.new,
);

final Provider<SourceRegistry> sourceRegistryProvider =
    Provider<SourceRegistry>((ref) {
  final client = ref.watch(httpClientProvider);
  final packs = ref.watch(sourcePacksProvider);
  // The catalogue follows the interface language: an Arabic reader gets the
  // Arabic scanlations first, and English stays as the fallback chapter track.
  final settings = ref.watch(settingsProvider);
  final language = settings.languageCode ??
      WidgetsBinding.instance.platformDispatcher.locale.languageCode;
  // Real catalogues lead: Browse opens on MangaDex, and the bundled guide sits
  // last as the offline demo instead of the first thing a reader sees.
  return SourceRegistry.fixed(<SourceAdapter>[
    MangaDexSource(
      client: client,
      language: language == 'ar' ? 'ar' : 'en',
    ),
    for (final pack in packs) JsonSourceAdapter(pack: pack, client: client),
    const DemoSource(),
  ]);
});

class AppSettings {
  const AppSettings({
    this.languageCode,
    this.themeMode = ThemeMode.system,
    this.wifiOnly = false,
    this.storageCapGb = 0,
  });

  /// `null` follows the system locale.
  final String? languageCode;
  final ThemeMode themeMode;

  /// Downloads wait for Wi-Fi. Off by default: a setting that silently stops a
  /// download on a first launch is worse than a small data bill.
  final bool wifiOnly;

  /// Offline storage cap in gigabytes. `0` means no cap.
  final int storageCapGb;

  AppSettings copyWith({
    String? languageCode,
    bool clearLanguage = false,
    ThemeMode? themeMode,
    bool? wifiOnly,
    int? storageCapGb,
  }) {
    return AppSettings(
      languageCode: clearLanguage ? null : (languageCode ?? this.languageCode),
      themeMode: themeMode ?? this.themeMode,
      wifiOnly: wifiOnly ?? this.wifiOnly,
      storageCapGb: storageCapGb ?? this.storageCapGb,
    );
  }
}

class SettingsController extends Notifier<AppSettings> {
  static const String _languageKey = 'language';
  static const String _themeKey = 'theme';
  static const String _wifiOnlyKey = 'wifi_only';
  static const String _storageCapKey = 'storage_cap_gb';

  @override
  AppSettings build() {
    final preferences = ref.watch(preferencesProvider);
    return AppSettings(
      languageCode: preferences?.getString(_languageKey),
      themeMode: _readTheme(preferences?.getString(_themeKey)),
      wifiOnly: preferences?.getBool(_wifiOnlyKey) ?? false,
      storageCapGb: preferences?.getInt(_storageCapKey) ?? 0,
    );
  }

  void setLanguage(String? code) {
    final preferences = ref.read(preferencesProvider);
    if (code == null) {
      unawaited(preferences?.remove(_languageKey));
    } else {
      unawaited(preferences?.setString(_languageKey, code));
    }
    state = state.copyWith(languageCode: code, clearLanguage: code == null);
  }

  void setThemeMode(ThemeMode mode) {
    unawaited(ref.read(preferencesProvider)?.setString(_themeKey, mode.name));
    state = state.copyWith(themeMode: mode);
  }

  void setWifiOnly(bool value) {
    unawaited(ref.read(preferencesProvider)?.setBool(_wifiOnlyKey, value));
    state = state.copyWith(wifiOnly: value);
  }

  void setStorageCapGb(int value) {
    unawaited(ref.read(preferencesProvider)?.setInt(_storageCapKey, value));
    state = state.copyWith(storageCapGb: value);
  }

  static ThemeMode _readTheme(String? name) {
    for (final mode in ThemeMode.values) {
      if (mode.name == name) return mode;
    }
    return ThemeMode.system;
  }
}

final NotifierProvider<SettingsController, AppSettings> settingsProvider =
    NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

class LibraryQueryController extends Notifier<LibraryQuery> {
  @override
  LibraryQuery build() => const LibraryQuery();

  void setSearch(String value) {
    if (state.search == value) return;
    state = state.copyWith(search: value);
  }

  void setFilter(LibraryFilter filter) {
    if (state.filter == filter) return;
    state = state.copyWith(filter: filter);
  }

  void setSort(LibrarySort sort) {
    if (state.sort == sort) return;
    state = state.copyWith(sort: sort);
  }
}

final NotifierProvider<LibraryQueryController, LibraryQuery>
    libraryQueryProvider =
    NotifierProvider<LibraryQueryController, LibraryQuery>(
  LibraryQueryController.new,
);

/// A new event means some write landed; the shelf re-runs its query.
final StreamProvider<void> libraryChangesProvider = StreamProvider<void>(
  (ref) => ref.watch(repositoryProvider).changes,
);

final FutureProvider<List<LibraryEntry>> libraryProvider =
    FutureProvider<List<LibraryEntry>>((ref) async {
  ref.watch(libraryChangesProvider);
  final repository = ref.watch(repositoryProvider);
  return repository.library(ref.watch(libraryQueryProvider));
});

final FutureProvider<List<ContinueEntry>> continueProvider =
    FutureProvider<List<ContinueEntry>>((ref) async {
  ref.watch(libraryChangesProvider);
  return ref.watch(repositoryProvider).continueReading();
});

/// Re-read after every write, including the one the manager makes per page.
final FutureProvider<List<DownloadTask>> downloadsProvider =
    FutureProvider<List<DownloadTask>>((ref) async {
  ref.watch(libraryChangesProvider);
  return ref.watch(repositoryProvider).downloads();
});

typedef BrowseKey = ({String sourceId, String query});

/// One provider for both the landing page and a search. Splitting them meant
/// the screen watched two futures and guessed which one was current.
final browseProvider = FutureProvider.family<List<Media>, BrowseKey>((
  ref,
  key,
) async {
  final source = ref.watch(sourceRegistryProvider).byId(key.sourceId);
  if (source == null) return const <Media>[];
  final query = key.query.trim();
  return query.isEmpty ? source.popular() : source.search(query);
});

/// What the front door shows: the live catalogue of every enabled source,
/// merged and de-duplicated by title.
///
/// Home used to show the bundled guide, which is honest but looks like a demo.
/// This walks the real sources instead, one failure at a time, and only falls
/// back to the guide when nothing answered — offline, or every source down.
class DiscoverFeed {
  const DiscoverFeed({required this.works, required this.live});

  final List<Media> works;

  /// False when the guide stood in for the live catalogue.
  final bool live;
}

final FutureProvider<DiscoverFeed> discoverProvider =
    FutureProvider<DiscoverFeed>((ref) async {
  final registry = ref.watch(sourceRegistryProvider);
  final works = <Media>[];
  final seen = <String>{};

  for (final source in registry.all) {
    if (source.id == DemoSource.sourceId) continue;
    try {
      final page = await source.popular();
      for (final media in page) {
        final key = '${media.title.toLowerCase().trim()}|${media.kind.name}';
        if (seen.add(key)) works.add(media);
      }
    } catch (_) {
      // One dead source must not empty the front door.
    }
  }

  if (works.isEmpty) {
    return DiscoverFeed(
      works: await const DemoSource().popular(),
      live: false,
    );
  }
  return DiscoverFeed(works: List.unmodifiable(works.take(40)), live: true);
});

/// One search box over every installed source. Sources answer in parallel, so
/// a slow pack cannot hold back the catalogue; a failure only removes that
/// source's rows.
final searchAllProvider =
    FutureProvider.family<List<Media>, String>((ref, rawQuery) async {
  final query = rawQuery.trim();
  if (query.isEmpty) return const <Media>[];
  final registry = ref.watch(sourceRegistryProvider);
  final pages = await Future.wait(<Future<List<Media>>>[
    for (final source in registry.all)
      if (source.id != DemoSource.sourceId)
        source.search(query).catchError((Object _) => const <Media>[]),
  ]);

  final merged = <Media>[];
  final seen = <String>{};
  for (final page in pages) {
    for (final media in page) {
      final key = '${media.title.toLowerCase().trim()}|${media.kind.name}';
      if (seen.add(key)) merged.add(media);
    }
  }
  return List.unmodifiable(merged.take(60));
});

typedef SeriesKey = ({String sourceId, String url});

class SeriesData {
  const SeriesData({
    required this.media,
    required this.units,
    required this.progress,
  });

  final Media media;
  final List<MediaUnit> units;
  final Map<String, UnitProgress> progress;
}

final seriesProvider = FutureProvider.family<SeriesData, SeriesKey>((
  ref,
  key,
) async {
  final repository = ref.watch(repositoryProvider);
  final source = ref.watch(sourceRegistryProvider).byId(key.sourceId);
  if (source == null) {
    throw StateError('This source is not installed: ${key.sourceId}');
  }

  final stored = await repository.mediaById(mediaIdOf(key.sourceId, key.url));

  // A deep link can arrive before the work was ever listed on this device.
  // Starting from a placeholder lets the source fill it in instead of showing
  // an error page for a work the person can plainly see.
  var media = stored ??
      Media(
        ref: SourceRef(key.sourceId, key.url),
        title: key.url,
        kind: MediaKind.manga,
      );
  try {
    media = await source.details(media);
    await repository.saveMedia(media);
  } catch (_) {
    // A details request is an enrichment. The listing data already on screen is
    // enough to open the work and read its chapters.
  }

  final units = await source.units(media);
  await repository.saveUnits(units);

  final progress = <String, UnitProgress>{};
  for (final unit in units) {
    final saved = await repository.progressFor(unit.id);
    if (saved != null) progress[unit.id] = saved;
  }

  return SeriesData(media: media, units: units, progress: progress);
});

typedef UnitKey = ({String sourceId, String url, String unitUrl});
typedef ReaderKey = UnitKey;

/// The catalogue rows every reader and player needs, resolved once.
///
/// Both screens arrive with the same three strings (source, work, unit) and
/// both must fail the same way when a deep link points at something this
/// device has never stored.
class ResolvedUnit {
  const ResolvedUnit({
    required this.media,
    required this.unit,
    required this.source,
  });

  final Media media;
  final MediaUnit unit;
  final SourceAdapter source;
}

Future<ResolvedUnit> _resolveUnit(
  LibraryRepository repository,
  SourceRegistry registry,
  UnitKey key,
) async {
  final source = registry.byId(key.sourceId);
  if (source == null) {
    throw StateError('This source is not installed: ${key.sourceId}');
  }

  final media = await repository.mediaById(mediaIdOf(key.sourceId, key.url));
  if (media == null) {
    throw StateError('This work is not in the local catalogue yet.');
  }

  final units = await repository.unitsFor(media.id);
  final unit = units.firstWhere(
    (candidate) => candidate.url == key.unitUrl,
    orElse: () => throw StateError('This unit is not in the local catalogue.'),
  );

  return ResolvedUnit(media: media, unit: unit, source: source);
}

class ReaderData {
  const ReaderData({
    required this.media,
    required this.unit,
    required this.resources,
    required this.progress,
    this.offline = false,
  });

  final Media media;
  final MediaUnit unit;
  final List<MediaResource> resources;
  final UnitProgress? progress;

  /// True when the pages came from a finished download, not a source.
  final bool offline;
}

final readerProvider = FutureProvider.family<ReaderData, ReaderKey>((
  ref,
  key,
) async {
  final repository = ref.watch(repositoryProvider);
  final resolved = await _resolveUnit(
    repository,
    ref.watch(sourceRegistryProvider),
    key,
  );
  final media = resolved.media;
  final unit = resolved.unit;
  final source = resolved.source;

  final task = await repository.downloadFor(unit.id);
  if (task != null && task.isFinished && task.directory != null) {
    final local = await downloadedPages(task.directory!);
    if (local.isNotEmpty) {
      return ReaderData(
        media: media,
        unit: unit,
        resources: local,
        progress: await repository.progressFor(unit.id),
        offline: true,
      );
    }
  }

  List<MediaResource> resources;
  try {
    resources = await source.resources(unit);
  } catch (error) {
    // A paused or partially written download is still better than an error
    // page when the network is the thing that failed.
    if (task?.directory == null) rethrow;
    final local = await downloadedPages(task!.directory!);
    if (local.isEmpty) rethrow;
    return ReaderData(
      media: media,
      unit: unit,
      resources: local,
      progress: await repository.progressFor(unit.id),
      offline: true,
    );
  }

  return ReaderData(
    media: media,
    unit: unit,
    resources: resources,
    progress: await repository.progressFor(unit.id),
  );
});

class WatchData {
  const WatchData({
    required this.media,
    required this.unit,
    required this.stream,
    required this.progress,
    this.sample = false,
  });

  final Media media;
  final MediaUnit unit;
  final VideoResource stream;
  final UnitProgress? progress;

  /// True for the bundled guide, whose episodes are public-domain sample films
  /// rather than licensed content. The player says so instead of pretending.
  final bool sample;
}

typedef WatchKey = UnitKey;

/// Resolves the one stream an episode plays. A source may return several
/// resources (trailers, alternate qualities); the player takes the first video
/// and leaves the rest to a future quality picker.
final watchProvider = FutureProvider.family<WatchData, WatchKey>((
  ref,
  key,
) async {
  final repository = ref.watch(repositoryProvider);
  final resolved = await _resolveUnit(
    repository,
    ref.watch(sourceRegistryProvider),
    key,
  );

  final resources = await resolved.source.resources(resolved.unit);
  VideoResource? stream;
  for (final resource in resources) {
    if (resource is VideoResource) {
      stream = resource;
      break;
    }
  }
  if (stream == null) {
    throw StateError('This unit has no playable stream.');
  }

  return WatchData(
    media: resolved.media,
    unit: resolved.unit,
    stream: stream,
    progress: await repository.progressFor(resolved.unit.id),
    sample: resolved.source.id == DemoSource.sourceId,
  );
});

/// The stored row for one work, re-read after every write.
///
/// The series screen gets its data from a provider that also talks to the
/// source; a plan change or a new list must not trigger a network refresh, so
/// it watches this tiny query instead.
final mediaByIdProvider = FutureProvider.family<Media?, String>((ref, id) async {
  ref.watch(libraryChangesProvider);
  return ref.watch(repositoryProvider).mediaById(id);
});

/// The numbers on the profile card: shelf totals plus the local activity log.
///
/// Progress-derived numbers come from the same query the shelf uses, so the
/// statistics screen can never disagree with what the library shows.
final FutureProvider<ReadingStats> readingStatsProvider =
    FutureProvider<ReadingStats>((ref) async {
  ref.watch(libraryChangesProvider);
  final repository = ref.watch(repositoryProvider);
  final entries = await repository.library();
  final activity = await repository.activity();
  var units = 0;
  var completed = 0;
  for (final entry in entries) {
    units += entry.totalUnits;
    completed += entry.completedUnits;
  }
  return ReadingStats.from(
    activity: activity,
    works: entries.length,
    units: units,
    completedUnits: completed,
    today: DateTime.now(),
  );
});

/// Export and restore live here so the screen only deals with text.
class BackupController {
  BackupController(this._ref);

  final Ref _ref;

  Future<({String text, LibrarySnapshot snapshot})> export() async {
    final snapshot = await snapshotOf(_ref.read(repositoryProvider));
    final sources = _ref.read(sourcePacksProvider.notifier).exportAll();
    return (
      text: LibraryBackup.encode(snapshot, sources: sources),
      snapshot: snapshot,
    );
  }

  /// Restores the shelf and reinstalls the packs the backup was made with.
  Future<RestoreReport> restore(String raw) async {
    final document = LibraryBackup.decodeDocument(raw);
    if (document.sources.isNotEmpty) {
      _ref.read(sourcePacksProvider.notifier).addAll(document.sources);
    }
    return restoreInto(_ref.read(repositoryProvider), document.snapshot);
  }
}

final Provider<BackupController> backupControllerProvider =
    Provider<BackupController>(BackupController.new);

/// Bulk refresh of the shelf.
///
/// One work at a time with a gap between requests: a source is somebody else's
/// server, and a shelf of forty works refreshed in parallel is how an IP gets
/// blocked. A failure is counted, never fatal.
class RefreshProgress {
  const RefreshProgress({
    this.running = false,
    this.finished = false,
    this.total = 0,
    this.done = 0,
    this.failed = 0,
  });

  final bool running;
  final bool finished;
  final int total;
  final int done;
  final int failed;

  int get settled => done + failed;

  double get fraction => total == 0 ? 0 : (settled / total).clamp(0.0, 1.0);
}

class LibraryRefreshController extends Notifier<RefreshProgress> {
  /// Long enough to be polite, short enough that forty works take under twenty
  /// seconds.
  static const Duration _gap = Duration(milliseconds: 400);

  @override
  RefreshProgress build() => const RefreshProgress();

  void clear() {
    if (state.running) return;
    state = const RefreshProgress();
  }

  Future<void> refreshAll() async {
    if (state.running) return;
    final repository = ref.read(repositoryProvider);
    final registry = ref.read(sourceRegistryProvider);
    final entries = await repository.library();
    if (entries.isEmpty) {
      state = const RefreshProgress(finished: true);
      return;
    }

    state = RefreshProgress(running: true, total: entries.length);
    var done = 0;
    var failed = 0;
    for (final entry in entries) {
      final source = registry.byId(entry.media.ref.sourceId);
      if (source == null) {
        failed++;
      } else {
        try {
          final fresh = await source.details(entry.media);
          await repository.saveMedia(fresh);
          await repository.saveUnits(await source.units(fresh));
          done++;
        } catch (_) {
          // A dead source must not stop the rest of the shelf.
          failed++;
        }
      }
      state = RefreshProgress(
        running: true,
        total: entries.length,
        done: done,
        failed: failed,
      );
      await Future<void>.delayed(_gap);
    }
    state = RefreshProgress(
      finished: true,
      total: entries.length,
      done: done,
      failed: failed,
    );
  }
}

final NotifierProvider<LibraryRefreshController, RefreshProgress>
    libraryRefreshProvider =
    NotifierProvider<LibraryRefreshController, RefreshProgress>(
  LibraryRefreshController.new,
);

/// Where the encrypted copy lives. The passphrase is deliberately absent: it is
/// typed per upload, kept in a controller, and never written to disk.
class SyncSettings {
  const SyncSettings({
    this.url = '',
    this.username = '',
    this.password = '',
  });

  final String url;
  final String username;
  final String password;

  bool get isConfigured => url.trim().isNotEmpty;

  SyncSettings copyWith({String? url, String? username, String? password}) {
    return SyncSettings(
      url: url ?? this.url,
      username: username ?? this.username,
      password: password ?? this.password,
    );
  }
}

class SyncSettingsController extends Notifier<SyncSettings> {
  static const String _urlKey = 'sync_url';
  static const String _userKey = 'sync_user';
  static const String _passwordKey = 'sync_password';

  @override
  SyncSettings build() {
    final preferences = ref.watch(preferencesProvider);
    return SyncSettings(
      url: preferences?.getString(_urlKey) ?? '',
      username: preferences?.getString(_userKey) ?? '',
      password: preferences?.getString(_passwordKey) ?? '',
    );
  }

  void save(SyncSettings next) {
    final preferences = ref.read(preferencesProvider);
    unawaited(preferences?.setString(_urlKey, next.url.trim()));
    unawaited(preferences?.setString(_userKey, next.username.trim()));
    unawaited(preferences?.setString(_passwordKey, next.password));
    state = next;
  }
}

final NotifierProvider<SyncSettingsController, SyncSettings>
    syncSettingsProvider =
    NotifierProvider<SyncSettingsController, SyncSettings>(
  SyncSettingsController.new,
);

/// Upload and download share one controller so the screen only deals with
/// strings, errors and counts.
class SyncController {
  SyncController(this._ref);

  final Ref _ref;

  /// Seals the current backup and puts it on the server.
  Future<({int works, int units, int sources})> upload(
    String passphrase,
  ) async {
    final settings = _ref.read(syncSettingsProvider);
    final sync = _client(settings);
    final backup = await _ref.read(backupControllerProvider).export();
    final sealed = await SyncCipher.seal(
      plaintext: backup.text,
      passphrase: passphrase,
    );
    await sync.upload(sealed);
    final document = LibraryBackup.decodeDocument(backup.text);
    return (
      works: document.snapshot.libraryCount,
      units: document.snapshot.units.length,
      sources: document.sources.length,
    );
  }

  /// Pulls the server copy, merges it, and reinstalls its packs.
  Future<({int works, int units, int sources})> download(
    String passphrase,
  ) async {
    final settings = _ref.read(syncSettingsProvider);
    final sync = _client(settings);
    final sealed = await sync.download();
    if (sealed == null) {
      throw const SyncException('There is nothing on the server yet.');
    }
    final raw = await SyncCipher.open(envelope: sealed, passphrase: passphrase);
    final document = LibraryBackup.decodeDocument(raw);
    final sources = document.sources.isEmpty
        ? 0
        : _ref.read(sourcePacksProvider.notifier).addAll(document.sources);
    await restoreInto(_ref.read(repositoryProvider), document.snapshot);
    return (
      works: document.snapshot.libraryCount,
      units: document.snapshot.units.length,
      sources: sources,
    );
  }

  WebDavSync _client(SyncSettings settings) {
    final sync = WebDavSync.fromSettings(
      url: settings.url,
      username: settings.username,
      password: settings.password,
      client: _ref.read(httpClientProvider),
    );
    if (sync == null) {
      throw const SyncException('Use an https:// folder URL.');
    }
    return sync;
  }
}

final Provider<SyncController> syncControllerProvider =
    Provider<SyncController>(SyncController.new);
