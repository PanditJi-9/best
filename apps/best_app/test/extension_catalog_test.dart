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

  group('starter sets', () {
    test('anime and manga bundles are separate allowlists', () {
      expect(ExtensionInstaller.starterPackages, isNotEmpty);
      expect(ExtensionInstaller.animeStarterPackages, isNotEmpty);
      expect(
        ExtensionInstaller.starterPackages
            .where((pkg) => ExtensionInstaller.animeStarterPackages.contains(pkg)),
        isEmpty,
      );
      // Anime bundles declare their entry point under their own metadata key,
      // which is exactly what the package name encodes.
      for (final pkg in ExtensionInstaller.animeStarterPackages) {
        expect(pkg, contains('animeextension'));
      }
      for (final pkg in ExtensionInstaller.starterPackages) {
        expect(pkg, isNot(contains('animeextension')));
      }
    });

    test('the two repositories are different indexes', () {
      expect(
        ExtensionRepository.defaultAnimeIndexUrl,
        isNot(ExtensionRepository.defaultIndexUrl),
      );
    });
  });
}
