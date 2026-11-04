import 'dart:convert';

import 'package:best_app/src/l10n/generated/app_localizations.dart';
import 'package:best_app/src/providers.dart';
import 'package:best_app/src/screens/about_screen.dart';
import 'package:best_app/src/updates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, Object?> _release(String tag) => {
      'tag_name': tag,
      'body': '## What is new\n\n- Reader layout\n- Faster shelf',
      'html_url': 'https://github.com/PanditJi-9/best/releases/tag/$tag',
      'published_at': '2026-11-04T07:00:00Z',
      'prerelease': false,
      'assets': [
        {
          'name': 'app-release.apk',
          'browser_download_url': 'https://example.test/app-release.apk',
        },
      ],
    };

Future<ProviderContainer> _container(
  http.Client client, {
  String installed = '1.0.0',
  String build = '19',
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final preferences = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [
      preferencesProvider.overrideWithValue(preferences),
      appBuildProvider.overrideWith(
        (ref) async => (version: installed, build: build),
      ),
      updateCheckerProvider.overrideWithValue(
        UpdateChecker(client: client, endpoint: Uri.parse('https://api.test')),
      ),
    ],
  );
}

Future<void> _pump(
  WidgetTester tester,
  ProviderContainer container, {
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const AboutScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('About shows the installed build and a newer release', (
    tester,
  ) async {
    final container = await _container(
      MockClient(
        (_) async => http.Response(jsonEncode(_release('v1.1.0')), 200),
      ),
    );
    addTearDown(container.dispose);

    await _pump(tester, container);

    expect(find.text('Version 1.0.0 · build 19'), findsOneWidget);
    expect(find.text('Version 1.1.0 is available'), findsOneWidget);
    expect(find.text('Download update'), findsOneWidget);
    expect(find.textContaining('Reader layout'), findsOneWidget);
    expect(find.text('About Best'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('About says the build is current', (tester) async {
    final container = await _container(
      MockClient(
        (_) async => http.Response(jsonEncode(_release('v1.0.0')), 200),
      ),
    );
    addTearDown(container.dispose);

    await _pump(tester, container);

    expect(find.text('You are on the latest version'), findsOneWidget);
    expect(find.text('Download update'), findsNothing);
    expect(find.text('What\'s new'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('About fits a 320 dp phone in Arabic', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = await _container(
      MockClient(
        (_) async => http.Response(jsonEncode(_release('v1.1.0')), 200),
      ),
    );
    addTearDown(container.dispose);

    await _pump(tester, container, locale: const Locale('ar'));

    expect(find.text('الإصدار 1.0.0 · البناء 19'), findsOneWidget);
    expect(find.text('الإصدار 1.1.0 متاح'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.text('الإصدار 1.1.0 متاح'))),
      TextDirection.rtl,
    );
    expect(tester.takeException(), isNull, reason: 'About overflows at 320 dp');
  });

  testWidgets('a failed check explains itself without inventing a release', (
    tester,
  ) async {
    final container = await _container(
      MockClient((_) async => http.Response('{}', 503)),
    );
    addTearDown(container.dispose);

    await _pump(tester, container);

    expect(find.text("Couldn't check for updates"), findsOneWidget);
    expect(
      find.text('GitHub returned an error. Try again later.'),
      findsOneWidget,
    );
    expect(find.text('Download update'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
