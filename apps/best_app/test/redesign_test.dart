import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:best_app/src/app.dart';
import 'package:best_app/src/l10n/generated/app_localizations.dart';
import 'package:best_app/src/meta/meta_models.dart';
import 'package:best_app/src/meta/meta_providers.dart';
import 'package:best_app/src/navigation.dart';
import 'package:best_app/src/network.dart';
import 'package:best_app/src/providers.dart';
import 'package:best_app/src/screens/meta_search_screen.dart';
import 'package:best_data/best_data.dart';
import 'package:best_domain/best_domain.dart';
import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _work = Media(
  ref: const SourceRef('test', 'blue'),
  title: 'Blue Echo',
  kind: MediaKind.manhwa,
  inLibrary: true,
);

final _fresh = Media(
  ref: const SourceRef('test', 'fresh'),
  title: 'A new story',
  kind: MediaKind.manhwa,
);

class _Source implements SourceAdapter {
  @override
  String get id => 'test';
  @override
  String get name => 'Test source';
  @override
  String get language => 'all';
  @override
  Future<List<Media>> popular({int page = 1}) async => [_fresh];
  @override
  Future<List<Media>> search(String query, {int page = 1}) async => [_fresh];
  @override
  Future<Media> details(Media media) async => media;
  @override
  Future<List<MediaUnit>> units(Media media) async => [];
  @override
  Future<List<MediaResource>> resources(MediaUnit unit) async => [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    WidgetController.hitTestWarningShouldBeFatal = true;
    for (final font in [
      (
        BestFonts.text,
        'packages/best_ui/assets/fonts/IBMPlexSansArabic-Regular.ttf'
      ),
      (BestFonts.display, 'packages/best_ui/assets/fonts/Amiri-Regular.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
  });

  final capture = GlobalKey();
  void viewport(WidgetTester tester, {double width = 390}) {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> image(WidgetTester tester, String name) async {
    await tester.pump();
    await tester.runAsync(() async {
      final boundary =
          capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final rendered = await boundary.toImage();
      final bytes = await rendered.toByteData(format: ui.ImageByteFormat.png);
      rendered.dispose();
      await Directory('build').create(recursive: true);
      await File('build/redesign-$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  Future<void> openSearch(
    WidgetTester tester, {
    required Future<MetaSearchResults> Function(String) search,
    bool local = true,
    String locale = 'en',
    double width = 390,
  }) async {
    viewport(tester, width: width);
    final repository = MemoryLibraryRepository();
    if (local) await repository.saveMedia(_work);
    final router = GoRouter(initialLocation: Routes.metaSearch, routes: [
      GoRoute(
          path: Routes.metaSearch,
          builder: (context, state) => const MetaSearchScreen()),
      GoRoute(
          path: Routes.browse,
          builder: (_, state) => Scaffold(
                body: Text('Forwarded: ${state.uri.queryParameters['q']}'),
              )),
    ]);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
      await repository.close();
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repository),
        metaSearchProvider.overrideWith((ref, query) => search(query)),
      ],
      child: RepaintBoundary(
          key: capture,
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            theme: bestTheme(Brightness.dark),
            locale: Locale(locale),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            routerConfig: router,
          )),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Blue');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
  }

  testWidgets(
      'local shelf and source forwarding survive online loading and failure',
      (tester) async {
    final pending = Completer<MetaSearchResults>();
    await openSearch(tester, search: (_) => pending.future);
    expect(find.text('Blue Echo'), findsOneWidget);
    expect(find.text('On your shelf'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await image(tester, 'search-loading-en');
    pending.completeError(StateError('Catalogue offline'));
    await tester.pumpAndSettle();
    expect(find.text('Blue Echo'), findsOneWidget);
    expect(find.textContaining('Catalogue offline'), findsOneWidget);
    await tester.tap(find.text('Search your sources for “Blue”'));
    await tester.pumpAndSettle();
    expect(find.text('Forwarded: Blue'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'empty catalogue keeps named failures and source fallback at 320 RTL',
      (tester) async {
    await openSearch(
      tester,
      width: 320,
      locale: 'ar',
      local: false,
      search: (query) async => MetaSearchResults(query: query, failures: const {
        MetaSource.anilist: 'offline',
        MetaSource.hwa: 'timeout',
      }),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('AniList'), findsWidgets);
    expect(find.textContaining('hwa.so'), findsWidgets);
    expect(Directionality.of(tester.element(find.byType(TextField))),
        TextDirection.rtl);
    await image(tester, 'search-empty-ar-320');
    await tester.tap(find.text('ابحث في مصادرك عن «Blue»'));
    await tester.pumpAndSettle();
    expect(find.text('Forwarded: Blue'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('clearing or changing query never leaks previous local matches',
      (tester) async {
    await openSearch(tester, search: (q) async => MetaSearchResults(query: q));
    await tester.pumpAndSettle();
    expect(find.text('Blue Echo'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Missing');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(find.text('Blue Echo'), findsNothing);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.textContaining('Search your sources for'), findsNothing);
    expect(find.text('Blue Echo'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final locale in ['en', 'ar']) {
    testWidgets(
        '$locale personal room, saved layout and download filters render coherently',
        (tester) async {
      viewport(tester, width: locale == 'ar' ? 320 : 390);
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final repository = MemoryLibraryRepository();
      await repository.saveMedia(_work);
      final unit = MediaUnit(
          mediaId: _work.id,
          url: 'chapter-1',
          number: 1,
          title: 'Chapter 1',
          kind: UnitKind.chapter,
          pageCount: 20);
      await repository.saveUnits([unit]);
      await repository.saveProgress(
          UnitProgress(unitId: unit.id, position: 4, total: 20, updatedAt: 1));
      await repository.saveDownload(DownloadTask(
        unitId: unit.id,
        mediaId: _work.id,
        sourceId: 'test',
        mediaUrl: 'blue',
        unitUrl: unit.url,
        mediaTitle: _work.title,
        unitTitle: unit.title,
        status: DownloadStatus.done,
        completed: 20,
        total: 20,
        bytes: 1048576,
        updatedAt: 1,
      ));
      await tester.pumpWidget(ProviderScope(overrides: [
        repositoryProvider.overrideWithValue(repository),
        preferencesProvider.overrideWithValue(preferences),
        networkProvider.overrideWith((ref) => Stream.value(NetworkKind.none)),
        sourceRegistryProvider
            .overrideWithValue(SourceRegistry.fixed([_Source()])),
        discoverProvider.overrideWith((ref) async =>
            DiscoverFeed(works: [_fresh], latest: [_fresh], live: true)),
        rankingsProvider.overrideWith(
            (ref) async => const Rankings(works: [], live: false)),
      ], child: RepaintBoundary(key: capture, child: const BestApp())));
      final container =
          ProviderScope.containerOf(tester.element(find.byType(BestApp)));
      container.read(settingsProvider.notifier).setLanguage(locale);
      container
          .read(settingsProvider.notifier)
          .setThemeMode(locale == 'en' ? ThemeMode.dark : ThemeMode.light);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await repository.close();
      });
      await tester.pumpAndSettle();
      final l10n =
          AppLocalizations.of(tester.element(find.byType(Scaffold).first));
      expect(find.text('Blue Echo'), findsOneWidget);
      expect(find.byKey(const ValueKey('home-unified-search')).hitTestable(),
          findsOneWidget);
      await image(tester, 'home-$locale');
      await tester.scrollUntilVisible(find.text(_fresh.title).first, 180,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await image(tester, 'discovery-$locale');
      await tester.tap(find.text(l10n.navLibrary).last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(l10n.libraryListView));
      await tester.pumpAndSettle();
      expect(preferences.getBool('library.grid'), isFalse);
      await image(tester, 'library-$locale');
      await tester.tap(find.text(l10n.navDownloads).last);
      await tester.pumpAndSettle();
      expect(find.text('Chapter 1'), findsWidgets);
      await image(tester, 'downloads-$locale');
      final queueFilter = find.text('${l10n.downloadsInProgress} · 0');
      await tester.ensureVisible(queueFilter);
      await tester.pumpAndSettle();
      await tester.tap(queueFilter);
      await tester.pumpAndSettle();
      expect(find.text(l10n.downloadFilterEmpty), findsOneWidget);
      expect((await repository.downloads()).single.isFinished, isTrue);
      await image(tester, 'downloads-filter-empty-$locale');
      await tester.tap(find.text(l10n.downloadsClearSearch));
      await tester.pumpAndSettle();
      expect(find.text('Chapter 1'), findsWidgets);
      await tester.tap(find.text(l10n.navMenu).last);
      await tester.pumpAndSettle();
      expect(find.text(l10n.openGuide).hitTestable(), findsOneWidget);
      expect(find.text(l10n.mangaSourcesTitle).hitTestable(), findsOneWidget);
      await image(tester, 'menu-$locale');
      await tester.tap(find.text(l10n.navLibrary).last);
      await tester.pumpAndSettle();
      expect(find.byTooltip(l10n.libraryGridView), findsOneWidget);
      await tester.tap(find.text(l10n.navHome).last);
      await tester.pumpAndSettle();
      // Home remembers its discovery scroll position. Scroll the lazy list
      // back until the search entry is built, just as a reader would.
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('home-unified-search')),
        -240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const ValueKey('home-unified-search')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.searchEverything), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
