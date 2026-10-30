import 'dart:async';
import 'dart:io';

import 'package:best_data/best_data.dart';
import 'package:best_domain/best_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

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
  return SourceRegistry.fixed(<SourceAdapter>[
    const DemoSource(),
    MangaDexSource(client: client),
    for (final pack in packs) JsonSourceAdapter(pack: pack, client: client),
  ]);
});

class AppSettings {
  const AppSettings({this.languageCode, this.themeMode = ThemeMode.system});

  /// `null` follows the system locale.
  final String? languageCode;
  final ThemeMode themeMode;

  AppSettings copyWith({
    String? languageCode,
    bool clearLanguage = false,
    ThemeMode? themeMode,
  }) {
    return AppSettings(
      languageCode: clearLanguage ? null : (languageCode ?? this.languageCode),
      themeMode: themeMode ?? this.themeMode,
    );
  }
}

class SettingsController extends Notifier<AppSettings> {
  static const String _languageKey = 'language';
  static const String _themeKey = 'theme';

  @override
  AppSettings build() {
    final preferences = ref.watch(preferencesProvider);
    return AppSettings(
      languageCode: preferences?.getString(_languageKey),
      themeMode: _readTheme(preferences?.getString(_themeKey)),
    );
  }

  void setLanguage(String? code) {
    final preferences = ref.read(preferencesProvider);
    if (code == null) {
      unawaited(preferences?.remove(_languageKey));
    } else {
      unawaited(preferences?.setString(_languageKey, code));
    }
    state = AppSettings(languageCode: code, themeMode: state.themeMode);
  }

  void setThemeMode(ThemeMode mode) {
    unawaited(ref.read(preferencesProvider)?.setString(_themeKey, mode.name));
    state = AppSettings(languageCode: state.languageCode, themeMode: mode);
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

typedef ReaderKey = ({String sourceId, String url, String unitUrl});

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
  final source = ref.watch(sourceRegistryProvider).byId(key.sourceId);
  if (source == null) {
    throw StateError('This source is not installed: ${key.sourceId}');
  }

  final media = await repository.mediaById(
    mediaIdOf(key.sourceId, key.url),
  );
  if (media == null) {
    throw StateError('This work is not in the local catalogue yet.');
  }

  final units = await repository.unitsFor(media.id);
  final unit = units.firstWhere(
    (candidate) => candidate.url == key.unitUrl,
    orElse: () => throw StateError('This unit is not in the local catalogue.'),
  );

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
