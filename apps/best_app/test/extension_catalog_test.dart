import 'package:best_app/src/extension_host.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ExtensionSourceInfo', () {
    test('reads an anime bundle from the host catalog', () {
      final info = ExtensionSourceInfo.fromMap(<String, dynamic>{
        'sourceId': 4222017068256633289,
        'name': 'AniZone',
        'kind': 'anime',
        'lang': 'all',
        'packageName': 'eu.kanade.tachiyomi.animeextension.all.anizone',
        'supportsLatest': true,
        'nsfw': false,
        'versionName': '16.15',
      });

      expect(info.isAnime, isTrue);
      expect(info.name, 'AniZone');
      expect(info.language, 'all');
    });

    test('defaults to manga when the host sends no kind', () {
      final info = ExtensionSourceInfo.fromMap(<String, dynamic>{
        'sourceId': 2499283573021220255,
        'name': 'MangaDex',
        'lang': 'en',
      });

      expect(info.isAnime, isFalse);
      expect(info.kind, 'manga');
    });
  });

  group('repository inventory', () {
    test('keeps an incompatible installed package independently of sources',
        () {
      final item = InstalledExtension.fromMap({
        'packageName': 'eu.kanade.tachiyomi.animeextension.all.test',
        'kind': 'anime',
        'versionCode': 16015,
        'versionName': '16.15',
      });
      final catalog = ExtensionCatalog(
          sources: const [], problems: const [], installed: [item]);
      expect(catalog.installed.single.versionCode, 16015);
    });
    test('the two repositories are different indexes', () {
      expect(
        ExtensionRepository.defaultAnimeIndexUrl,
        isNot(ExtensionRepository.defaultIndexUrl),
      );
    });
  });
}
