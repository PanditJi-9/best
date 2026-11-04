import 'dart:convert';

import 'package:best_app/src/providers.dart';
import 'package:best_app/src/updates.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, Object?> _release({
  String tag = 'v1.1.0',
  String body =
      '## What is new\n\n- **Reader** layout\n- [Notes](https://example.test/notes)',
  bool prerelease = false,
  List<Map<String, Object?>> assets = const [
    {
      'name': 'app-release.apk',
      'browser_download_url': 'https://example.test/app-release.apk',
    },
  ],
}) =>
    {
      'tag_name': tag,
      'body': body,
      'html_url': 'https://github.com/PanditJi-9/best/releases/tag/$tag',
      'published_at': '2026-11-04T07:00:00Z',
      'prerelease': prerelease,
      'assets': assets,
    };

UpdateChecker _checker(
  MockClient client, {
  Uri? endpoint,
}) =>
    UpdateChecker(
      client: client,
      endpoint: endpoint ?? Uri.parse('https://api.test/releases/latest'),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('versions', () {
    test('parse Flutter and tag spellings', () {
      expect(AppVersion.tryParse('v0.11.0+18').toString(), '0.11.0+18');
      expect(AppVersion.tryParse('1.0').toString(), '1.0.0');
      expect(AppVersion.tryParse('v1.0.0-beta.2').toString(), '1.0.0-beta.2');
      expect(AppVersion.tryParse('nightly'), isNull);
      expect(AppVersion.tryParse(''), isNull);
    });

    test('compare core, pre-release and build numbers', () {
      expect(isNewerVersion('1.0.0', '0.11.0'), isTrue);
      expect(isNewerVersion('v1.0.1', '1.0.0+19'), isTrue);
      expect(isNewerVersion('1.0.0+20', '1.0.0+19'), isTrue);
      expect(isNewerVersion('1.0.0', '1.0.0+19'), isFalse);
      expect(isNewerVersion('1.0.0+19', '1.0.0+19'), isFalse);
      expect(isNewerVersion('1.0.0-beta', '1.0.0'), isFalse);
      expect(isNewerVersion('1.0.0', '1.0.0-beta'), isTrue);
      expect(isNewerVersion('latest', '1.0.0'), isFalse);
      expect(isNewerVersion('1.0.0', 'not-a-version'), isFalse);
    });
  });

  group('release parsing', () {
    test('picks the APK asset and keeps a usable page', () {
      final release = AppRelease.fromJson(_release(
        assets: const [
          {
            'name': 'checksums.txt',
            'browser_download_url': 'https://example.test/checksums.txt',
          },
          {
            'name': 'app-release.apk',
            'browser_download_url': 'https://example.test/app-release.apk',
          },
        ],
      ));
      expect(release, isNotNull);
      expect(release!.version, '1.1.0');
      expect(release.apkUrl, 'https://example.test/app-release.apk');
      expect(release.pageUrl, contains('v1.1.0'));
      expect(release.publishedAt, isNotNull);
      expect(release.prerelease, isFalse);
    });

    test('ignores an APK on an untrusted scheme', () {
      final release = AppRelease.fromJson(_release(
        assets: const [
          {
            'name': 'app-release.apk',
            'browser_download_url': 'http://example.test/app-release.apk',
          },
        ],
      ));
      expect(release!.apkUrl, isNull);
    });

    test('rejects an object without a tag', () {
      expect(AppRelease.fromJson(const {'body': 'no tag'}), isNull);
      expect(AppRelease.fromJson('nope'), isNull);
    });

    test('release notes lose Markdown syntax but keep their words', () {
      final release = AppRelease.fromJson(_release());
      expect(release!.notes, contains('What is new'));
      expect(release.notes, contains('• Reader layout'));
      expect(release.notes, contains('Notes (https://example.test/notes)'));
      expect(release.notes, isNot(contains('**')));
      expect(release.notes, isNot(contains('##')));
    });
  });

  group('checker', () {
    test('reads the latest release with a User-Agent', () async {
      final client = MockClient((request) async {
        expect(request.headers['User-Agent'], 'Best-App');
        expect(request.headers['Accept'], 'application/vnd.github+json');
        return http.Response(jsonEncode(_release()), 200);
      });
      final release = await _checker(client).latest();
      expect(release.version, '1.1.0');
    });

    test('maps rate limits, missing releases and server errors', () async {
      Future<void> expectFailure(
        int status,
        UpdateFailure failure,
      ) async {
        final client = MockClient((_) async => http.Response('{}', status));
        await expectLater(
          _checker(client).latest(),
          throwsA(
            isA<UpdateException>().having(
              (error) => error.failure,
              'failure',
              failure,
            ),
          ),
        );
      }

      await expectFailure(403, UpdateFailure.rateLimited);
      await expectFailure(429, UpdateFailure.rateLimited);
      await expectFailure(404, UpdateFailure.notFound);
      await expectFailure(500, UpdateFailure.server);
    });

    test('a broken body is malformed, not an empty release', () async {
      final client = MockClient((_) async => http.Response('<html>', 200));
      await expectLater(
        _checker(client).latest(),
        throwsA(
          isA<UpdateException>().having(
            (error) => error.failure,
            'failure',
            UpdateFailure.malformed,
          ),
        ),
      );
    });

    test('a dropped connection is a network failure', () async {
      final client = MockClient((_) async {
        throw http.ClientException('offline');
      });
      await expectLater(
        _checker(client).latest(),
        throwsA(
          isA<UpdateException>().having(
            (error) => error.failure,
            'failure',
            UpdateFailure.network,
          ),
        ),
      );
    });

    test('a pre-release is never offered as the latest build', () async {
      final client = MockClient(
        (_) async => http.Response(jsonEncode(_release(prerelease: true)), 200),
      );
      await expectLater(
        _checker(client).latest(),
        throwsA(
          isA<UpdateException>().having(
            (error) => error.failure,
            'failure',
            UpdateFailure.notFound,
          ),
        ),
      );
    });
  });

  group('controller', () {
    test('reports a newer release and remembers the check', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final preferences = await SharedPreferences.getInstance();
      final client = MockClient(
        (_) async => http.Response(jsonEncode(_release()), 200),
      );
      final container = ProviderContainer(
        overrides: [
          preferencesProvider.overrideWithValue(preferences),
          appBuildProvider.overrideWith(
            (ref) async => (version: '1.0.0', build: '19'),
          ),
          updateCheckerProvider.overrideWithValue(_checker(client)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(updateProvider.notifier).check(force: true);
      final status = container.read(updateProvider).value;
      expect(status, isNotNull);
      expect(status!.available, isTrue);
      expect(status.latestVersion, '1.1.0');
      expect(status.currentVersion, '1.0.0+19');
      expect(preferences.getInt('app_update_checked_at'), isNotNull);
    });

    test('the automatic check respects the six-hour gap', () async {
      final checkedAt = DateTime.now().millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues(
        <String, Object>{'app_update_checked_at': checkedAt},
      );
      final preferences = await SharedPreferences.getInstance();
      var requests = 0;
      final client = MockClient((_) async {
        requests++;
        return http.Response(jsonEncode(_release()), 200);
      });
      final container = ProviderContainer(
        overrides: [
          preferencesProvider.overrideWithValue(preferences),
          appBuildProvider.overrideWith(
            (ref) async => (version: '1.0.0', build: '19'),
          ),
          updateCheckerProvider.overrideWithValue(_checker(client)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(updateProvider.notifier).check();
      expect(requests, 0);
      expect(container.read(updateProvider).value, isNull);
    });
  });
}
