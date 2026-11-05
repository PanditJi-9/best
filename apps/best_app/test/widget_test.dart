import 'dart:convert';

import 'package:best_app/src/app.dart';
import 'package:best_app/src/providers.dart';
import 'package:best_data/best_data.dart';
import 'package:best_domain/best_domain.dart';
import 'package:best_ui/best_ui.dart';
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
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
  });
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(
    tester.element(find.byType(BestApp)),
    listen: false,
  );
}

Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(find.text('Menu').last);
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.text('Settings'),
    220,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Settings'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Settings'));
  await tester.pumpAndSettle();
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
    expect(find.byKey(const ValueKey('home-unified-search')), findsOneWidget);
    expect(find.byIcon(Icons.search_rounded), findsOneWidget);

    // The shelf is one tab away, with its resume rail and real progress.
    await tester.tap(find.text('Library').last);
    await tester.pumpAndSettle();

    expect(find.text('Blue Echo'), findsWidgets);
    expect(find.text('Library'), findsWidgets);
    expect(find.text('Page 4 of 10'), findsOneWidget);

    container.read(settingsProvider.notifier).setLanguage('ar');
    await tester.pumpAndSettle();

    expect(find.text('متابعة'), findsOneWidget);
    expect(find.text('مكتبتي'), findsWidgets);
    expect(
      Directionality.of(tester.element(find.text('مكتبتي').first)),
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
      'Database',
      'Library',
      'Downloads',
      'Menu',
    ]) {
      expect(find.text(label), findsWidgets, reason: '$label tab is missing');
    }
    expect(tester.takeException(), isNull, reason: 'Home overflows at 320 dp');

    // Every destination has to survive the narrow phone, not just Home: the
    // library header, the source pills and the settings segments are all rows
    // that can overflow.
    for (final label in ['Database', 'Library', 'Downloads', 'Menu']) {
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
    expect(find.text('Chapter 1'), findsWidgets);
    expect(find.text('Downloaded'), findsWidgets);
  });

  testWidgets('a saved guide opens a series and a readable page',
      (tester) async {
    final repository = MemoryLibraryRepository();
    final guide = await const DemoSource().popular();
    final manga = guide.firstWhere((work) => work.kind.isReading);
    await repository.saveMedia(manga.copyWith(inLibrary: true));
    await _pumpApp(tester, repository: repository);
    await tester.tap(find.text('Library').last);
    await tester.pumpAndSettle();

    // Saved reading material remains one tap from the Library. The fresh Home
    // guide now opens the playable drama, covered separately below.
    await tester.scrollUntilVisible(
      find.text(manga.displayTitle),
      300,
      scrollable: find.descendant(
          of: find.byType(CustomScrollView), matching: find.byType(Scrollable)),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(manga.displayTitle));
    await tester.pumpAndSettle();
    await tester.tap(find.text(manga.displayTitle));
    await tester.pumpAndSettle();

    expect(find.text('ظل الغابة'), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('Chapter 1'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Chapter 1'));
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

    // Settings lives in the Menu tab, one tap from any space.
    await _openSettings(tester);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Language'), findsOneWidget);
  });

  testWidgets('the Menu guide offers the player, not the page reader', (
    tester,
  ) async {
    await _pumpApp(tester);
    // The guide lives in the Menu tab now, and opens the playable drama.
    await tester.tap(find.text('Menu').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Open the guide'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open the guide'));
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
    // Bring the first episode fully on screen.
    await tester.ensureVisible(find.text('Episode 1'));
    await tester.pumpAndSettle();
    // The stat strip names episodes too, so only the section header counts.
    // Finders skip widgets scrolled out of view by default. The header can end
    // up just above the first episode, so search the built tree instead.
    expect(
      find.descendant(
        of: find.byType(SectionHeader, skipOffstage: false),
        matching: find.text('Episodes', skipOffstage: false),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(find.text('Episode 1'), findsOneWidget);
  });

  testWidgets('a source pack is validated, installed and listed', (
    tester,
  ) async {
    final container = await _pumpApp(tester);

    await _openSettings(tester);

    await tester.scrollUntilVisible(
      find.text('Add a source pack'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    // The bottom bar overlays the last row, so nudge the list once more.
    await tester.drag(find.byType(ListView), const Offset(0, -160));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Add a source pack'));
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
    // The "Source added" snackbar dismisses itself after a few seconds. Let it
    // go before the test ends, so no timer is left running.
    await tester.pump(const Duration(seconds: 5));

    expect(find.text('Example'), findsOneWidget);
    expect(container.read(sourcePacksProvider).single.id, 'example');
    expect(container.read(sourceRegistryProvider).byId('example'), isNotNull);
  });

  testWidgets('source pack errors fit a small phone with the keyboard open', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = await _pumpApp(tester);
    await _openSettings(tester);
    await tester.scrollUntilVisible(
      find.text('Add a source pack'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(ListView), const Offset(0, -160));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add a source pack'));
    await tester.pumpAndSettle();

    tester.view.viewInsets = const FakeViewPadding(bottom: 220);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '{');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Add').hitTestable(), findsOneWidget);

    container.read(settingsProvider.notifier).setLanguage('ar');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      Directionality.of(tester.element(find.byType(AlertDialog))),
      TextDirection.rtl,
    );
  });
}
