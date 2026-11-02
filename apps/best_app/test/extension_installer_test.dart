import 'package:best_app/src/extension_host.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

ExtensionEntry _entry(String package) => ExtensionEntry(
      name: package.split('.').last,
      packageName: package,
      apkUrl: 'https://example.invalid/$package.apk',
      language: 'all',
      version: '1.0',
      nsfw: false,
    );

class _Repository extends ExtensionRepository {
  _Repository(List<String> packages)
      : entries = packages.map(_entry).toList(),
        super(
          indexUrl: 'https://example.invalid/index.json',
          client: MockClient((_) async => http.Response('[]', 200)),
        );

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

class _Host extends ExtensionHost {
  final loaded = <String>{};
  final failedDownloads = <String>{};
  final incompatible = <String>{};
  final attempts = <String>[];
  bool available = true;

  @override
  bool get isAvailable => available;

  @override
  Future<ExtensionCatalog> catalog() async => ExtensionCatalog(
        sources: [
          for (final package in loaded)
            ExtensionSourceInfo(
              sourceId: package.hashCode,
              name: package.split('.').last,
              language: 'all',
              packageName: package,
              supportsLatest: true,
              nsfw: false,
              versionName: '1.0',
            ),
        ],
        problems: const [],
      );

  @override
  Future<String?> install(
      {required String url, required String fileName}) async {
    final package = fileName.substring(0, fileName.length - 4);
    attempts.add(package);
    if (failedDownloads.contains(package)) return null;
    if (!incompatible.contains(package)) loaded.add(package);
    return package;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Host host;
  late _Repository manga;
  late _Repository anime;
  late ExtensionInstaller installer;
  late SharedPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    host = _Host();
    manga = _Repository(ExtensionInstaller.starterPackages);
    anime = _Repository(ExtensionInstaller.animeStarterPackages);
    installer = ExtensionInstaller(
      host: host,
      repository: manga,
      animeRepository: anime,
      preferences: preferences,
    );
  });

  test('complete bootstrap loads nine bundles and does not refetch on launch',
      () async {
    expect(await installer.ensureStarterSet(), 9);
    expect(host.loaded.length, 9);
    expect(await installer.ensureStarterSet(), 0);
    expect(manga.reads, 1);
    expect(anime.reads, 1);
  });

  test('partial download retries only missing bundles on the next launch',
      () async {
    final missing = ExtensionInstaller.animeStarterPackages.first;
    host.failedDownloads.add(missing);
    expect(await installer.ensureStarterSet(), 8);
    host.failedDownloads.clear();
    host.attempts.clear();
    expect(await installer.ensureStarterSet(), 1);
    expect(host.attempts, [missing]);
    expect(host.loaded.length, 9);
  });

  test('a dead anime index does not block manga or suppress the next retry',
      () async {
    anime.reachable = false;
    expect(await installer.ensureStarterSet(), 5);
    anime.reachable = true;
    host.attempts.clear();
    expect(await installer.ensureStarterSet(), 4);
    expect(host.attempts, ExtensionInstaller.animeStarterPackages);
  });

  test('a stored APK that does not load is not bootstrap success', () async {
    final missing = ExtensionInstaller.animeStarterPackages.last;
    host.incompatible.add(missing);
    expect(await installer.ensureStarterSet(), 9);
    expect(host.loaded.length, 8);
    host.incompatible.clear();
    host.attempts.clear();
    expect(await installer.ensureStarterSet(), 1);
    expect(host.attempts, [missing]);
  });

  test('empty guard index is retried instead of hiding the entire anime shelf',
      () async {
    final offered = anime.entries;
    anime.entries = [];
    expect(await installer.ensureStarterSet(), 5);
    anime.entries = offered;
    expect(await installer.ensureStarterSet(), 4);
  });

  test(
      'old partial-success marker is rechecked without reinstalling loaded sources',
      () async {
    await preferences.setBool('extensions_bootstrapped_v2', true);
    host.loaded.addAll(ExtensionInstaller.starterPackages);
    expect(await installer.ensureStarterSet(), 4);
    expect(host.attempts, ExtensionInstaller.animeStarterPackages);
  });

  test('failed manual retry clears success and allows automatic recovery',
      () async {
    await installer.ensureStarterSet();
    final missing = ExtensionInstaller.animeStarterPackages.first;
    host.loaded.remove(missing);
    anime.reachable = false;
    expect(await installer.ensureStarterSet(force: true), 0);
    anime.reachable = true;
    expect(await installer.ensureStarterSet(), 1);
    expect(host.loaded.length, 9);
  });

  test('unavailable native host never downloads extensions', () async {
    host.available = false;
    expect(await installer.ensureStarterSet(), 0);
    expect(host.attempts, isEmpty);
    expect(manga.reads, 0);
    expect(anime.reads, 0);
  });
}
