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
  await tester.tap(find.byKey(const ValueKey('home-settings')));
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

    // Home is the front door: the wordmark and the five content destinations
    // are on screen before the shelf is, with settings one tap away.
    expect(find.text('Best'), findsWidgets);
    expect(find.text('Home'), findsWidgets);
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
    // The emulator is 320 dp wide. The test font draws every glyph one em wide,
    // which makes this double as a large-text-scale stress test: anything that
    // fits here also fits a reader who has raised their system font size.
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = await _pumpApp(tester);

    for (final label in [
      'Home',
      'Library',
      'Downloads',
      'Encyclopedia',
      'History',
    ]) {
      expect(find.text(label), findsWidgets, reason: '$label tab is missing');
    }
    expect(tester.takeException(), isNull, reason: 'Home overflows at 320 dp');

    // Every destination has to survive the narrow phone, not just Home.
    for (final label in ['Library', 'Downloads', 'History']) {
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: '$label overflows at 320 dp',
      );
    }

    // The settings screen is pushed from the masthead, so the dock keeps five
    // content destinations and still fits this width.
    await tester.tap(find.text('Home').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-settings')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'Settings overflows');
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Arabic is the other first-class locale and its longest tab is the one
    // that has to fit: check the RTL bar on the same narrow phone.
    container.read(settingsProvider.notifier).setLanguage('ar');
    await tester.pumpAndSettle();
    expect(
      tester.takeException(),
      isNull,
      reason: 'the Arabic bar overflows at 320 dp',
    );
  });

  testWidgets('finished downloads live in their own tab', (tester) async {
    final repository = MemoryLibraryRepository();
    final media = Media(
      ref: const SourceRef('test', 'blue-echo'),
      title: 'Blue Echo',
      kind: MediaKind.manhwa,
      inLibrary: true,
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

    // The shelf stays a shelf: no offline rail and no transfer banner.
    await tester.tap(find.text('Library').last);
    await tester.pumpAndSettle();
    expect(find.text('Ready offline'), findsNothing);

    // Downloads are their own destination, grouped by work with the finished
    // chapters folded inside one card.
    await tester.tap(find.text('Downloads').last);
    await tester.pumpAndSettle();
    expect(find.text('Ready offline'), findsOneWidget);
    expect(find.text('Blue Echo'), findsWidgets);
    expect(find.text('Chapter 1'), findsWidgets);
    expect(find.byKey(const ValueKey('downloads-history')), findsOneWidget);
  });

  testWidgets('settings opens from the home masthead and remembers choices', (
    tester,
  ) async {
    final container = await _pumpApp(tester);
    await _openSettings(tester);

    expect(find.text('Settings'), findsWidgets);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Auto-advance chapters'), findsOneWidget);

    container.read(settingsProvider.notifier).setLanguage('ar');
    await tester.pumpAndSettle();
    expect(find.text('الإعدادات'), findsWidgets);
    expect(
      Directionality.of(tester.element(find.text('الإعدادات').first)),
      TextDirection.rtl,
    );
  });
}
