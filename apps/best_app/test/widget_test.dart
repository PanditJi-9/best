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

    // Home is the front door now: the wordmark and the five destinations are
    // on screen before the shelf is.
    expect(find.text('Best'), findsWidgets);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Search all sources'), findsOneWidget);

    // The shelf is one tab away, with its resume rail and real progress.
    await tester.tap(find.text('Library').last);
    await tester.pumpAndSettle();

    expect(find.text('Blue Echo'), findsWidgets);
    expect(find.text('Library'), findsWidgets);
    expect(find.text('Page 4 of 10'), findsOneWidget);

    container.read(settingsProvider.notifier).setLanguage('ar');
    await tester.pumpAndSettle();

    expect(find.text('متابعة'), findsOneWidget);
    expect(find.text('المكتبة'), findsWidgets);
    expect(
      Directionality.of(tester.element(find.text('المكتبة').first)),
      TextDirection.rtl,
    );
  });

  testWidgets('the five destinations fit a 320 dp phone', (tester) async {
    // The emulator is 320 dp wide. Material's default nav label wraps
    // "Downloads" onto two lines at that width, which is a visible defect, so
    // pin the small-phone layout in a test.
    //
    // The test font draws every glyph one em wide, which makes this double as a
    // large-text-scale stress test: anything that fits here also fits a reader
    // who has raised their system font size.
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = await _pumpApp(tester);

    for (final label in [
      'Home',
      'Library',
      'Browse',
      'Downloads',
      'Settings',
    ]) {
      expect(find.text(label), findsWidgets, reason: '$label tab is missing');
    }
    expect(tester.takeException(), isNull, reason: 'Home overflows at 320 dp');

    // Every destination has to survive the narrow phone, not just Home: the
    // library header, the source pills and the settings segments are all rows
    // that can overflow.
    for (final label in ['Library', 'Browse', 'Downloads', 'Settings']) {
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: '$label overflows at 320 dp',
      );
    }

    // Arabic is the other first-class locale and its longest tab is the one
    // that has to fit: check the RTL bar on the same narrow phone.
    container.read(settingsProvider.notifier).setLanguage('ar');
    await tester.pumpAndSettle();
    expect(
      tester.takeException(),
      isNull,
      reason: 'the Arabic bar overflows at 320 dp',
    );
    expect(find.text('التحميلات'), findsWidgets);
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

    // Downloads are grouped by work, so the title appears once in the group
    // header and once on the chapter row.
    expect(find.text('Blue Echo'), findsWidgets);
    expect(find.text('Chapter 1'), findsOneWidget);
    expect(find.text('Downloaded'), findsOneWidget);
  });

  testWidgets('the guide opens a series and a readable page', (tester) async {
    await _pumpApp(tester);

    // The empty-shelf card sits under the spotlight and the rails, so reach it
    // the way a reader would instead of assuming it is above the fold.
    await tester.scrollUntilVisible(
      find.text('Open the guide'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

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

    // The series page uses its own glass back control over the hero instead of
    // an app bar, so tap the control a reader would tap.
    await tester.tap(find.byTooltip('Back to series'));
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
    // The scroll stops as soon as the first row is visible, which can leave the
    // section header just above the viewport; pull it back into view.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 80));
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
