import 'dart:async';

import 'package:best_app/src/extension_host.dart';
import 'package:best_app/src/providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

ExtensionEntry entry(String name,
        {int code = 10, String kind = 'manga'}) =>
    ExtensionEntry(
        name: name,
        packageName:
            'eu.kanade.tachiyomi.${kind == 'anime' ? 'animeextension' : 'extension'}.all.$name',
        apkUrl: 'https://example.invalid/$name.apk',
        language: 'all',
        version: '1.$code',
        versionCode: code,
        nsfw: false,
        kind: kind,
        repositoryUrl: kind == 'anime' ? ExtensionRepository.defaultAnimeIndexUrl : ExtensionRepository.defaultIndexUrl,
        sources: [
          ExtensionSite(
              name: name, language: 'all', homeUrl: 'https://example.invalid')
        ]);

class Repository extends ExtensionRepository {
  Repository(this.entries)
      : super(
            indexUrl: 'https://example.invalid/index.json',
            client: MockClient((_) async => http.Response('[]', 200)));
  List<ExtensionEntry> entries;
  bool reachable = true;
  int reads = 0;
  @override
  Future<List<ExtensionEntry>> fetch() async {
    reads++;
    if (!reachable) throw StateError('offline');
    return entries;
  }
}

class Host extends ExtensionHost {
  final inventory = <String, InstalledExtension>{};
  final attempts = <String>[];
  final failed = <String>{};
  bool available = true;
  Completer<void>? download;
  @override
  bool get isAvailable => available;
  void seed(ExtensionEntry entry, {int? code}) {
    inventory[entry.packageName] = InstalledExtension(
        packageName: entry.packageName,
        versionCode: code ?? entry.versionCode,
        versionName: entry.version,
        kind: entry.kind);
  }

  @override
  Future<ExtensionCatalog> catalog() async => ExtensionCatalog(
      sources: const [],
      problems: const [],
      installed: inventory.values.toList());
  @override
  Future<String?> install(
      {required String url,
      required String fileName,
      required String expectedPackage,
      required int expectedVersionCode}) async {
    attempts.add(expectedPackage);
    if (download != null) await download!.future;
    if (failed.contains(expectedPackage)) {
      throw PlatformException(code: 'signature-changed');
    }
    inventory[expectedPackage] = InstalledExtension(
        packageName: expectedPackage,
        versionCode: expectedVersionCode,
        versionName: 'new');
    return expectedPackage;
  }

  @override
  Future<bool> remove(String packageName) async =>
      inventory.remove(packageName) != null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Host host;
  late Repository manga;
  late Repository anime;
  late ExtensionInstaller installer;
  late SharedPreferences preferences;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    host = Host();
    manga = Repository([entry('one'), entry('two')]);
    anime = Repository([entry('anime', kind: 'anime')]);
    installer = ExtensionInstaller(
        host: host,
        repository: manga,
        animeRepository: anime,
        preferences: preferences);
  });

  test('opening inventory or refreshing full directory installs nothing',
      () async {
    final container = ProviderContainer(overrides: [
      extensionHostProvider.overrideWithValue(host),
      extensionInstallerProvider.overrideWithValue(installer)
    ]);
    addTearDown(container.dispose);
    await container.read(extensionCatalogProvider.future);
    expect((await installer.directory()).entries.length, 3);
    expect(host.attempts, isEmpty);
    expect((await installer.checkUpdates()).checked, isFalse);
    expect(host.attempts, isEmpty);
  });
  test('activation forwards expected identity and version for just one choice',
      () async {
    final selected = manga.entries.last;
    expect(await installer.activate(selected), selected.packageName);
    expect(host.inventory[selected.packageName]!.versionCode,
        selected.versionCode);
    expect(host.attempts, [selected.packageName]);
  });
  test('legacy MangaDex works resolve without exposing a ready-made source',
      () {
    final container = ProviderContainer(overrides: [
      extensionHostProvider.overrideWithValue(host),
      extensionInstallerProvider.overrideWithValue(installer),
    ]);
    addTearDown(container.dispose);
    final registry = container.read(sourceRegistryProvider);
    expect(registry.all.where((s) => s.id == 'mangadex'), isEmpty);
    expect(registry.byId('mangadex'), isNotNull);
  });
  test(
      'updates only installed numeric newer versions, including incompatible APKs',
      () async {
    host.seed(manga.entries.first, code: 9);
    host.seed(anime.entries.first, code: 9);
    expect((await installer.checkUpdates()).updated, 2);
    expect(host.attempts,
        [manga.entries.first.packageName, anime.entries.first.packageName]);
    expect(host.inventory.length, 2);
    expect((await installer.checkUpdates()).checked, isFalse);
    expect(manga.reads, 1);
  });
  test('equal versions and repository downgrades are not installed', () async {
    host.seed(manga.entries.first);
    host.seed(manga.entries.last, code: 11);
    expect((await installer.checkUpdates()).updated, 0);
    expect(host.attempts, isEmpty);
  });
  test(
      'retired packages are retained; unavailable index does not block other side',
      () async {
    host.seed(entry('retired'));
    host.seed(anime.entries.first, code: 9);
    manga.reachable = false;
    final result = await installer.checkUpdates();
    expect(result.updated, 1);
    expect(result.errors, isNotEmpty);
    expect(host.inventory.containsKey(entry('retired').packageName), isTrue);
  });
  test('cached indexes remain browsable but never drive automatic updates',
      () async {
    host.seed(manga.entries.first, code: 9);
    manga.fromCache = true;
    expect((await installer.directory()).cached, isTrue);
    expect((await installer.checkUpdates()).updated, 0);
    expect(host.attempts, isEmpty);
  });
  test('signature rejection keeps old version and permits manual retry',
      () async {
    final selected = manga.entries.first;
    host.seed(selected, code: 9);
    host.failed.add(selected.packageName);
    expect((await installer.checkUpdates()).errors.keys,
        contains(selected.packageName));
    expect(host.inventory[selected.packageName]!.versionCode, 9);
    host.failed.clear();
    expect((await installer.checkUpdates(force: true)).updated, 1);
  });
  test('overlapping updates share one download; queued removal wins afterwards',
      () async {
    final selected = manga.entries.first;
    host.seed(selected, code: 9);
    host.download = Completer<void>();
    final first = installer.checkUpdates();
    final second = installer.checkUpdates(force: true);
    final remove = installer.remove(selected.packageName);
    host.download!.complete();
    expect((await first).updated, 1);
    expect((await second).updated, 1);
    expect(await remove, isTrue);
    expect(host.attempts, [selected.packageName]);
    expect(host.inventory, isEmpty);
  });
  test('unavailable host makes no update index or APK requests', () async {
    host.available = false;
    host.seed(manga.entries.first, code: 9);
    expect((await installer.checkUpdates()).checked, isFalse);
    expect(manga.reads, 0);
    expect(host.attempts, isEmpty);
  });
}
