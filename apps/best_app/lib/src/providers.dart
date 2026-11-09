import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:best_data/best_data.dart';
import 'package:best_domain/best_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'download/background_download_client.dart';
import 'backup/backup_file_sharer.dart';
import 'backup/backup_file_store.dart';
import 'extension_host.dart';
import 'network.dart';
import 'ocr/ocr_client.dart';
import 'security/biometric_client.dart';
import 'l10n/generated/app_localizations.dart';

// Keep existing settings-only imports source-compatible after moving these
// framework-free choices into the domain layer.
export 'package:best_domain/best_domain.dart'
    show
        ReaderMode,
        ReaderDirection,
        ReaderFit,
        ReaderBackground,
        ReaderSpreadMode;

/// Replaced in `main()` after the database is open. A provider that throws
/// until it is overridden is better than a nullable global that fails later.
final Provider<LibraryRepository> repositoryProvider =
    Provider<LibraryRepository>(
  (ref) => throw StateError('repositoryProvider must be overridden in main().'),
);

final Provider<BiometricClient> biometricClientProvider =
    Provider<BiometricClient>((ref) => const BiometricClient());

final backupFileSharerProvider =
    Provider<BackupFileSharer>((ref) => const BackupFileSharer());

final backupFileStoreProvider =
    Provider<BackupFileStore>((ref) => const BackupFileStore());

final Provider<OcrClient> ocrClientProvider = Provider<OcrClient>((ref) {
  return OcrClient(repository: ref.watch(repositoryProvider));
});

final Provider<BackgroundDownloadClient> backgroundDownloadClientProvider =
    Provider<BackgroundDownloadClient>(
  (ref) => const BackgroundDownloadClient(),
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
    registry: SourceRegistry(
      () => ref.read(sourceRegistryProvider).all,
      fallback: (id) => ref.read(sourceRegistryProvider).byId(id),
    ),
    client: ref.watch(httpClientProvider),
    root: ref.watch(downloadRootProvider),
  );
  ref.onDispose(manager.dispose);

  if (Platform.isAndroid) {
    manager.prepareSources = () async {
      // A cold worker must not confuse a still-loading extension catalogue
      // with an uninstalled source.
      try {
        await ref.read(extensionCatalogProvider.future)
            .timeout(const Duration(seconds: 20));
      } catch (_) {
        // DownloadManager reports an unavailable source honestly, per unit.
      }
      if (!ref.mounted) return;
      if (ref.read(suwayomiClientProvider) != null) {
        try {
          await ref.read(suwayomiSourcesProvider.future)
              .timeout(const Duration(seconds: 20));
        } catch (_) {}
      }
    };
  }

  // The queue obeys two app-level rules: the Wi-Fi-only setting and the storage
  // cap. Both are read through closures so changing a setting does not rebuild
  // the manager (and therefore does not drop a download in flight).
  void applyPolicy() {
    final settings = ref.read(settingsProvider);
    final network = ref.read(networkProvider).value ?? NetworkKind.unknown;
    manager.mayDownload =
        () => !settings.wifiOnly || network != NetworkKind.mobile;
    manager.storageCap = () => settings.storageCapGb * 1024 * 1024 * 1024;
    manager.maxConcurrent = () => settings.downloadConcurrency;
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

/// Notification commands and display snapshots around the existing manager.
/// There is no parallel queue, file store, database writer or polling timer.
class BackgroundDownloadsController extends Notifier<BackgroundDownloadState> {
  StreamSubscription<void>? _subscription;
  bool _publishing = false;
  bool _again = false;
  Completer<void>? _publicationDone;
  Future<void>? _startup;

  Future<void> get ready => _startup ?? Future<void>.value();

  @override
  BackgroundDownloadState build() {
    final client = ref.watch(backgroundDownloadClientProvider);
    ref.onDispose(() {
      unawaited(_subscription?.cancel());
      client.dispose();
    });
    if (!client.isSupported) return const BackgroundDownloadState();
    _startup = _start(client);
    unawaited(_startup);
    return const BackgroundDownloadState();
  }

  Future<void> _start(BackgroundDownloadClient client) async {
    final repository = ref.read(repositoryProvider);
    final manager = ref.read(downloadManagerProvider);
    manager.onDrainChanged = () => unawaited(_publish());
    ref.onDispose(() => manager.onDrainChanged = null);
    try {
      final available = await client.initialize(
        onAction: notificationAction,
        onFailure: (message) {
          if (ref.mounted) {
            state = BackgroundDownloadState(
              error: message, openRequests: state.openRequests,
            );
          }
        },
      );
      if (!ref.mounted) return;
      state = BackgroundDownloadState(available: available,
          openRequests: state.openRequests);
      _subscription = repository.changes.listen((_) => unawaited(_publish()));
      ref.listen(settingsProvider, (_, next) => unawaited(_publish()));
      ref.listen(networkProvider, (_, next) => unawaited(_publish()));
      await _publish();
    } catch (error) {
      if (ref.mounted) {
        state = BackgroundDownloadState(
            error: '$error', openRequests: state.openRequests);
      }
    }
  }

  Future<void> _publish() async {
    if (!ref.mounted) return;
    if (_publishing) {
      _again = true;
      await _publicationDone?.future;
      return;
    }
    _publishing = true;
    _publicationDone = Completer<void>();
    try {
      do {
        _again = false;
        final tasks = await ref.read(repositoryProvider).downloads();
        if (!ref.mounted) return;
        final pending = tasks.where((task) => task.isActive).toList();
        pending.sort((a, b) {
          if (a.status != b.status) {
            if (a.status == DownloadStatus.running) return -1;
            if (b.status == DownloadStatus.running) return 1;
          }
          return a.updatedAt.compareTo(b.updatedAt);
        });
        final settings = ref.read(settingsProvider);
        final language = settings.languageCode ??
            WidgetsBinding.instance.platformDispatcher.locale.languageCode;
        final l10n = await AppLocalizations.delegate.load(
            Locale(language == 'ar' ? 'ar' : 'en'));
        if (!ref.mounted) return;
        final current = pending.isEmpty ? null : pending.first;
        final busy = ref.read(downloadManagerProvider).isDraining;
        final accepted = await ref.read(backgroundDownloadClientProvider).publish(
          BackgroundDownloadSnapshot(
            pending: pending.isNotEmpty || busy,
            wifiOnly: settings.wifiOnly,
            title: current?.mediaTitle ?? l10n.downloadsTitle,
            detail: current == null
                ? (busy ? l10n.downloadFinishingRequest : l10n.downloadDone) :
                '${current.unitTitle} · ${l10n.downloadProgress(current.completed, current.total)}',
            unitId: current?.unitId ?? '',
            progress: current?.completed ?? 0,
            total: current?.total ?? 0,
            pauseLabel: l10n.downloadPauseAll,
          ),
        );
        if (!accepted && ref.mounted) {
          state = BackgroundDownloadState(error: 'Background service unavailable',
              openRequests: state.openRequests);
        }
      } while (_again && ref.mounted);
    } catch (error) {
      if (ref.mounted) {
        state = BackgroundDownloadState(error: '$error',
            openRequests: state.openRequests);
      }
    } finally {
      _publishing = false;
      _publicationDone?.complete();
      _publicationDone = null;
    }
  }

  Future<void> notificationAction(String action, String? unitId) async {
    if (!ref.mounted) return;
    if (action == 'open') {
      state = BackgroundDownloadState(available: state.available,
          error: state.error, openRequests: state.openRequests + 1);
      return;
    }
    if (!const {'pause', 'stop', 'resume'}.contains(action)) return;
    final manager = ref.read(downloadManagerProvider);
    final tasks = await ref.read(repositoryProvider).downloads();
    for (final task in tasks) {
      if (!ref.mounted) return;
      if (unitId != null && unitId != task.unitId) continue;
      if (action == 'resume' && unitId != null && task.isPaused) {
        await manager.resume(task.unitId);
      } else if (action != 'resume' && task.isActive) {
        // Stop is non-destructive: the saved prefix and row stay available.
        await manager.pause(task.unitId);
      }
    }
    await _publish();
  }
}

final backgroundDownloadsProvider = NotifierProvider<BackgroundDownloadsController,
    BackgroundDownloadState>(BackgroundDownloadsController.new);

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
  List<String> exportAll() => [for (final pack in state) pack.encode()];

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

/// `null` when no server is configured, or when the address is not a URL.
final Provider<SuwayomiClient?> suwayomiClientProvider =
    Provider<SuwayomiClient?>((ref) {
  final url = ref.watch(settingsProvider).suwayomiUrl;
  if (url == null || url.trim().isEmpty) return null;
  try {
    return SuwayomiClient(
      baseUrl: url,
      client: ref.watch(httpClientProvider),
    );
  } on SuwayomiException {
    return null;
  }
});

/// What the server hosts. An unreachable server yields an empty list instead of
/// breaking the app: the built-in catalogues keep working.
final FutureProvider<List<SuwayomiSourceInfo>> suwayomiSourcesProvider =
    FutureProvider<List<SuwayomiSourceInfo>>((ref) async {
  final client = ref.watch(suwayomiClientProvider);
  if (client == null) return const <SuwayomiSourceInfo>[];
  try {
    final sources = await client.sources();
    // Adult sources stay out of a general catalogue; a reader who wants them
    // can point Best at a server that only serves them.
    return List.unmodifiable(sources.where((source) => !source.nsfw));
  } catch (_) {
    return const <SuwayomiSourceInfo>[];
  }
});

/// The Kotlin extension host. Extensions are programs, so they live on the
/// native side and this is the only door to them.
final Provider<ExtensionHost> extensionHostProvider =
    Provider<ExtensionHost>((ref) => ExtensionHost());

final Provider<ExtensionInstaller> extensionInstallerProvider =
    Provider<ExtensionInstaller>((ref) {
  final client = ref.watch(httpClientProvider);
  return ExtensionInstaller(
    host: ref.watch(extensionHostProvider),
    repository: ExtensionRepository(
      indexUrl: ExtensionRepository.defaultIndexUrl,
      client: client,
      preferences: ref.watch(preferencesProvider),
    ),
    // Anime bundles come from a different index and link against a different
    // runtime, but they install into the same private folder and show up in the
    // same picker.
    animeRepository: ExtensionRepository(
      indexUrl: ExtensionRepository.defaultAnimeIndexUrl,
      client: client,
      preferences: ref.watch(preferencesProvider),
    ),
    preferences: ref.watch(preferencesProvider),
  );
});

/// Every source the installed extension APKs expose.
///
/// Inventory reads never install anything on a first launch.
final FutureProvider<ExtensionCatalog> extensionCatalogProvider =
    FutureProvider<ExtensionCatalog>((ref) async {
  final host = ref.watch(extensionHostProvider);
  if (!host.isAvailable) return const ExtensionCatalog.empty();
  return host.catalog();
});

final extensionDirectoryProvider = FutureProvider<ExtensionDirectory>(
    (ref) => ref.watch(extensionInstallerProvider).directory());

class ExtensionAutoUpdatesController extends Notifier<bool> {
  @override
  bool build() =>
      ref.watch(preferencesProvider)?.getBool('extension_auto_updates') ?? true;
  void setEnabled(bool enabled) {
    unawaited(ref
        .read(preferencesProvider)
        ?.setBool('extension_auto_updates', enabled));
    state = enabled;
  }
}

final extensionAutoUpdatesProvider =
    NotifierProvider<ExtensionAutoUpdatesController, bool>(
        ExtensionAutoUpdatesController.new);

class ExtensionUpdatesController
    extends Notifier<AsyncValue<ExtensionUpdateResult>> {
  @override
  AsyncValue<ExtensionUpdateResult> build() =>
      const AsyncData(ExtensionUpdateResult());
  Future<void> check({bool force = false}) async {
    if (state.isLoading) return;
    state = const AsyncLoading();
    try {
      final result =
          await ref.read(extensionInstallerProvider).checkUpdates(force: force);
      if (!ref.mounted) return;
      state = AsyncData(result);
      if (result.updated > 0) ref.invalidate(extensionCatalogProvider);
      if (result.checked) ref.invalidate(extensionDirectoryProvider);
    } catch (error, stack) {
      if (ref.mounted) state = AsyncError(error, stack);
    }
  }
}

final extensionUpdatesProvider = NotifierProvider<ExtensionUpdatesController,
    AsyncValue<ExtensionUpdateResult>>(ExtensionUpdatesController.new);

final Provider<SourceRegistry> sourceRegistryProvider =
    Provider<SourceRegistry>((ref) {
  final client = ref.watch(httpClientProvider);
  final packs = ref.watch(sourcePacksProvider);
  // The catalogue follows the interface language: an Arabic reader gets the
  // Arabic scanlations first, and English stays as the fallback chapter track.
  final settings = ref.watch(settingsProvider);
  final language = settings.languageCode ??
      WidgetsBinding.instance.platformDispatcher.locale.languageCode;
  // Only chosen sites are discoverable. The guide remains an explicit offline
  // demo, and the legacy MangaDex API is a by-id fallback for existing libraries.
  final suwayomi = ref.watch(suwayomiClientProvider);
  final remoteSources =
      ref.watch(suwayomiSourcesProvider).value ?? const <SuwayomiSourceInfo>[];
  final extensionHost = ref.watch(extensionHostProvider);
  final extensions = ref.watch(extensionCatalogProvider).value ??
      const ExtensionCatalog.empty();
  final packageCounts = <String, int>{};
  for (final info in extensions.sources) {
    packageCounts[info.packageName] =
        (packageCounts[info.packageName] ?? 0) + 1;
  }

  return SourceRegistry.fixed(<SourceAdapter>[
    // A configured server leads: its sources are the ones the reader chose to
    // bring, and they update with the server's extensions.
    if (suwayomi != null)
      for (final info in remoteSources)
        SuwayomiSource(client: suwayomi, info: info),
    for (final pack in packs) JsonSourceAdapter(pack: pack, client: client),
    // Installed extensions sit beside the built-in catalogues: they are real
    // sources the reader brought, and a library entry must keep resolving to the
    // same adapter across launches.
    // An extension like MangaDex exposes one source per language. Showing all of
    // them would bury the catalogue under forty identical rows, so the shelf
    // keeps the reader's language, the language-neutral bundles, and any
    // single-source bundle the reader activated on purpose.
    //
    // Anime bundles remain visible whatever the interface language is.
    for (final info in extensions.sources.where((info) =>
        info.isAnime ||
        extensionSourceVisible(
          sourceLanguage: info.language,
          interfaceLanguage: language,
          packageSourceCount: packageCounts[info.packageName] ?? 1,
        )))
      ExtensionSourceAdapter(host: extensionHost, info: info),
  ],
      fallback: (id) {
        if (id == 'mangadex') {
          return MangaDexSource(
              client: client, language: language == 'ar' ? 'ar' : 'en');
        }
        // Display-language filtering must not strand stored works/downloads.
        for (final info in extensions.sources) {
          if (id == 'mihon:${info.sourceId}') {
            return ExtensionSourceAdapter(host: extensionHost, info: info);
          }
        }
        if (suwayomi != null) {
          for (final info in remoteSources) {
            final source = SuwayomiSource(client: suwayomi, info: info);
            if (source.id == id) return source;
          }
        }
        return null;
      });
});

class AppSettings {
  const AppSettings({
    this.languageCode,
    this.themeMode = ThemeMode.system,
    this.wifiOnly = false,
    this.storageCapGb = 0,
    this.suwayomiUrl,
    this.readerMode = ReaderMode.paged,
    this.readerDirection = ReaderDirection.ltr,
    this.readerFit = ReaderFit.screen,
    this.readerBackground = ReaderBackground.black,
    this.readerTapZones = true,
    this.readerTapZoneSize = ReaderTapZoneSize.medium,
    this.readerKeepAwake = true,
    this.readerPreload = true,
    this.readerWebtoonGap = 0,
    this.readerFilterMode = 'none',
    this.readerBrightness = 0,
    this.readerSpreadMode = ReaderSpreadMode.single,
    this.readerCoverAlone = true,
    this.readerAutoAdvance = true,
    this.ocrTranslationEnabled = false,
    this.biometricLockEnabled = false,
    this.autoRefreshLibrary = true,
    this.refreshIntervalHours = 12,
    this.updateWifiOnly = true,
    this.downloadConcurrency = 1,
  });

  /// `null` follows the system locale.
  final String? languageCode;
  final ThemeMode themeMode;

  /// Downloads wait for Wi-Fi. Off by default: a setting that silently stops a
  /// download on a first launch is worse than a small data bill.
  final bool wifiOnly;

  /// Offline storage cap in gigabytes. `0` means no cap.
  final int storageCapGb;

  /// A Suwayomi server the reader runs, e.g. `http://192.168.1.20:4567`.
  /// `null` means no server: Best stays on its built-in catalogues.
  final String? suwayomiUrl;

  /// How a chapter is laid out. Paged suits manga; vertical joins the pages
  /// into one scroll, which is how manhwa and webtoons are drawn.
  final ReaderMode readerMode;

  /// Which way a paged chapter is read. Manga is bound right to left, so the
  /// first page sits on the right and a forward swipe moves leftwards.
  final ReaderDirection readerDirection;

  /// How a paged page fills the viewport. Vertical mode always fits the width.
  final ReaderFit readerFit;

  /// The canvas behind a page. Black is the classic reader; sepia and white
  /// help in daylight, charcoal softens the contrast of pure black.
  final ReaderBackground readerBackground;

  /// Tapping the left or right side turns a page; the middle toggles chrome.
  /// Off, any tap only toggles chrome.
  final bool readerTapZones;

  /// How wide the page-turn edges are in paged mode.
  final ReaderTapZoneSize readerTapZoneSize;

  /// Keep the display awake while a chapter is open.
  final bool readerKeepAwake;

  /// Warm the image cache for the pages around the one being read.
  final bool readerPreload;

  /// Extra space between pages in vertical/webtoon mode, in logical pixels.
  final int readerWebtoonGap;

  /// Persisted reader filter and dim level. The filter itself lives in
  /// `widgets/reader_color_filter.dart`; storing its name keeps this provider
  /// free of widget imports.
  final String readerFilterMode;
  final int readerBrightness;

  final ReaderSpreadMode readerSpreadMode;
  final bool readerCoverAlone;

  /// Finishing the last page and pushing past it opens the next chapter, the
  /// way Mihon and Komikku behave. Turning it off keeps the reader on the
  /// finished chapter until the reader chooses.
  final bool readerAutoAdvance;

  ReaderPreferences get readerPreferences => ReaderPreferences(
        mode: readerMode,
        direction: readerDirection,
        fit: readerFit,
        background: readerBackground,
        tapZones: readerTapZones,
        tapZoneSize: readerTapZoneSize,
        webtoonGap: readerWebtoonGap,
        filterMode: readerFilterMode,
        brightness: readerBrightness,
        spreadMode: readerSpreadMode,
        coverAlone: readerCoverAlone,
      );

  AppSettings withReaderPreferences(ReaderPreferences preferences) => copyWith(
        readerMode: preferences.mode,
        readerDirection: preferences.direction,
        readerFit: preferences.fit,
        readerBackground: preferences.background,
        readerTapZones: preferences.tapZones,
        readerTapZoneSize: preferences.tapZoneSize,
        readerWebtoonGap: preferences.webtoonGap,
        readerFilterMode: preferences.filterMode,
        readerBrightness: preferences.brightness,
        readerSpreadMode: preferences.spreadMode,
        readerCoverAlone: preferences.coverAlone,
      );

  /// Real-time offline OCR and translation overlay on manga pages.
  final bool ocrTranslationEnabled;

  /// Protects the app with biometrics / device passcode.
  final bool biometricLockEnabled;

  /// Refresh the shelf on launch/resume when the interval has elapsed.
  final bool autoRefreshLibrary;

  /// Hours between automatic shelf refreshes.
  final int refreshIntervalHours;

  /// Automatic refreshes wait for Wi-Fi. Manual refresh always runs.
  final bool updateWifiOnly;

  /// How many chapters the offline queue may fetch at once. One is the polite
  /// default; more is an explicit choice for a fast connection.
  final int downloadConcurrency;

  AppSettings copyWith({
    String? languageCode,
    bool clearLanguage = false,
    ThemeMode? themeMode,
    bool? wifiOnly,
    int? storageCapGb,
    String? suwayomiUrl,
    bool clearSuwayomi = false,
    ReaderMode? readerMode,
    ReaderDirection? readerDirection,
    ReaderFit? readerFit,
    ReaderBackground? readerBackground,
    bool? readerTapZones,
    ReaderTapZoneSize? readerTapZoneSize,
    bool? readerKeepAwake,
    bool? readerPreload,
    int? readerWebtoonGap,
    String? readerFilterMode,
    int? readerBrightness,
    ReaderSpreadMode? readerSpreadMode,
    bool? readerCoverAlone,
    bool? readerAutoAdvance,
    bool? ocrTranslationEnabled,
    bool? biometricLockEnabled,
    bool? autoRefreshLibrary,
    int? refreshIntervalHours,
    bool? updateWifiOnly,
    int? downloadConcurrency,
  }) {
    return AppSettings(
      languageCode: clearLanguage ? null : (languageCode ?? this.languageCode),
      themeMode: themeMode ?? this.themeMode,
      wifiOnly: wifiOnly ?? this.wifiOnly,
      storageCapGb: storageCapGb ?? this.storageCapGb,
      suwayomiUrl: clearSuwayomi ? null : (suwayomiUrl ?? this.suwayomiUrl),
      readerMode: readerMode ?? this.readerMode,
      readerDirection: readerDirection ?? this.readerDirection,
      readerFit: readerFit ?? this.readerFit,
      readerBackground: readerBackground ?? this.readerBackground,
      readerTapZones: readerTapZones ?? this.readerTapZones,
      readerTapZoneSize: readerTapZoneSize ?? this.readerTapZoneSize,
      readerKeepAwake: readerKeepAwake ?? this.readerKeepAwake,
      readerPreload: readerPreload ?? this.readerPreload,
      readerWebtoonGap: readerWebtoonGap ?? this.readerWebtoonGap,
      readerFilterMode: readerFilterMode ?? this.readerFilterMode,
      readerBrightness: readerBrightness ?? this.readerBrightness,
      readerSpreadMode: readerSpreadMode ?? this.readerSpreadMode,
      readerCoverAlone: readerCoverAlone ?? this.readerCoverAlone,
      readerAutoAdvance: readerAutoAdvance ?? this.readerAutoAdvance,
      ocrTranslationEnabled:
          ocrTranslationEnabled ?? this.ocrTranslationEnabled,
      biometricLockEnabled: biometricLockEnabled ?? this.biometricLockEnabled,
      autoRefreshLibrary: autoRefreshLibrary ?? this.autoRefreshLibrary,
      refreshIntervalHours: refreshIntervalHours ?? this.refreshIntervalHours,
      updateWifiOnly: updateWifiOnly ?? this.updateWifiOnly,
      downloadConcurrency: downloadConcurrency ?? this.downloadConcurrency,
    );
  }
}

class SettingsController extends Notifier<AppSettings> {
  static const String _languageKey = 'language';
  static const String _themeKey = 'theme';
  static const String _wifiOnlyKey = 'wifi_only';
  static const String _storageCapKey = 'storage_cap_gb';
  static const String _suwayomiKey = 'suwayomi_url';
  static const String _readerModeKey = 'reader_mode';
  static const String _readerDirectionKey = 'reader_direction';
  static const String _readerFitKey = 'reader_fit';
  static const String _readerBackgroundKey = 'reader_background';
  static const String _readerTapZonesKey = 'reader_tap_zones';
  static const String _readerTapZoneSizeKey = 'reader_tap_zone_size';
  static const String _readerKeepAwakeKey = 'reader_keep_awake';
  static const String _readerPreloadKey = 'reader_preload';
  static const String _readerWebtoonGapKey = 'reader_webtoon_gap';
  static const String _readerFilterModeKey = 'reader_filter_mode';
  static const String _readerBrightnessKey = 'reader_brightness';
  static const String _readerSpreadModeKey = 'reader_spread_mode';
  static const String _readerCoverAloneKey = 'reader_cover_alone';
  static const String _readerAutoAdvanceKey = 'reader_auto_advance';
  static const String _ocrTranslationKey = 'ocr_translation_enabled';
  static const String _biometricLockKey = 'biometric_lock_enabled';
  static const String _autoRefreshKey = 'library_auto_refresh';
  static const String _refreshIntervalKey = 'library_refresh_interval_hours';
  static const String _updateWifiOnlyKey = 'library_update_wifi_only';
  static const String _downloadConcurrencyKey = 'download_concurrency';

  @override
  AppSettings build() {
    final preferences = ref.watch(preferencesProvider);
    return AppSettings(
      languageCode: preferences?.getString(_languageKey),
      themeMode: _readTheme(preferences?.getString(_themeKey)),
      wifiOnly: preferences?.getBool(_wifiOnlyKey) ?? false,
      storageCapGb: preferences?.getInt(_storageCapKey) ?? 0,
      suwayomiUrl: preferences?.getString(_suwayomiKey),
      readerMode: ReaderMode.fromName(
        preferences?.getString(_readerModeKey),
      ),
      readerDirection: ReaderDirection.fromName(
        preferences?.getString(_readerDirectionKey),
      ),
      readerFit: ReaderFit.fromName(
        preferences?.getString(_readerFitKey),
      ),
      readerBackground: ReaderBackground.fromName(
        preferences?.getString(_readerBackgroundKey),
      ),
      readerTapZones: preferences?.getBool(_readerTapZonesKey) ?? true,
      readerTapZoneSize: ReaderTapZoneSize.fromName(
        preferences?.getString(_readerTapZoneSizeKey),
      ),
      readerKeepAwake: preferences?.getBool(_readerKeepAwakeKey) ?? true,
      readerPreload: preferences?.getBool(_readerPreloadKey) ?? true,
      readerWebtoonGap:
          (preferences?.getInt(_readerWebtoonGapKey) ?? 0).clamp(0, 32).toInt(),
      readerFilterMode: preferences?.getString(_readerFilterModeKey) ?? 'none',
      readerBrightness: preferences?.getInt(_readerBrightnessKey) ?? 0,
      readerSpreadMode: ReaderSpreadMode.fromName(
        preferences?.getString(_readerSpreadModeKey),
      ),
      readerCoverAlone: preferences?.getBool(_readerCoverAloneKey) ?? true,
      readerAutoAdvance: preferences?.getBool(_readerAutoAdvanceKey) ?? true,
      ocrTranslationEnabled: preferences?.getBool(_ocrTranslationKey) ?? false,
      biometricLockEnabled: preferences?.getBool(_biometricLockKey) ?? false,
      autoRefreshLibrary: preferences?.getBool(_autoRefreshKey) ?? true,
      refreshIntervalHours:
          (preferences?.getInt(_refreshIntervalKey) ?? 12).clamp(1, 168).toInt(),
      updateWifiOnly: preferences?.getBool(_updateWifiOnlyKey) ?? true,
      downloadConcurrency:
          (preferences?.getInt(_downloadConcurrencyKey) ?? 1).clamp(1, 4).toInt(),
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

  void setReaderMode(ReaderMode mode) {
    unawaited(
        ref.read(preferencesProvider)?.setString(_readerModeKey, mode.name));
    state = state.copyWith(readerMode: mode);
  }

  void setReaderDirection(ReaderDirection direction) {
    unawaited(
      ref
          .read(preferencesProvider)
          ?.setString(_readerDirectionKey, direction.name),
    );
    state = state.copyWith(readerDirection: direction);
  }

  void setReaderFit(ReaderFit fit) {
    unawaited(
      ref.read(preferencesProvider)?.setString(_readerFitKey, fit.name),
    );
    state = state.copyWith(readerFit: fit);
  }

  void setReaderBackground(ReaderBackground background) {
    unawaited(
      ref
          .read(preferencesProvider)
          ?.setString(_readerBackgroundKey, background.name),
    );
    state = state.copyWith(readerBackground: background);
  }

  void setReaderTapZones(bool value) {
    unawaited(
      ref.read(preferencesProvider)?.setBool(_readerTapZonesKey, value),
    );
    state = state.copyWith(readerTapZones: value);
  }

  void setReaderTapZoneSize(ReaderTapZoneSize value) {
    unawaited(
      ref
          .read(preferencesProvider)
          ?.setString(_readerTapZoneSizeKey, value.name),
    );
    state = state.copyWith(readerTapZoneSize: value);
  }

  void setAutoRefreshLibrary(bool value) {
    unawaited(ref.read(preferencesProvider)?.setBool(_autoRefreshKey, value));
    state = state.copyWith(autoRefreshLibrary: value);
  }

  void setRefreshIntervalHours(int value) {
    final hours = value.clamp(1, 168).toInt();
    unawaited(ref.read(preferencesProvider)?.setInt(_refreshIntervalKey, hours));
    state = state.copyWith(refreshIntervalHours: hours);
  }

  void setUpdateWifiOnly(bool value) {
    unawaited(
      ref.read(preferencesProvider)?.setBool(_updateWifiOnlyKey, value),
    );
    state = state.copyWith(updateWifiOnly: value);
  }

  void setDownloadConcurrency(int value) {
    final limit = value.clamp(1, 4).toInt();
    unawaited(
      ref.read(preferencesProvider)?.setInt(_downloadConcurrencyKey, limit),
    );
    state = state.copyWith(downloadConcurrency: limit);
  }

  void setReaderKeepAwake(bool value) {
    unawaited(
      ref.read(preferencesProvider)?.setBool(_readerKeepAwakeKey, value),
    );
    state = state.copyWith(readerKeepAwake: value);
  }

  void setReaderPreload(bool value) {
    unawaited(ref.read(preferencesProvider)?.setBool(_readerPreloadKey, value));
    state = state.copyWith(readerPreload: value);
  }

  void setReaderAutoAdvance(bool value) {
    unawaited(
      ref.read(preferencesProvider)?.setBool(_readerAutoAdvanceKey, value),
    );
    state = state.copyWith(readerAutoAdvance: value);
  }

  void setReaderWebtoonGap(int value) {
    final gap = value.clamp(0, 32).toInt();
    unawaited(ref.read(preferencesProvider)?.setInt(_readerWebtoonGapKey, gap));
    state = state.copyWith(readerWebtoonGap: gap);
  }

  /// Applies presentation defaults without touching locale, downloads, OCR or
  /// security. The original preference keys keep existing installations intact.
  void setReaderPreferences(ReaderPreferences value) {
    final next = value.copyWith();
    state = state.withReaderPreferences(next);
    unawaited(_persistReaderPreferences(next));
  }

  bool get hasReaderPreferences {
    final preferences = ref.read(preferencesProvider);
    if (preferences == null) {
      return state.readerPreferences != const ReaderPreferences();
    }
    return const [
      _readerModeKey,
      _readerDirectionKey,
      _readerFitKey,
      _readerBackgroundKey,
      _readerTapZonesKey,
      _readerTapZoneSizeKey,
      _readerWebtoonGapKey,
      _readerFilterModeKey,
      _readerBrightnessKey,
      _readerSpreadModeKey,
      _readerCoverAloneKey,
    ].any(preferences.containsKey);
  }

  Future<void> restoreReaderDefaultsIfUnset(ReaderPreferences value) async {
    if (hasReaderPreferences) return;
    final next = value.copyWith();
    state = state.withReaderPreferences(next);
    await _persistReaderPreferences(next);
  }

  Future<void> _persistReaderPreferences(ReaderPreferences next) async {
    final preferences = ref.read(preferencesProvider);
    if (preferences == null) return;
    final entries = <String, Object>{
      _readerModeKey: next.mode.name,
      _readerDirectionKey: next.direction.name,
      _readerFitKey: next.fit.name,
      _readerBackgroundKey: next.background.name,
      _readerTapZonesKey: next.tapZones,
      _readerTapZoneSizeKey: next.tapZoneSize.name,
      _readerWebtoonGapKey: next.webtoonGap,
      _readerFilterModeKey: next.filterMode,
      _readerBrightnessKey: next.brightness,
      _readerSpreadModeKey: next.spreadMode.name,
      _readerCoverAloneKey: next.coverAlone,
    };
    final writes = <Future<bool>>[];
    for (final entry in entries.entries) {
      switch (entry.value) {
        case final String value:
          writes.add(preferences.setString(entry.key, value));
        case final bool value:
          writes.add(preferences.setBool(entry.key, value));
        case final int value:
          writes.add(preferences.setInt(entry.key, value));
      }
    }
    await Future.wait(writes);
  }

  /// Persists the filter name and dim level together so a sheet that changes
  /// both never writes one and loses the other.
  void setReaderFilter({String? mode, int? brightness}) {
    final preferences = ref.read(preferencesProvider);
    var next = state;
    if (mode != null) {
      unawaited(preferences?.setString(_readerFilterModeKey, mode));
      next = next.copyWith(readerFilterMode: mode);
    }
    if (brightness != null) {
      final clamped = brightness.clamp(-75, 0).toInt();
      unawaited(preferences?.setInt(_readerBrightnessKey, clamped));
      next = next.copyWith(readerBrightness: clamped);
    }
    state = next;
  }

  void setOcrTranslationEnabled(bool value) {
    unawaited(
        ref.read(preferencesProvider)?.setBool(_ocrTranslationKey, value));
    state = state.copyWith(ocrTranslationEnabled: value);
  }

  void setBiometricLockEnabled(bool value) {
    unawaited(ref.read(preferencesProvider)?.setBool(_biometricLockKey, value));
    state = state.copyWith(biometricLockEnabled: value);
  }

  /// `null` forgets the server. The address is stored as typed; the client
  /// validates it before the first request.
  void setSuwayomiUrl(String? url) {
    final preferences = ref.read(preferencesProvider);
    final trimmed = url?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      unawaited(preferences?.remove(_suwayomiKey));
      state = state.copyWith(clearSuwayomi: true);
      return;
    }
    unawaited(preferences?.setString(_suwayomiKey, trimmed));
    state = state.copyWith(suwayomiUrl: trimmed);
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

/// Opt-in work profiles, not chapter profiles: all chapters of the same work
/// share one layout, while another source edition keeps its own identity.
class ReaderProfilesController
    extends Notifier<Map<String, ReaderPreferences>> {
  static const String _key = 'reader_profiles_v1';

  @override
  Map<String, ReaderPreferences> build() {
    final raw = ref.watch(preferencesProvider)?.getString(_key);
    if (raw == null || raw.isEmpty) return const {};
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) return const {};
      final profiles = <String, ReaderPreferences>{};
      for (final entry in decoded.entries) {
        final Object? value = entry.value;
        if (entry.key.isEmpty || value is! Map<String, Object?>) continue;
        profiles[entry.key] = ReaderPreferences.fromJson(value);
      }
      return Map.unmodifiable(profiles);
    } catch (_) {
      return const {};
    }
  }

  void save(String mediaId, ReaderPreferences preferences) {
    if (mediaId.isEmpty || state[mediaId] == preferences) return;
    unawaited(_write({...state, mediaId: preferences.copyWith()}));
  }

  void reset(String mediaId) {
    if (!state.containsKey(mediaId)) return;
    unawaited(_write({...state}..remove(mediaId)));
  }

  Future<void> merge(Map<String, ReaderPreferences> imported) async {
    if (imported.isEmpty) return;
    await _write({...imported, ...state});
  }

  Future<void> _write(Map<String, ReaderPreferences> profiles) async {
    state = Map.unmodifiable(profiles);
    final encoded =
        profiles.map((id, profile) => MapEntry(id, profile.toJson()));
    await ref.read(preferencesProvider)?.setString(_key, jsonEncode(encoded));
  }
}

final readerProfilesProvider =
    NotifierProvider<ReaderProfilesController, Map<String, ReaderPreferences>>(
  ReaderProfilesController.new,
);

/// Presentation comes from the selected work; device-wide policy always comes
/// from AppSettings. Merely opening a work never creates or overwrites a profile.
final readerSettingsForProvider =
    Provider.family<AppSettings, String>((ref, id) {
  final defaults = ref.watch(settingsProvider);
  final profile =
      ref.watch(readerProfilesProvider.select((profiles) => profiles[id]));
  return profile == null ? defaults : defaults.withReaderPreferences(profile);
});

class ReaderSettingsController {
  ReaderSettingsController(this._ref, this.mediaId);

  final Ref _ref;
  final String mediaId;

  void rememberForWork(bool value) {
    final controller = _ref.read(readerProfilesProvider.notifier);
    if (value) {
      controller.save(mediaId,
          _ref.read(readerSettingsForProvider(mediaId)).readerPreferences);
    } else {
      controller.reset(mediaId);
    }
  }

  void _update(ReaderPreferences Function(ReaderPreferences) edit) {
    final current =
        _ref.read(readerSettingsForProvider(mediaId)).readerPreferences;
    final next = edit(current);
    if (_ref.read(readerProfilesProvider).containsKey(mediaId)) {
      _ref.read(readerProfilesProvider.notifier).save(mediaId, next);
    } else {
      _ref.read(settingsProvider.notifier).setReaderPreferences(next);
    }
  }

  void setReaderMode(ReaderMode value) =>
      _update((p) => p.copyWith(mode: value));
  void setReaderDirection(ReaderDirection value) =>
      _update((p) => p.copyWith(direction: value));
  void setReaderFit(ReaderFit value) => _update((p) => p.copyWith(fit: value));
  void setReaderBackground(ReaderBackground value) =>
      _update((p) => p.copyWith(background: value));
  void setReaderTapZones(bool value) =>
      _update((p) => p.copyWith(tapZones: value));
  void setReaderTapZoneSize(ReaderTapZoneSize value) =>
      _update((p) => p.copyWith(tapZoneSize: value));
  void setReaderWebtoonGap(int value) =>
      _update((p) => p.copyWith(webtoonGap: value));
  void setReaderSpreadMode(ReaderSpreadMode value) =>
      _update((p) => p.copyWith(spreadMode: value));
  void setReaderCoverAlone(bool value) =>
      _update((p) => p.copyWith(coverAlone: value));
  void setReaderFilter({String? mode, int? brightness}) =>
      _update((p) => p.copyWith(filterMode: mode, brightness: brightness));

  void setReaderKeepAwake(bool value) =>
      _ref.read(settingsProvider.notifier).setReaderKeepAwake(value);
  void setReaderPreload(bool value) =>
      _ref.read(settingsProvider.notifier).setReaderPreload(value);
  void setOcrTranslationEnabled(bool value) =>
      _ref.read(settingsProvider.notifier).setOcrTranslationEnabled(value);
}

final readerSettingsControllerProvider =
    Provider.family<ReaderSettingsController, String>(
  (ref, id) => ReaderSettingsController(ref, id),
);

/// Pages the person marked while reading, keyed by unit id.
///
/// A bookmark belongs to a chapter, not to the work: page 7 of chapter 3 and
/// page 7 of chapter 4 are different places. The map is small (only chapters
/// with marks), stored as JSON in preferences, and written on every toggle so a
/// process death cannot lose it.
class ReaderBookmarksController extends Notifier<Map<String, List<int>>> {
  static const String _key = 'reader_bookmarks_v1';

  @override
  Map<String, List<int>> build() {
    final raw = ref.watch(preferencesProvider)?.getString(_key);
    if (raw == null || raw.isEmpty) return const <String, List<int>>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const <String, List<int>>{};
      final result = <String, List<int>>{};
      decoded.forEach((dynamic key, dynamic value) {
        if (key is! String || value is! List) return;
        final pages = value
            .whereType<num>()
            .map((number) => number.toInt())
            .where((page) => page >= 0)
            .toSet()
            .toList()
          ..sort();
        if (pages.isNotEmpty) result[key] = List<int>.unmodifiable(pages);
      });
      return Map<String, List<int>>.unmodifiable(result);
    } catch (_) {
      // A corrupt preference must not lock the reader; start with no marks.
      return const <String, List<int>>{};
    }
  }

  List<int> pagesFor(String unitId) => state[unitId] ?? const <int>[];

  bool isBookmarked(String unitId, int page) => pagesFor(unitId).contains(page);

  Future<void> merge(Map<String, List<int>> imported) async {
    if (imported.isEmpty) return;
    final merged = ReaderStateSnapshot(bookmarks: state)
        .merge(ReaderStateSnapshot(bookmarks: imported));
    state = merged.bookmarks;
    await ref.read(preferencesProvider)?.setString(_key, jsonEncode(state));
  }

  void toggle(String unitId, int page) {
    if (page < 0) return;
    final next = <String, List<int>>{...state};
    final pages = <int>{...pagesFor(unitId)};
    if (!pages.add(page)) pages.remove(page);
    if (pages.isEmpty) {
      next.remove(unitId);
    } else {
      final sorted = pages.toList()..sort();
      next[unitId] = List<int>.unmodifiable(sorted);
    }
    state = Map<String, List<int>>.unmodifiable(next);
    unawaited(
        ref.read(preferencesProvider)?.setString(_key, jsonEncode(state)));
  }
}

final NotifierProvider<ReaderBookmarksController, Map<String, List<int>>>
    readerBookmarksProvider =
    NotifierProvider<ReaderBookmarksController, Map<String, List<int>>>(
  ReaderBookmarksController.new,
);

class LibraryQueryController extends Notifier<LibraryQuery> {
  static const String _shelfKey = 'library.shelf';

  /// The library opens on the shelf the person used last, on its Default tab.
  @override
  LibraryQuery build() {
    final saved = ref.watch(preferencesProvider)?.getString(_shelfKey);
    final shelf = saved == LibraryShelf.watching.name
        ? LibraryShelf.watching
        : LibraryShelf.reading;
    return LibraryQuery(shelf: shelf, uncategorized: true);
  }

  void setSearch(String value) {
    if (state.search == value) return;
    state = state.copyWith(search: value);
  }

  void setFilter(LibraryFilter filter) {
    if (state.filter == filter) return;
    state = state.copyWith(filter: filter);
  }

  void setSort(LibrarySort sort) {
    if (sort == LibrarySort.random) {
      // A fresh seed each time the person asks to shuffle; the seed keeps the
      // order stable across rebuilds until they ask again.
      final now = DateTime.now().microsecondsSinceEpoch;
      state = state.copyWith(
        sort: sort,
        randomSeed: now > state.randomSeed ? now : state.randomSeed + 1,
      );
      return;
    }
    if (state.sort == sort) return;
    state = state.copyWith(sort: sort, randomSeed: 0);
  }

  /// One category tab. Selecting the active one again does nothing.
  void setTag(String? tag) {
    if (tag != null && state.tag == tag && !state.uncategorized) return;
    state = state.copyWith(
      tag: tag,
      clearTag: tag == null,
      uncategorized: false,
    );
  }

  /// The Default tab: works that belong to no category on this shelf.
  void setUncategorized() {
    if (state.uncategorized && state.tag == null) return;
    state = state.copyWith(clearTag: true, uncategorized: true);
  }

  /// Switching shelves starts again on that shelf's Default tab, and the choice
  /// is remembered for the next launch.
  void setShelf(LibraryShelf shelf) {
    if (state.shelf == shelf) return;
    state = state.copyWith(
      shelf: shelf,
      clearTag: true,
      uncategorized: true,
    );
    unawaited(ref.read(preferencesProvider)?.setString(_shelfKey, shelf.name));
  }
}

final NotifierProvider<LibraryQueryController, LibraryQuery>
    libraryQueryProvider =
    NotifierProvider<LibraryQueryController, LibraryQuery>(
  LibraryQueryController.new,
);

/// The two halves of Best. A source belongs to one of them, which is why Home
/// needs no separate switch: choosing a source already chooses the half.
enum HomeKind { reading, watching }

/// Which half a source serves. Extensions declare it; a JSON pack declares its
/// default work kind; every other adapter is a reading catalogue.
HomeKind homeKindOf(SourceAdapter source) {
  if (source is ExtensionSourceAdapter) {
    return source.info.isAnime ? HomeKind.watching : HomeKind.reading;
  }
  if (source is JsonSourceAdapter) {
    return source.pack.defaultKind.isReading
        ? HomeKind.reading
        : HomeKind.watching;
  }
  return HomeKind.reading;
}

/// The front door remembers the last source, so reopening Best lands on the
/// catalogue the person actually uses instead of a merged list. The source's
/// own kind decides whether the feed reads manga or anime; there is no global
/// switch taking room on a screen a manga-only reader may never need.
class HomeScope {
  const HomeScope({this.sourceId});

  final String? sourceId;
}

class HomeScopeController extends Notifier<HomeScope> {
  static const String _sourceKey = 'home.source';

  @override
  HomeScope build() {
    final prefs = ref.watch(preferencesProvider);
    return HomeScope(sourceId: prefs?.getString(_sourceKey));
  }

  void selectSource(String? sourceId) {
    final next = sourceId == null || sourceId.isEmpty ? null : sourceId;
    unawaited(ref.read(preferencesProvider)?.setString(_sourceKey, next ?? ''));
    state = HomeScope(sourceId: next);
  }
}

final NotifierProvider<HomeScopeController, HomeScope> homeScopeProvider =
    NotifierProvider<HomeScopeController, HomeScope>(HomeScopeController.new);

/// Sources the reader hid from Home.
///
/// Hiding is a front-door decision, not an uninstall: a hidden source keeps
/// resolving works already on the shelf and files already downloaded, it just
/// stops taking a chip on Home. At least one source always stays visible, so a
/// mistap cannot leave the front door empty.
class SourceVisibilityController extends Notifier<Set<String>> {
  static const String _key = 'hidden_sources_v1';

  @override
  Set<String> build() {
    final raw =
        ref.watch(preferencesProvider)?.getStringList(_key) ?? const <String>[];
    return Set.unmodifiable(raw.where((id) => id.trim().isNotEmpty));
  }

  bool isVisible(String sourceId) => !state.contains(sourceId);

  /// Returns false when hiding [sourceId] would hide the last visible source.
  Future<bool> setVisible(
    String sourceId,
    bool visible, {
    required Iterable<String> allIds,
  }) async {
    final next = {...state};
    if (visible) {
      next.remove(sourceId);
    } else {
      next.add(sourceId);
      final visibleCount = allIds.where((id) => !next.contains(id)).length;
      if (visibleCount == 0) return false;
    }
    await _write(next);
    return true;
  }

  Future<void> _write(Set<String> ids) async {
    final list = ids.where((id) => id.isNotEmpty).toList()..sort();
    await ref.read(preferencesProvider)?.setStringList(_key, list);
    state = Set.unmodifiable(list);
  }
}

final NotifierProvider<SourceVisibilityController, Set<String>>
    sourceVisibilityProvider =
    NotifierProvider<SourceVisibilityController, Set<String>>(
  SourceVisibilityController.new,
);

/// What the last request to a source did.
///
/// A catalogue can fail while the app is otherwise healthy. This is the small
/// amount of evidence Manage sources needs to say "this one is down" without
/// pretending the whole app is broken, and without silently switching away
/// from the source the reader chose.
class SourceHealth {
  const SourceHealth({
    this.lastSuccessAt = 0,
    this.lastFailureAt = 0,
    this.lastError,
    this.lastLatencyMs = 0,
  });

  final int lastSuccessAt;
  final int lastFailureAt;
  final String? lastError;
  final int lastLatencyMs;

  bool get tested => lastSuccessAt > 0 || lastFailureAt > 0;
  bool get failed => lastFailureAt > lastSuccessAt;
  bool get slow => !failed && lastSuccessAt > 0 && lastLatencyMs >= 4000;

  Map<String, Object?> toJson() => {
        's': lastSuccessAt,
        'f': lastFailureAt,
        'e': lastError,
        'l': lastLatencyMs,
      };

  static SourceHealth? fromJson(Object? raw) {
    if (raw is! Map) return null;
    int read(String key) => (raw[key] as num?)?.toInt() ?? 0;
    final error = raw['e'];
    return SourceHealth(
      lastSuccessAt: read('s'),
      lastFailureAt: read('f'),
      lastError: error is String && error.trim().isNotEmpty ? error : null,
      lastLatencyMs: read('l'),
    );
  }
}

class SourceHealthController extends Notifier<Map<String, SourceHealth>> {
  static const String _key = 'source_health_v1';

  /// Writes are chained instead of timed: a widget test that ends immediately
  /// after a source request must not leave a pending debounce timer behind, and
  /// a later snapshot must never overwrite an older one out of order.
  Future<void> _saveChain = Future<void>.value();

  @override
  Map<String, SourceHealth> build() {
    final raw = ref.watch(preferencesProvider)?.getString(_key);
    if (raw == null || raw.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final result = <String, SourceHealth>{};
      for (final entry in decoded.entries) {
        final health = SourceHealth.fromJson(entry.value);
        if (health != null) result['${entry.key}'] = health;
      }
      return Map.unmodifiable(result);
    } catch (_) {
      // A corrupt health cache is disposable: it is evidence, not user data.
      return const {};
    }
  }

  SourceHealth? healthOf(String sourceId) => state[sourceId];

  void recordSuccess(String sourceId, Duration latency) {
    final previous = state[sourceId];
    final failureAt = previous?.lastFailureAt ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final next = <String, SourceHealth>{
      ...state,
      sourceId: SourceHealth(
        // A success in the same millisecond as a failure still has to win.
        lastSuccessAt: now > failureAt ? now : failureAt + 1,
        lastFailureAt: failureAt,
        lastLatencyMs: latency.inMilliseconds,
      ),
    };
    state = Map.unmodifiable(next);
    _scheduleSave();
  }

  void recordFailure(String sourceId, Object error) {
    final previous = state[sourceId];
    final successAt = previous?.lastSuccessAt ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final next = <String, SourceHealth>{
      ...state,
      sourceId: SourceHealth(
        lastSuccessAt: successAt,
        lastFailureAt: now > successAt ? now : successAt + 1,
        lastError: _shortError(error),
        lastLatencyMs: previous?.lastLatencyMs ?? 0,
      ),
    };
    state = Map.unmodifiable(next);
    _scheduleSave();
  }

  /// Waits for every queued write, for tests and explicit actions.
  Future<void> flush() => _saveChain;

  void _scheduleSave() {
    final preferences = ref.read(preferencesProvider);
    final encoded = jsonEncode({
      for (final entry in state.entries) entry.key: entry.value.toJson(),
    });
    _saveChain = _saveChain.then((_) async {
      await preferences?.setString(_key, encoded);
    }).catchError((Object _) {
      // Evidence is disposable; a failed preference write must not break a
      // catalogue request or surface as an unhandled async error.
    });
  }

  static String _shortError(Object error) {
    final first = error.toString().split('\n').first.trim();
    if (first.isEmpty) return 'Unknown error';
    return first.length > 180 ? '${first.substring(0, 177)}…' : first;
  }
}

final NotifierProvider<SourceHealthController, Map<String, SourceHealth>>
    sourceHealthProvider =
    NotifierProvider<SourceHealthController, Map<String, SourceHealth>>(
  SourceHealthController.new,
);

/// Categories are tags with a first-class name, kept apart per shelf: a manga
/// category never appears on the anime shelf and the other way round.
///
/// The assignment still lives on the work (`media.tags`), so a backup made by
/// an older Best restores every category without a schema change. This
/// controller only keeps the names that exist even while no work uses them,
/// plus the order the person put them in.
abstract class ShelfCategoriesController extends Notifier<List<String>> {
  /// The shelf whose works these names belong to.
  LibraryShelf get shelf;

  /// Preferences key that stores this shelf's names.
  String get storageKey;

  @override
  List<String> build() {
    final raw =
        ref.watch(preferencesProvider)?.getStringList(storageKey) ?? const [];
    return List.unmodifiable(_clean(raw));
  }

  Future<void> add(String name) async {
    final clean = name.trim();
    if (clean.isEmpty || state.contains(clean)) return;
    await _write([...state, clean]);
  }

  Future<void> merge(Iterable<String> names) => _write([...state, ...names]);

  /// Renames a category on every work of this shelf that carries it.
  Future<void> rename(String from, String to) async {
    final clean = to.trim();
    if (clean.isEmpty || from == clean) return;
    final repository = ref.read(repositoryProvider);
    for (final media in await repository.allMedia()) {
      if (!shelf.contains(media.kind) || !media.tags.contains(from)) continue;
      final tags = [
        for (final tag in media.tags)
          if (tag == from) clean else tag,
      ];
      await repository.setTags(media.id, _dedupe(tags));
    }
    await _write([
      for (final name in state)
        if (name == from) clean else name,
    ]);
    await ref.read(hiddenCategoriesProvider.notifier).rename(from, clean);
  }

  /// Deletes the name from every work of this shelf. Downloads and progress
  /// are untouched: a category is a label, not a container of files.
  Future<void> remove(String name) async {
    final repository = ref.read(repositoryProvider);
    for (final media in await repository.allMedia()) {
      if (!shelf.contains(media.kind) || !media.tags.contains(name)) continue;
      await repository.setTags(
        media.id,
        media.tags.where((tag) => tag != name).toList(growable: false),
      );
    }
    await _write(state.where((entry) => entry != name).toList());
    await ref.read(hiddenCategoriesProvider.notifier).unhide(name);
  }

  Future<void> _write(List<String> names) async {
    final clean = _clean(names);
    await ref.read(preferencesProvider)?.setStringList(storageKey, clean);
    state = List.unmodifiable(clean);
  }

  static List<String> _clean(Iterable<String> names) => _dedupe(
      names.map((name) => name.trim()).where((name) => name.isNotEmpty));

  static List<String> _dedupe(Iterable<String> names) {
    final seen = <String>{};
    return [
      for (final name in names)
        if (seen.add(name)) name,
    ];
  }
}

/// Manga and its kin. The original key, so existing categories stay put.
class CategoriesController extends ShelfCategoriesController {
  @override
  LibraryShelf get shelf => LibraryShelf.reading;

  @override
  String get storageKey => 'categories_v1';
}

/// Anime. Its own key, so its categories never mix with manga's.
class WatchingCategoriesController extends ShelfCategoriesController {
  @override
  LibraryShelf get shelf => LibraryShelf.watching;

  @override
  String get storageKey => 'categories_v1_watching';
}

final NotifierProvider<CategoriesController, List<String>> categoriesProvider =
    NotifierProvider<CategoriesController, List<String>>(
  CategoriesController.new,
);

final NotifierProvider<WatchingCategoriesController, List<String>>
    watchingCategoriesProvider =
    NotifierProvider<WatchingCategoriesController, List<String>>(
  WatchingCategoriesController.new,
);

/// Categories hidden from the shelf. Local only, like everything else here.
class HiddenCategoriesController extends Notifier<Set<String>> {
  static const String _key = 'hidden_categories_v1';

  @override
  Set<String> build() {
    final raw =
        ref.watch(preferencesProvider)?.getStringList(_key) ?? const <String>[];
    return Set.unmodifiable(raw.where((name) => name.trim().isNotEmpty));
  }

  Future<void> setHidden(String name, bool hidden) async {
    final next = {...state};
    if (hidden) {
      next.add(name);
    } else {
      next.remove(name);
    }
    await _write(next);
  }

  Future<void> rename(String from, String to) async {
    if (!state.contains(from)) return;
    final next = {...state}..remove(from);
    next.add(to);
    await _write(next);
  }

  Future<void> unhide(String name) async {
    if (!state.contains(name)) return;
    final next = {...state}..remove(name);
    await _write(next);
  }

  Future<void> _write(Set<String> names) async {
    final list = names.where((name) => name.isNotEmpty).toList()..sort();
    await ref.read(preferencesProvider)?.setStringList(_key, list);
    state = Set.unmodifiable(list);
  }
}

final NotifierProvider<HiddenCategoriesController, Set<String>>
    hiddenCategoriesProvider =
    NotifierProvider<HiddenCategoriesController, Set<String>>(
  HiddenCategoriesController.new,
);

/// Reveals hidden categories for this session only. A restart locks them again,
/// which is the point of a hidden category.
class RevealHiddenController extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;

  void toggle() => state = !state;
}

final NotifierProvider<RevealHiddenController, bool> revealHiddenProvider =
    NotifierProvider<RevealHiddenController, bool>(RevealHiddenController.new);

/// Komikku hides empty category tabs while a search or filter is active. Some
/// readers prefer the strip to stay put, so it is a preference, not a rule.
class LibraryShowEmptyController extends Notifier<bool> {
  static const String _key = 'library_show_empty_categories';

  @override
  bool build() => ref.watch(preferencesProvider)?.getBool(_key) ?? false;

  Future<void> set(bool value) async {
    await ref.read(preferencesProvider)?.setBool(_key, value);
    state = value;
  }
}

final NotifierProvider<LibraryShowEmptyController, bool>
    libraryShowEmptyCategoriesProvider =
    NotifierProvider<LibraryShowEmptyController, bool>(
  LibraryShowEmptyController.new,
);

/// A category plus how many works currently carry it.
class CategorySummary {
  const CategorySummary({
    required this.name,
    required this.count,
    required this.hidden,
  });

  final String name;
  final int count;
  final bool hidden;
}

/// What one shelf's tab strip needs: how many works it holds, how many have no
/// category (the Default tab), and every category of that shelf with its count.
class ShelfTabs {
  const ShelfTabs({
    required this.total,
    required this.uncategorized,
    required this.categories,
  });

  final int total;
  final int uncategorized;
  final List<CategorySummary> categories;
}

/// The union of names the person created and tags already present on works of
/// the current shelf, so a list typed on a series page shows up here without
/// extra bookkeeping. Hidden categories stay in the list: the manager needs
/// them to show them again.
final FutureProvider<ShelfTabs> libraryTabsProvider =
    FutureProvider<ShelfTabs>((ref) async {
  ref.watch(libraryChangesProvider);
  final shelf = ref.watch(
        libraryQueryProvider.select((query) => query.shelf),
      ) ??
      LibraryShelf.reading;
  final entries = await ref.watch(allLibraryProvider.future);
  final hidden = ref.watch(hiddenCategoriesProvider);
  final registered = shelf == LibraryShelf.watching
      ? ref.watch(watchingCategoriesProvider)
      : ref.watch(categoriesProvider);

  final inShelf =
      entries.where((entry) => shelf.contains(entry.media.kind)).toList();
  final counts = <String, int>{};
  final discovered = <String>[];
  var uncategorized = 0;
  for (final entry in inShelf) {
    final names = [
      for (final tag in entry.media.tags)
        if (tag.trim().isNotEmpty) tag.trim(),
    ];
    if (names.isEmpty) uncategorized++;
    for (final name in names) {
      if (!counts.containsKey(name)) discovered.add(name);
      counts[name] = (counts[name] ?? 0) + 1;
    }
  }

  final names = <String>[...registered];
  for (final name in discovered) {
    if (!names.contains(name)) names.add(name);
  }

  return ShelfTabs(
    total: inShelf.length,
    uncategorized: uncategorized,
    categories: List.unmodifiable([
      for (final name in names)
        CategorySummary(
          name: name,
          count: counts[name] ?? 0,
          hidden: hidden.contains(name),
        ),
    ]),
  );
});

/// The on-screen strip, unlike the category manager, follows search/filter
/// matches. Ignore the selected category when counting: other tabs must remain
/// reachable. Hidden works must never contribute to a visible tab's count.
final FutureProvider<ShelfTabs> libraryVisibleTabsProvider =
    FutureProvider<ShelfTabs>((ref) async {
  final query = ref.watch(libraryQueryProvider);
  final hidden = ref.watch(hiddenCategoriesProvider);
  final reveal = ref.watch(revealHiddenProvider);
  final showEmpty = ref.watch(libraryShowEmptyCategoriesProvider);
  final tabsFuture = ref.watch(libraryTabsProvider.future);
  final entriesFuture = ref.watch(allLibraryProvider.future);
  final tabs = await tabsFuture;
  final entries = await entriesFuture;
  final matches = LibraryPolicy.apply(
    entries,
    query.copyWith(
      clearTag: true,
      uncategorized: false,
      hiddenTags: hidden,
      includeHidden: reveal,
    ),
  );
  final counts = <String, int>{};
  var uncategorized = 0;
  for (final entry in matches) {
    final names = {
      for (final tag in entry.media.tags)
        if (tag.trim().isNotEmpty) tag.trim(),
    };
    if (names.isEmpty) uncategorized++;
    for (final name in names) {
      counts[name] = (counts[name] ?? 0) + 1;
    }
  }
  final narrowing = query.search.trim().isNotEmpty ||
      query.filter != LibraryFilter.all;
  return ShelfTabs(
    total: matches.length,
    uncategorized: uncategorized,
    categories: List.unmodifiable([
      for (final category in tabs.categories)
        if (reveal || !category.hidden)
          if (!narrowing || showEmpty || (counts[category.name] ?? 0) > 0)
            CategorySummary(
              name: category.name,
              count: counts[category.name] ?? 0,
              hidden: category.hidden,
            ),
    ]),
  );
});

/// The category list of the current shelf, for the manager and the pickers.
final FutureProvider<List<CategorySummary>> libraryCategoriesProvider =
    FutureProvider<List<CategorySummary>>((ref) async {
  return (await ref.watch(libraryTabsProvider.future)).categories;
});

/// A new event means some write landed; the shelf re-runs its query.
final StreamProvider<int> libraryChangesProvider = StreamProvider<int>((ref) {
  var revision = 0;
  // Repository events are void/null. AsyncData(null) compares equal after the
  // first event in Riverpod 3, so queries otherwise stop refreshing. Each write
  // needs a distinct revision, not a distinct payload from the database.
  return ref.watch(repositoryProvider).changes.map((_) => ++revision);
});

final FutureProvider<List<LibraryEntry>> libraryProvider =
    FutureProvider<List<LibraryEntry>>((ref) async {
  ref.watch(libraryChangesProvider);
  final repository = ref.watch(repositoryProvider);
  final hidden = ref.watch(hiddenCategoriesProvider);
  final reveal = ref.watch(revealHiddenProvider);
  final query = ref.watch(libraryQueryProvider);
  return repository.library(
    hidden.isEmpty || reveal ? query : query.copyWith(hiddenTags: hidden),
  );
});

/// Every work in the library, both shelves, with no tab, search or hidden
/// filter. Downloads, recommendations and the settings count read this, so the
/// library screen's own view never narrows them.
final FutureProvider<List<LibraryEntry>> allLibraryProvider =
    FutureProvider<List<LibraryEntry>>((ref) async {
  ref.watch(libraryChangesProvider);
  return ref.watch(repositoryProvider).library(const LibraryQuery());
});

/// New unread chapters from works already on the shelf, newest first.
final FutureProvider<List<LibraryUpdate>> libraryUpdatesProvider =
    FutureProvider<List<LibraryUpdate>>((ref) async {
  ref.watch(libraryChangesProvider);
  return ref.watch(repositoryProvider).libraryUpdates();
});

/// The shelf, filtered by the same text a reader types into search. It is a
/// separate provider so a search never disturbs the Library tab's own query.
final librarySearchProvider =
    FutureProvider.family<List<LibraryEntry>, String>((ref, query) async {
  final text = query.trim();
  if (text.isEmpty) return const <LibraryEntry>[];
  ref.watch(libraryChangesProvider);
  return ref.watch(repositoryProvider).library(LibraryQuery(search: text));
});

final FutureProvider<List<ContinueEntry>> continueProvider =
    FutureProvider<List<ContinueEntry>>((ref) async {
  ref.watch(libraryChangesProvider);
  return ref.watch(repositoryProvider).continueReading();
});

/// The history keeps a longer list than the home rail, which shows six.
final FutureProvider<List<ContinueEntry>> historyContinueProvider =
    FutureProvider<List<ContinueEntry>>((ref) async {
  ref.watch(libraryChangesProvider);
  return ref.watch(repositoryProvider).continueReading(limit: 40);
});

/// Where "continue" actually lands, not just where it stopped.
///
/// A reader who finished chapter 12 does not want chapter 12 again: the smart
/// answer is chapter 13. [continueProvider] can only report a unit that has
/// progress, so this walks one step further when the last unit is finished and
/// hands back the first unit that is still unread. `isNext` is what the card
/// labels "next up"; the numbers themselves are never invented — a work with no
/// stored units simply does not appear.
class ResumeSlot {
  const ResumeSlot({
    required this.media,
    required this.unit,
    required this.isNext,
    this.progress,
  });

  final Media media;
  final MediaUnit unit;

  /// True when [unit] is a chapter the reader has never opened, reached by
  /// finishing the one before it.
  final bool isNext;

  /// Progress for [unit]. Null when it has never been opened.
  final UnitProgress? progress;

  double get fraction => progress?.fraction ?? 0;

  /// The same label the continue rail uses, built from a real progress row.
  ContinueEntry? get continueEntry => progress == null
      ? null
      : ContinueEntry(media: media, unit: unit, progress: progress!);
}

final FutureProvider<List<ResumeSlot>> resumeProvider =
    FutureProvider<List<ResumeSlot>>((ref) async {
  ref.watch(libraryChangesProvider);
  final repository = ref.watch(repositoryProvider);
  final entries = await repository.continueReading(limit: 24);
  final slots = <ResumeSlot>[];
  final seen = <String>{};

  for (final entry in entries) {
    if (slots.length == 6) break;
    // One card per work: the newest unit with progress is the one that speaks.
    if (!seen.add(entry.media.id)) continue;
    if (!entry.progress.completed) {
      slots.add(
        ResumeSlot(
          media: entry.media,
          unit: entry.unit,
          isNext: false,
          progress: entry.progress,
        ),
      );
      continue;
    }
    final units = await repository.unitsFor(entry.media.id);
    final index = units.indexWhere((unit) => unit.id == entry.unit.id);
    if (index < 0) continue;
    for (var i = index + 1; i < units.length; i++) {
      final saved = await repository.progressFor(units[i].id);
      if (saved != null && saved.completed) continue;
      slots.add(
        ResumeSlot(
          media: entry.media,
          unit: units[i],
          isNext: !UnitNavigation.hasStarted(saved),
          progress: saved,
        ),
      );
      break;
    }
  }
  return List.unmodifiable(slots);
});

/// Everything opened recently, whether or not it is on the shelf.
final FutureProvider<List<Media>> recentProvider =
    FutureProvider<List<Media>>((ref) async {
  ref.watch(libraryChangesProvider);
  return ref.watch(repositoryProvider).recent(limit: 40);
});

/// What the history screen is allowed to show. Komikku exposes tri-state
/// filters for unfinished works, unfinished chapters and works outside the
/// library; Best keeps the same questions as plain switches plus a kind.
enum HistoryKindFilter { all, reading, watching }

class HistoryFilter {
  const HistoryFilter({
    this.kind = HistoryKindFilter.all,
    this.onlyUnread = false,
    this.onlyNotOnShelf = false,
    this.onlyFavorites = false,
  });

  final HistoryKindFilter kind;
  final bool onlyUnread;
  final bool onlyNotOnShelf;
  final bool onlyFavorites;

  bool get isActive =>
      kind != HistoryKindFilter.all ||
      onlyUnread ||
      onlyNotOnShelf ||
      onlyFavorites;

  int get activeCount =>
      (kind == HistoryKindFilter.all ? 0 : 1) +
      (onlyUnread ? 1 : 0) +
      (onlyNotOnShelf ? 1 : 0) +
      (onlyFavorites ? 1 : 0);

  HistoryFilter copyWith({
    HistoryKindFilter? kind,
    bool? onlyUnread,
    bool? onlyNotOnShelf,
    bool? onlyFavorites,
  }) =>
      HistoryFilter(
        kind: kind ?? this.kind,
        onlyUnread: onlyUnread ?? this.onlyUnread,
        onlyNotOnShelf: onlyNotOnShelf ?? this.onlyNotOnShelf,
        onlyFavorites: onlyFavorites ?? this.onlyFavorites,
      );

  Map<String, Object> toJson() => {
        'kind': kind.name,
        'onlyUnread': onlyUnread,
        'onlyNotOnShelf': onlyNotOnShelf,
        'onlyFavorites': onlyFavorites,
      };

  factory HistoryFilter.fromJson(Map<String, Object?> json) {
    final kind = HistoryKindFilter.values.firstWhere(
      (value) => value.name == json['kind'],
      orElse: () => HistoryKindFilter.all,
    );
    return HistoryFilter(
      kind: kind,
      onlyUnread: json['onlyUnread'] == true,
      onlyNotOnShelf: json['onlyNotOnShelf'] == true,
      onlyFavorites: json['onlyFavorites'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is HistoryFilter &&
      other.kind == kind &&
      other.onlyUnread == onlyUnread &&
      other.onlyNotOnShelf == onlyNotOnShelf &&
      other.onlyFavorites == onlyFavorites;

  @override
  int get hashCode =>
      Object.hash(kind, onlyUnread, onlyNotOnShelf, onlyFavorites);
}

class HistoryFilterController extends Notifier<HistoryFilter> {
  static const String _key = 'history_filters_v1';

  @override
  HistoryFilter build() {
    final raw = ref.watch(preferencesProvider)?.getString(_key);
    if (raw == null || raw.isEmpty) return const HistoryFilter();
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, Object?>
          ? HistoryFilter.fromJson(decoded)
          : const HistoryFilter();
    } catch (_) {
      // A corrupt preference must not hide the person's history.
      return const HistoryFilter();
    }
  }

  void setKind(HistoryKindFilter kind) => _set(state.copyWith(kind: kind));
  void setOnlyUnread(bool value) => _set(state.copyWith(onlyUnread: value));
  void setOnlyNotOnShelf(bool value) =>
      _set(state.copyWith(onlyNotOnShelf: value));
  void setOnlyFavorites(bool value) =>
      _set(state.copyWith(onlyFavorites: value));
  void clear() => _set(const HistoryFilter());

  void _set(HistoryFilter next) {
    if (next == state) return;
    state = next;
    unawaited(
      ref.read(preferencesProvider)?.setString(_key, jsonEncode(next.toJson())),
    );
  }
}

final NotifierProvider<HistoryFilterController, HistoryFilter>
    historyFilterProvider =
    NotifierProvider<HistoryFilterController, HistoryFilter>(
  HistoryFilterController.new,
);

/// Re-read after every write, including the one the manager makes per page.
final FutureProvider<List<DownloadTask>> downloadsProvider =
    FutureProvider<List<DownloadTask>>((ref) async {
  ref.watch(libraryChangesProvider);
  return ref.watch(repositoryProvider).downloads();
});

/// The download row for one unit, refreshed as the manager writes each page.
/// The reader uses it to show whether the current chapter is available offline.
final downloadForProvider = FutureProvider.family<DownloadTask?, String>((
  ref,
  unitId,
) async {
  ref.watch(libraryChangesProvider);
  return ref.watch(repositoryProvider).downloadFor(unitId);
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
  final started = DateTime.now();
  try {
    final result =
        query.isEmpty ? await source.popular() : await source.search(query);
    ref.read(sourceHealthProvider.notifier).recordSuccess(
          source.id,
          DateTime.now().difference(started),
        );
    return result;
  } catch (error) {
    ref.read(sourceHealthProvider.notifier).recordFailure(source.id, error);
    rethrow;
  }
});

/// What the front door shows: the live catalogue of every enabled source,
/// merged and de-duplicated by title.
///
/// Home used to show the bundled guide, which is honest but looks like a demo.
/// This walks the real sources instead, one failure at a time, and only falls
/// back to the guide when nothing answered — offline, or every source down.
class DiscoverFeed {
  const DiscoverFeed({
    required this.works,
    required this.live,
    this.latest = const [],
  });

  final List<Media> works;

  /// What gained a chapter most recently, from sources that support it.
  final List<Media> latest;

  /// False when the guide stood in for the live catalogue.
  final bool live;
}

final FutureProvider<DiscoverFeed> discoverProvider =
    FutureProvider<DiscoverFeed>((ref) async {
  final registry = ref.watch(sourceRegistryProvider);
  final works = <Media>[];
  final latest = <Media>[];
  final seen = <String>{};
  final seenLatest = <String>{};

  // The front door probes a handful of chosen sources, not the full index.
  // Asking hundreds would hammer a server and turn one slow site into a slow
  // app; the Manga tab is where the complete list lives.
  final sources = registry.all
      .where((source) =>
          source.id != DemoSource.sourceId &&
          !source.id.startsWith('suwayomi:'))
      .take(4)
      .toList();

  List<Media> merge(List<Media> page, List<Media> into, Set<String> seen) {
    for (final media in page) {
      final key = '${media.title.toLowerCase().trim()}|${media.kind.name}';
      if (seen.add(key)) into.add(media);
    }
    return into;
  }

  // Latest is a capability, not a promise: only sources that declare it are
  // asked, and a source without a latest page is not an error. Both phases
  // start together, so a slow latest page never delays the catalogue.
  final latestSources = sources.whereType<LatestSource>().toList();
  final popularRequest = Future.wait<List<Media>>([
    for (final source in sources)
      source
          .popular()
          .timeout(
            const Duration(seconds: 12),
            onTimeout: () => const <Media>[],
          )
          .catchError((Object _) => const <Media>[]),
  ]);
  final latestRequest = Future.wait<List<Media>>([
    for (final source in latestSources)
      source
          .latest()
          .timeout(
            const Duration(seconds: 12),
            onTimeout: () => const <Media>[],
          )
          .catchError((Object _) => const <Media>[]),
  ]);

  for (final page in await popularRequest) {
    merge(page, works, seen);
  }
  for (final page in await latestRequest) {
    merge(page, latest, seenLatest);
  }

  if (works.isEmpty) {
    return const DiscoverFeed(works: [], live: false);
  }
  return DiscoverFeed(
    works: List.unmodifiable(works.take(40)),
    latest: List.unmodifiable(latest.take(30)),
    live: true,
  );
});

/// The real community ranking.
///
/// MangaDex is the only catalogue in the app that publishes a score, so this
/// list never mixes rated and unrated works: a rank with no number behind it
/// would be an invented statistic. When the API is down the screen says so
/// instead of falling back to a made-up order.
class Rankings {
  const Rankings({
    this.works = const [],
    this.live = false,
    this.error,
  });

  final List<Media> works;
  final bool live;
  final String? error;

  bool get isEmpty => works.isEmpty;
}

final FutureProvider<Rankings> rankingsProvider =
    FutureProvider<Rankings>((ref) async {
  final registry = ref.watch(sourceRegistryProvider);
  final source = registry.byId(MangaDexSource.sourceId);
  if (source is! MangaDexSource) {
    return const Rankings(error: 'MangaDex is not available.');
  }
  try {
    final works = await source.topRated();
    final rated = works.where((work) => work.rating != null).toList()
      ..sort((a, b) {
        final byScore = b.rating!.compareTo(a.rating!);
        return byScore != 0
            ? byScore
            : a.displayTitle.compareTo(b.displayTitle);
      });
    return Rankings(works: List.unmodifiable(rated), live: true);
  } catch (error) {
    return Rankings(error: '$error');
  }
});

/// A publisher in the extension directory.
///
/// The directory is community-maintained: a publisher is the GitHub account
/// (or host) that signs the APK, not a Best employee. Aggregating the index is
/// the only honest "top contributors" list the app can show, because it is the
/// same data the installer already trusts.
class Publisher {
  const Publisher({
    required this.name,
    required this.url,
    required this.extensions,
    required this.sources,
    required this.languages,
    required this.kinds,
  });

  final String name;
  final String url;
  final int extensions;
  final int sources;
  final List<String> languages;
  final Set<String> kinds;

  bool get hasAnime => kinds.contains('anime');
  bool get hasManga => kinds.contains('manga') || kinds.isEmpty;
}

class Publishers {
  const Publishers({
    this.items = const [],
    this.extensions = 0,
    this.sources = 0,
    this.cached = false,
    this.errors = const [],
  });

  final List<Publisher> items;
  final int extensions;
  final int sources;
  final bool cached;
  final List<String> errors;
}

String _publisherName(String repositoryUrl) {
  final uri = Uri.tryParse(repositoryUrl);
  if (uri == null) return repositoryUrl;
  final segments = uri.pathSegments.where((part) => part.isNotEmpty).toList();
  if (segments.isEmpty) return uri.host;
  if (uri.host == 'github.com' && segments.length >= 2) return segments.first;
  if (uri.host.endsWith('githubusercontent.com') && segments.length >= 2) {
    return segments.first;
  }
  return uri.host;
}

String _publisherUrl(String repositoryUrl) {
  final uri = Uri.tryParse(repositoryUrl);
  if (uri == null) return repositoryUrl;
  final segments = uri.pathSegments.where((part) => part.isNotEmpty).toList();
  final github =
      uri.host == 'github.com' || uri.host.endsWith('githubusercontent.com');
  if (github && segments.isNotEmpty) {
    return 'https://github.com/${segments.first}';
  }
  return '${uri.scheme}://${uri.host}';
}

final FutureProvider<Publishers> publishersProvider =
    FutureProvider<Publishers>((ref) async {
  final directory = await ref.watch(extensionDirectoryProvider.future);
  final groups = <String, List<ExtensionEntry>>{};
  for (final entry in directory.entries) {
    final name = _publisherName(entry.repositoryUrl);
    groups.putIfAbsent(name, () => <ExtensionEntry>[]).add(entry);
  }
  final items = <Publisher>[];
  var sourceCount = 0;
  for (final group in groups.entries) {
    final entries = group.value;
    final languages = <String>{};
    final kinds = <String>{};
    var sources = 0;
    for (final entry in entries) {
      sources += entry.sources.isEmpty ? 1 : entry.sources.length;
      languages.addAll(entry.languages.where((code) => code.isNotEmpty));
      kinds.add(entry.kind);
    }
    sourceCount += sources;
    final sortedLanguages = languages.toList()..sort();
    items.add(
      Publisher(
        name: group.key,
        url: _publisherUrl(entries.first.repositoryUrl),
        extensions: entries.length,
        sources: sources,
        languages: List.unmodifiable(sortedLanguages),
        kinds: Set.unmodifiable(kinds),
      ),
    );
  }
  items.sort((a, b) {
    final bySources = b.sources.compareTo(a.sources);
    return bySources != 0 ? bySources : a.name.compareTo(b.name);
  });
  return Publishers(
    items: List.unmodifiable(items),
    extensions: directory.entries.length,
    sources: sourceCount,
    cached: directory.cached,
    errors: directory.errors,
  );
});

/// Shelf-aware picks from a pool of real catalogue entries.
///
/// There is no recommendation model here: the genres the person actually keeps
/// on their shelf are intersected with what the live sources returned. With an
/// empty shelf it is simply the top-rated list, labelled as such.
class Recommendations {
  const Recommendations({
    this.works = const [],
    this.genres = const [],
    this.personalised = false,
  });

  final List<Media> works;
  final List<String> genres;
  final bool personalised;
}

final FutureProvider<Recommendations> recommendationsProvider =
    FutureProvider<Recommendations>((ref) async {
  final entries = await ref.watch(allLibraryProvider.future);
  final rankings = await ref.watch(rankingsProvider.future);
  final feed = await ref.watch(discoverProvider.future);

  final wanted = <String>{};
  final owned = <String>{};
  for (final entry in entries) {
    owned.add(entry.media.id);
    for (final genre in entry.media.genres) {
      final clean = genre.trim().toLowerCase();
      if (clean.isNotEmpty) wanted.add(clean);
    }
  }

  final pool = <Media>[];
  final seen = <String>{};
  for (final media in [
    ...rankings.works,
    ...feed.works,
    ...feed.latest,
  ]) {
    if (owned.contains(media.id)) continue;
    if (seen.add(media.id)) pool.add(media);
  }

  if (wanted.isEmpty) {
    return Recommendations(
      works: List.unmodifiable(pool.take(12)),
    );
  }

  final matches = pool.where((media) {
    for (final genre in media.genres) {
      if (wanted.contains(genre.trim().toLowerCase())) return true;
    }
    return false;
  }).toList();

  return Recommendations(
    works: List.unmodifiable(matches.take(12)),
    genres: List.unmodifiable(wanted.take(4)),
    personalised: true,
  );
});

/// A week of local activity, framed as a challenge rather than a store.
///
/// The goal and badges are thresholds over numbers the app already records
/// (pages turned, consecutive days, finished chapters). Nothing is uploaded and
/// no reward is a currency: the prize is a label on your own profile.
enum RewardBadge { firstUnit, streak3, streak7, pages100, pages300, pages1000 }

class WeeklyRewards {
  const WeeklyRewards({
    required this.goal,
    required this.weekPages,
    required this.streakDays,
    required this.completedUnits,
    required this.lifetimePages,
    required this.works,
  });

  final int goal;
  final int weekPages;
  final int streakDays;
  final int completedUnits;
  final int lifetimePages;
  final int works;

  double get progress => (weekPages / goal).clamp(0.0, 1.0);

  Set<RewardBadge> get earned => {
        if (completedUnits > 0) RewardBadge.firstUnit,
        if (streakDays >= 3) RewardBadge.streak3,
        if (streakDays >= 7) RewardBadge.streak7,
        if (lifetimePages >= 100) RewardBadge.pages100,
        if (lifetimePages >= 300) RewardBadge.pages300,
        if (lifetimePages >= 1000) RewardBadge.pages1000,
      };
}

final FutureProvider<WeeklyRewards> weeklyRewardsProvider =
    FutureProvider<WeeklyRewards>((ref) async {
  final stats = await ref.watch(readingStatsProvider.future);
  return WeeklyRewards(
    goal: 300,
    weekPages: stats.weekPages,
    streakDays: stats.streakDays,
    completedUnits: stats.completedUnits,
    lifetimePages: stats.pages,
    works: stats.works,
  );
});

/// One search box over every installed source. Sources answer in parallel, so
/// a slow pack cannot hold back the catalogue; a failure only removes that
/// source's rows.
final searchAllProvider =
    FutureProvider.family<List<Media>, String>((ref, rawQuery) async {
  final query = rawQuery.trim();
  if (query.isEmpty) return const <Media>[];
  final registry = ref.watch(sourceRegistryProvider);
  Future<List<Media>> ask(SourceAdapter source) async {
    final started = DateTime.now();
    try {
      // An extension that hangs must not hold the whole search box open.
      final page = await source
          .search(query)
          .timeout(const Duration(seconds: 15));
      ref.read(sourceHealthProvider.notifier).recordSuccess(
            source.id,
            DateTime.now().difference(started),
          );
      return page;
    } catch (error) {
      ref.read(sourceHealthProvider.notifier).recordFailure(source.id, error);
      return const <Media>[];
    }
  }

  final pages = await Future.wait(<Future<List<Media>>>[
    for (final source in registry.all)
      if (source.id != DemoSource.sourceId &&
          !source.id.startsWith('suwayomi:'))
        ask(source),
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

/// The hand-picked shelf.
///
/// It ships inside the app, so the very first launch has an editorial front
/// page even before a source answers, and it refreshes from the project
/// repository, so the picks can change without a store release. Every entry is
/// resolved through its own adapter: the list names a work, it never copies one.
const String kCuratedAsset = 'assets/curated.json';
const String kCuratedRemote =
    'https://raw.githubusercontent.com/PanditJi-9/best/main/apps/'
    'best_app/assets/curated.json';
const String _curatedCacheKey = 'curated_v1';
const String _curatedStampKey = 'curated_v1_at';
const Duration _curatedTtl = Duration(hours: 12);

final FutureProvider<List<Media>> curatedProvider =
    FutureProvider<List<Media>>((ref) async {
  final registry = ref.watch(sourceRegistryProvider);
  final client = ref.watch(httpClientProvider);
  final preferences = ref.watch(preferencesProvider);

  var raw = '';
  final cached = preferences?.getString(_curatedCacheKey);
  final stamp = preferences?.getInt(_curatedStampKey) ?? 0;
  final fresh = DateTime.now().millisecondsSinceEpoch - stamp <
      _curatedTtl.inMilliseconds;
  if (fresh && cached != null) {
    raw = cached;
  } else {
    try {
      final response = await client.get(
        Uri.parse(kCuratedRemote),
        headers: const {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        CuratedList.parse(response.body); // Validate before it is cached.
        raw = response.body;
        unawaited(preferences?.setString(_curatedCacheKey, raw));
        unawaited(
          preferences?.setInt(
            _curatedStampKey,
            DateTime.now().millisecondsSinceEpoch,
          ),
        );
      }
    } catch (_) {
      // Offline, a blocked host or a bad document: the bundled list stands.
    }
    if (raw.isEmpty) raw = cached ?? '';
  }

  if (raw.isEmpty) {
    try {
      raw = await rootBundle.loadString(kCuratedAsset);
    } catch (_) {
      return const <Media>[];
    }
  }

  final CuratedList list;
  try {
    list = CuratedList.parse(raw);
  } on CuratedException {
    return const <Media>[];
  }

  final resolved = await Future.wait(list.picks.map((pick) async {
    if (!registry.all.any((s) => s.id == pick.sourceId)) return null;
    final source = registry.byId(pick.sourceId);
    if (source == null) return null;
    try {
      return await source.details(
        Media(
          ref: SourceRef(pick.sourceId, pick.id),
          title: pick.id,
          kind: MediaKind.manga,
        ),
      );
    } catch (_) {
      // One dead pick must not empty the shelf.
      return null;
    }
  }));

  return List.unmodifiable(resolved.whereType<Media>());
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
    throw SourceNotInstalled(key.sourceId);
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

  final started = DateTime.now();
  final List<MediaUnit> units;
  try {
    units = UnitNavigation.readingOrder(await source.units(media).timeout(
          const Duration(seconds: 20),
        ));
    ref.read(sourceHealthProvider.notifier).recordSuccess(
          source.id,
          DateTime.now().difference(started),
        );
  } catch (error) {
    ref.read(sourceHealthProvider.notifier).recordFailure(source.id, error);
    rethrow;
  }
  await repository.saveUnits(units);

  final progress = <String, UnitProgress>{};
  for (final unit in units) {
    final saved = await repository.progressFor(unit.id);
    if (saved != null) progress[unit.id] = saved;
  }

  return SeriesData(media: media, units: units, progress: progress);
});

/// The stored work and its chapters, without touching the network.
///
/// Migration must work when the old source is gone — that is often why a work
/// is being moved — so it reads the local rows instead of asking the old
/// adapter for details again.
final localWorkProvider = FutureProvider.family<SeriesData, String>((
  ref,
  mediaId,
) async {
  ref.watch(libraryChangesProvider);
  final repository = ref.watch(repositoryProvider);
  final media = await repository.mediaById(mediaId);
  if (media == null) {
    throw StateError('This work is not in the local catalogue yet.');
  }
  final units = await repository.unitsFor(mediaId);
  final progress = <String, UnitProgress>{};
  for (final unit in units) {
    final saved = await repository.progressFor(unit.id);
    if (saved != null) progress[unit.id] = saved;
  }
  return SeriesData(media: media, units: units, progress: progress);
});

typedef MigrationSearchKey = ({String sourceId, String query});

/// Candidate works on other sources while migrating.
///
/// `sourceId == '*'` means every installed source. Each source answers in
/// parallel with its own timeout: a dead site must not hold the migration
/// screen, and one failure is simply absent from the list.
final migrationSearchProvider =
    FutureProvider.family<List<Media>, MigrationSearchKey>((ref, key) async {
  final query = key.query.trim();
  if (query.isEmpty) return const <Media>[];
  final registry = ref.watch(sourceRegistryProvider);
  final all = registry.all;
  final sources = key.sourceId == '*'
      ? all.where((source) => source.id != DemoSource.sourceId).toList()
      : [
          if (registry.byId(key.sourceId) case final source?) source,
        ];
  final pages = await Future.wait(<Future<List<Media>>>[
    for (final source in sources)
      source
          .search(query)
          .timeout(
            const Duration(seconds: 14),
            onTimeout: () => const <Media>[],
          )
          .catchError((Object _) => const <Media>[]),
  ]);

  final merged = <Media>[];
  final seen = <String>{};
  for (final page in pages) {
    for (final media in page) {
      if (seen.add(media.id)) merged.add(media);
    }
  }
  return List.unmodifiable(merged.take(48));
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
    this.units = const [],
  });

  final Media media;
  final MediaUnit unit;
  final SourceAdapter? source;
  final List<MediaUnit> units;
}

Future<ResolvedUnit> _resolveUnit(
  LibraryRepository repository,
  SourceRegistry registry,
  UnitKey key, {
  bool requireSource = true,
}) async {
  final source = registry.byId(key.sourceId);
  if (source == null && requireSource) {
    throw SourceNotInstalled(key.sourceId);
  }

  final media = await repository.mediaById(mediaIdOf(key.sourceId, key.url));
  if (media == null) {
    if (source == null) throw SourceNotInstalled(key.sourceId);
    throw StateError('This work is not in the local catalogue yet.');
  }

  final units = await repository.unitsFor(media.id);
  final unit = units.firstWhere(
    (candidate) => candidate.url == key.unitUrl,
    orElse: () => throw StateError('This unit is not in the local catalogue.'),
  );

  return ResolvedUnit(
    media: media,
    unit: unit,
    source: source,
    units: units,
  );
}

class ReaderData {
  const ReaderData({
    required this.media,
    required this.unit,
    required this.resources,
    required this.progress,
    this.units = const [],
    this.offline = false,
    this.partial = false,
    this.totalPages,
  });

  final Media media;
  final MediaUnit unit;
  final List<MediaResource> resources;
  final UnitProgress? progress;
  final List<MediaUnit> units;

  /// True when the pages came from a finished download, not a source.
  final bool offline;
  final bool partial;
  final int? totalPages;
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
    requireSource: false,
  );
  final media = resolved.media;
  final unit = resolved.unit;
  final source = resolved.source;

  final task = await repository.downloadFor(unit.id);
  final savedProgress = await repository.progressFor(unit.id);
  final storedTotal = task != null && task.total > 0
      ? task.total
      : (unit.pageCount > 0 ? unit.pageCount : (savedProgress?.total ?? 0));
  if (task != null && task.isFinished && task.directory != null) {
    final expected = storedTotal;
    final local = await downloadedPages(
      task.directory!,
      expectedCount: expected > 0 ? expected : null,
    );
    if (local.isNotEmpty) {
      return ReaderData(
        media: media,
        unit: unit,
        resources: local,
        progress: await repository.progressFor(unit.id),
        units: resolved.units,
        offline: true,
        partial: task.total <= 0 || expected > local.length,
        totalPages: expected > 0 ? expected : null,
      );
    }
  }

  List<MediaResource> resources;
  try {
    if (source == null) throw SourceNotInstalled(key.sourceId);
    resources = await source.resources(unit);
  } catch (error) {
    // A paused or partially written download is still better than an error
    // page when the network is the thing that failed.
    if (task?.directory == null) rethrow;
    final expected = storedTotal;
    final local = await downloadedPages(
      task!.directory!,
      expectedCount: expected > 0 ? expected : null,
    );
    if (local.isEmpty) rethrow;
    return ReaderData(
      media: media,
      unit: unit,
      resources: local,
      progress: await repository.progressFor(unit.id),
      units: resolved.units,
      offline: true,
      partial: true,
      totalPages: expected > 0 ? expected : null,
    );
  }

  return ReaderData(
    media: media,
    unit: unit,
    resources: resources,
    progress: await repository.progressFor(unit.id),
    units: resolved.units,
  );
});

class WatchData {
  const WatchData({
    required this.media,
    required this.unit,
    required this.stream,
    required this.progress,
    this.sample = false,
    this.units = const [],
  });

  final Media media;
  final MediaUnit unit;
  final VideoResource stream;
  final UnitProgress? progress;
  final List<MediaUnit> units;

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
  ).timeout(const Duration(seconds: 45));

  final source = resolved.source;
  if (source == null) throw SourceNotInstalled(key.sourceId);
  final resources = await source
      .resources(resolved.unit)
      .timeout(const Duration(seconds: 45));
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
    sample: source.id == DemoSource.sourceId,
    units: resolved.units,
  );
});

/// The stored row for one work, re-read after every write.
///
/// The series screen gets its data from a provider that also talks to the
/// source; a plan change or a new list must not trigger a network refresh, so
/// it watches this tiny query instead.
final mediaByIdProvider =
    FutureProvider.family<Media?, String>((ref, id) async {
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
    final reader = ReaderStateSnapshot(
      defaults: _ref.read(settingsProvider).readerPreferences,
      profiles: _ref.read(readerProfilesProvider),
      bookmarks: _ref.read(readerBookmarksProvider),
    );
    return (
      text: LibraryBackup.encode(
        snapshot,
        sources: sources,
        categories: <String>{
          ..._ref.read(categoriesProvider),
          ..._ref.read(watchingCategoriesProvider),
        }.toList(),
        reader: reader,
      ),
      snapshot: snapshot,
    );
  }

  /// Restores the shelf and reinstalls the packs the backup was made with.
  Future<RestoreReport> restore(String raw) async {
    final document = LibraryBackup.decodeDocument(raw);
    return restoreDocument(document);
  }

  Future<RestoreReport> restoreDocument(
    BackupDocument document, {
    bool reinstallSources = true,
  }) async {
    if (reinstallSources && document.sources.isNotEmpty) {
      _ref.read(sourcePacksProvider.notifier).addAll(document.sources);
    }
    final report =
        await restoreInto(_ref.read(repositoryProvider), document.snapshot);
    // A name goes back onto the shelf whose works carry it. A name no work
    // carries comes back as a manga category, the shelf it was made on first.
    final restoredWorks = await _ref.read(repositoryProvider).allMedia();
    final readingNames = <String>[];
    final watchingNames = <String>[];
    for (final name in document.categories) {
      final kinds = [
        for (final media in restoredWorks)
          if (media.tags.contains(name)) media.kind,
      ];
      final watchingOnly =
          kinds.isNotEmpty && kinds.every((kind) => !kind.isReading);
      (watchingOnly ? watchingNames : readingNames).add(name);
    }
    await _ref.read(categoriesProvider.notifier).merge(readingNames);
    await _ref.read(watchingCategoriesProvider.notifier).merge(watchingNames);
    await _ref
        .read(readerProfilesProvider.notifier)
        .merge(document.reader.profiles);
    await _ref
        .read(readerBookmarksProvider.notifier)
        .merge(document.reader.bookmarks);
    if (document.reader.defaults case final defaults?) {
      await _ref
          .read(settingsProvider.notifier)
          .restoreReaderDefaultsIfUnset(defaults);
    }
    return report;
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

/// Runs the shelf refresh on launch/resume, at most once per chosen interval.
///
/// Android cannot run a Dart source extension while the app is killed, so this
/// is an in-app schedule, not a promise of work while the app is closed. A
/// manual refresh ignores both the interval and the Wi-Fi rule.
class LibraryAutoRefreshController extends Notifier<DateTime?> {
  static const String _lastKey = 'library_last_refresh_at';

  @override
  DateTime? build() {
    final raw = ref.watch(preferencesProvider)?.getInt(_lastKey);
    return raw == null ? null : DateTime.fromMillisecondsSinceEpoch(raw);
  }

  Future<void> maybeRefresh() async {
    final settings = ref.read(settingsProvider);
    if (!settings.autoRefreshLibrary) return;
    if (ref.read(libraryRefreshProvider).running) return;
    final network = ref.read(networkProvider).value ?? NetworkKind.unknown;
    if (network == NetworkKind.none) return;
    if (settings.updateWifiOnly && network == NetworkKind.mobile) return;
    final last = state;
    if (last != null &&
        DateTime.now().difference(last) <
            Duration(hours: settings.refreshIntervalHours)) {
      return;
    }
    await refreshNow();
  }

  Future<void> refreshNow() async {
    if (ref.read(libraryRefreshProvider).running) return;
    await ref.read(libraryRefreshProvider.notifier).refreshAll();
    final progress = ref.read(libraryRefreshProvider);
    // A total failure (offline, every source down) must not silence the next
    // attempt for a whole interval; a partial refresh is still worth recording.
    if (progress.total > 0 && progress.done == 0) return;
    final now = DateTime.now();
    state = now;
    await ref
        .read(preferencesProvider)
        ?.setInt(_lastKey, now.millisecondsSinceEpoch);
  }
}

final NotifierProvider<LibraryAutoRefreshController, DateTime?>
    libraryAutoRefreshProvider =
    NotifierProvider<LibraryAutoRefreshController, DateTime?>(
  LibraryAutoRefreshController.new,
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
    await _ref.read(backupControllerProvider).restoreDocument(
          document,
          reinstallSources: false,
        );
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
