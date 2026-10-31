import 'dart:convert';

import 'package:best_app/src/app.dart';
import 'package:best_app/src/providers.dart';
import 'package:best_data/best_data.dart';
import 'package:best_domain/best_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _pumpApp(
  WidgetTester tester, {
  LibraryRepository? repository,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final preferences = await SharedPreferences.getInstance();
  final scope = ProviderScope(
    overrides: [
      repositoryProvider
          .overrideWithValue(repository ?? MemoryLibraryRepository()),
      preferencesProvider.overrideWithValue(preferences),
    ],
    child: const BestApp(),
  );
  await tester.pumpWidget(scope);
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(
    tester.element(find.byType(BestApp)),
    listen: false,
  );
}

void main() {
  testWidgets('the shelf renders, then flips to Arabic and RTL', (
    tester,
  ) async {
    final repository = MemoryLibraryRepository();
    final media = Media(
      ref: const SourceRef('test', 'blue-echo'),
      title: 'Blue Echo',
      kind: MediaKind.manhwa,
      inLibrary: true,
      addedAt: 1,
      lastOpenedAt: 2,
    );
    await repository.saveMedia(media);
    await repository.saveUnits([
      MediaUnit(
        mediaId: media.id,
        url: 'unit-1',
        number: 1,
        title: 'Chapter 1',
        kind: UnitKind.chapter,
        pageCount: 10,
      ),
    ]);
    await repository.saveProgress(
      UnitProgress(
        unitId: '${media.id}::unit-1',
        position: 3,
        total: 10,
        updatedAt: 5,
      ),
    );

    final container = await _pumpApp(tester, repository: repository);

    expect(find.text('Blue Echo'), findsWidgets);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Library'), findsWidgets);
    expect(find.text('Page 4 of 10'), findsOneWidget);

    container.read(settingsProvider.notifier).setLanguage('ar');
    await tester.pumpAndSettle();

    expect(find.text('متابعة'), findsOneWidget);
    expect(find.text('المكتبة'), findsWidgets);
    expect(
      Directionality.of(tester.element(find.text('بست'))),
      TextDirection.rtl,
    );
  });

  testWidgets('downloads tab lists a finished chapter', (tester) async {
    final repository = MemoryLibraryRepository();
    final media = Media(
      ref: const SourceRef('test', 'blue-echo'),
      title: 'Blue Echo',
      kind: MediaKind.manhwa,
    );
    await repository.saveMedia(media);
    await repository.saveDownload(
      DownloadTask(
        unitId: '${media.id}::unit-1',
        mediaId: media.id,
        sourceId: media.ref.sourceId,
        mediaUrl: media.ref.url,
        unitUrl: 'unit-1',
        mediaTitle: media.title,
        unitTitle: 'Chapter 1',
        total: 10,
        completed: 10,
        status: DownloadStatus.done,
        updatedAt: 10,
      ),
    );

    await _pumpApp(tester, repository: repository);
    await tester.tap(find.text('Downloads').last);
    await tester.pumpAndSettle();

    expect(find.text('Blue Echo'), findsOneWidget);
    expect(find.text('Chapter 1'), findsOneWidget);
    expect(find.text('Downloaded'), findsOneWidget);
  });

  testWidgets('the guide opens a series and a readable page', (tester) async {
    await _pumpApp(tester);

    expect(find.text('Your shelf is waiting'), findsOneWidget);
    await tester.tap(find.text('Open the guide'));
    await tester.pumpAndSettle();

    expect(find.text('ظل الغابة'), findsWidgets);
    expect(find.text('Start reading'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Chapter 1'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chapter 1'));
    await tester.pumpAndSettle();

    expect(find.textContaining('صفحة 1'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Language'), findsOneWidget);
  });

  testWidgets('a drama offers the player, not the page reader', (
    tester,
  ) async {
    await _pumpApp(tester);

    await tester.tap(find.text('Browse').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Neon Seoul'));
    await tester.pumpAndSettle();

    expect(find.text('Neon Seoul'), findsWidgets);
    expect(find.text('Watch now'), findsOneWidget);
    expect(find.text('Start reading'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('Episode 1'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Episodes'), findsOneWidget);
    expect(find.text('Episode 1'), findsOneWidget);
  });

  testWidgets('a source pack is validated, installed and listed', (
    tester,
  ) async {
    final container = await _pumpApp(tester);

    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Add a source pack'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    // The bottom bar overlays the last row, so nudge the list once more.
    await tester.drag(find.byType(ListView), const Offset(0, -160));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add a source pack'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '{"id":"example"');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.textContaining('not valid JSON'), findsOneWidget);

    final pack = {
      'id': 'example',
      'name': 'Example',
      'language': 'ar',
      'baseUrl': 'https://api.example.com',
      'routes': {
        'popular': '/popular?page={page}',
        'search': '/search?q={query}&page={page}',
        'chapters': '/series/{id}/chapters',
        'pages': '/chapter/{id}/pages',
      },
      'map': {
        'media': {'list': 'data', 'id': 'slug', 'title': 'title'},
        'unit': {'list': 'chapters', 'id': 'id'},
        'page': {'list': 'pages', 'url': 'url'},
      },
    };
    await tester.enterText(find.byType(TextField), jsonEncode(pack));
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(find.text('Example'), findsOneWidget);
    expect(container.read(sourcePacksProvider).single.id, 'example');
    expect(container.read(sourceRegistryProvider).byId('example'), isNotNull);
  });
}
