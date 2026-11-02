import 'dart:convert';

import 'package:best_app/src/extension_host.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, Object> manga(String name, String warning) => {
      'name': name,
      'packageName': 'eu.kanade.tachiyomi.extension.all.${name.toLowerCase()}',
      'resources': {
        'apkUrl':
            'https://github.com/keiyoushi/extensions/releases/download/tag/$name.apk',
        'iconUrl': 'https://cdn.jsdelivr.net/$name.png'
      },
      'versionCode': '106012',
      'versionName': '1.6.12',
      'contentWarning': warning,
      'sources': [
        {
          'name': '$name Arabic',
          'language': 'ar',
          'homeUrl': 'https://$name.test'
        },
        {
          'name': '$name English',
          'language': 'en',
          'homeUrl': 'https://$name.test/en'
        }
      ],
    };
String fullIndex() => jsonEncode({
      'extensionList': {
        'extensions': [
          manga('Safe', 'CONTENT_WARNING_SAFE'),
          manga('Mixed', 'CONTENT_WARNING_MIXED'),
          manga('Adult', 'CONTENT_WARNING_NSFW')
        ]
      }
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'real manga shape preserves numeric code, multilingual sites and warnings',
      () {
    final entries = ExtensionRepository.parse(
        fullIndex(), ExtensionRepository.defaultIndexUrl);
    expect(entries.length, 3);
    expect(entries.where((e) => e.nsfw).map((e) => e.name), ['Adult']);
    final mixed = entries.firstWhere((e) => e.name == 'Mixed');
    expect(mixed.contentWarning, 'mixed');
    expect(mixed.versionCode, 106012);
    expect(mixed.languages, {'ar', 'en'});
    expect(mixed.matches('arabic'), isTrue);
    expect(mixed.matches('mixed.test'), isTrue);
    expect(mixed.iconUrl, startsWith('https://'));
  });
  test('flat anime shape resolves APK and icon and parses source lang/baseUrl',
      () {
    final entries = ExtensionRepository.parse(
        jsonEncode([
          {
            'name': 'Anime',
            'pkg': 'eu.kanade.tachiyomi.animeextension.en.test',
            'apk': 'test.apk',
            'icon': 'test.png',
            'code': 16015,
            'version': '16.15',
            'nsfw': 0,
            'lang': 'en',
            'sources': [
              {'name': 'Site', 'lang': 'en', 'baseUrl': 'https://anime.test'}
            ],
          }
        ]),
        ExtensionRepository.defaultAnimeIndexUrl);
    expect(entries.single.apkUrl,
        'https://raw.githubusercontent.com/yuzono/anime-repo/repo/apk/test.apk');
    expect(entries.single.kind, 'anime');
    expect(entries.single.versionCode, 16015);
    expect(entries.single.sources.single.homeUrl, 'https://anime.test');
  });
  test(
      'large index stays one row per package and keeps over 1000 genuine choices',
      () {
    final entries = ExtensionRepository.parse(
        jsonEncode([
          for (var i = 0; i < 1448; i++)
            manga('Site$i', 'CONTENT_WARNING_SAFE'),
          manga('Site0', 'CONTENT_WARNING_SAFE'),
        ]),
        ExtensionRepository.defaultIndexUrl);
    expect(entries.length, 1448);
    expect(entries.fold<int>(0, (n, e) => n + e.sources.length), 2896);
  });
  test('guard, empty, invalid package and malformed JSON are rejected', () {
    for (final body in [
      '[]',
      '{}',
      'oops',
      jsonEncode([
        {'name': 'Guard', 'pkg': 'fake', 'code': 1}
      ])
    ]) {
      expect(
          () => ExtensionRepository.parse(
              body, ExtensionRepository.defaultIndexUrl),
          throwsFormatException);
    }
  });
  test('valid cached index survives offline and malformed upstream responses',
      () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    var response = fullIndex();
    var offline = false;
    final repo = ExtensionRepository(
        indexUrl: ExtensionRepository.defaultIndexUrl,
        preferences: preferences,
        client: MockClient((_) async {
          if (offline) throw StateError('offline');
          return http.Response(response, 200);
        }));
    expect((await repo.fetch()).length, 3);
    response = '[]';
    expect((await repo.fetch()).length, 3);
    expect(repo.fromCache, isTrue);
    offline = true;
    expect((await repo.fetch()).length, 3);
    expect(repo.fromCache, isTrue);
    expect(repo.lastError, contains('offline'));
  });
}
