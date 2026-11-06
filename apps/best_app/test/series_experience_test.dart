import 'dart:io';
import 'dart:ui' as ui;

import 'package:best_app/src/l10n/generated/app_localizations.dart';
import 'package:best_app/src/providers.dart';
import 'package:best_app/src/screens/reader_screen.dart';
import 'package:best_app/src/screens/series_screen.dart';
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

class _Source implements SourceAdapter {
  _Source(this.chapters, {this.fail = false, this.pending});

  final List<MediaUnit> chapters;
  final bool fail;
  final Future<List<MediaUnit>>? pending;
  int unitCalls = 0;
  final resourcesRequested = <String>[];

  @override
  String get id => 'test';
  @override
  String get name => 'Test source';
  @override
  String get language => 'all';
  @override
  Future<Media> details(Media media) async => media;
  @override
  Future<List<Media>> popular({int page = 1}) async => [];
  @override
  Future<List<Media>> search(String query, {int page = 1}) async => [];
  @override
  Future<List<MediaUnit>> units(Media media) async {
    unitCalls++;
    if (fail) throw const HttpException('Offline');
    if (pending != null) return pending!;
    return chapters.reversed.toList();
  }

  @override
  Future<List<MediaResource>> resources(MediaUnit unit) async {
    resourcesRequested.add(unit.url);
    return const [
      SyntheticPage(0, 'First scan'),
      SyntheticPage(1, 'Second scan')
    ];
  }
}

class _Fixture {
  const _Fixture(this.container, this.repository, this.media, this.units,
      this.source, this.router, this.capture);
  final ProviderContainer container;
  final MemoryLibraryRepository repository;
  final Media media;
  final List<MediaUnit> units;
  final _Source source;
  final GoRouter router;
  final GlobalKey capture;
}

Future<_Fixture> _open(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  String language = 'en',
  double textScale = 1,
  bool fail = false,
  bool missing = false,
  bool offlineChapter = false,
  bool inLibrary = true,
  bool realReader = false,
  bool complete = false,
  Future<List<MediaUnit>>? pending,
  Map<int, (int, int)> progress = const {},
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final repository = MemoryLibraryRepository();
  final media = Media(
    ref: const SourceRef('test', 'blue-echo'),
    title: 'Blue Echo',
    nativeTitle: 'صدى أزرق',
    kind: MediaKind.manhwa,
    inLibrary: inLibrary,
    author: 'A storyteller',
    synopsis: 'A short, spoiler-free introduction.',
    genres: const ['Fantasy', 'Adventure'],
  );
  final units = [
    for (var n = 1; n <= 3; n++)
      MediaUnit(
        mediaId: media.id,
        url: 'chapter-$n',
        number: n.toDouble(),
        title: 'Chapter $n',
        kind: UnitKind.chapter,
        pageCount: 10,
      ),
  ];
  await repository.saveMedia(media);
  await repository.saveUnits(units.reversed);
  for (final entry in progress.entries) {
    await repository.saveProgress(UnitProgress(
      unitId: units[entry.key - 1].id,
      position: entry.value.$1,
      total: 10,
      updatedAt: entry.value.$2,
    ));
  }
  if (complete) {
    for (final unit in units) {
      await repository.saveProgress(UnitProgress(
        unitId: unit.id,
        position: 9,
        total: 10,
        completed: true,
        updatedAt: unit.number.toInt(),
      ));
    }
  }
  if (offlineChapter) {
    await repository.saveDownload(DownloadTask(
      unitId: units.first.id,
      mediaId: media.id,
      sourceId: 'test',
      mediaUrl: media.ref.url,
      unitUrl: units.first.url,
      mediaTitle: media.title,
      unitTitle: units.first.title,
      total: 10,
      completed: 10,
      status: DownloadStatus.done,
    ));
  }
  final source = _Source(units, fail: fail, pending: pending);
  final container = ProviderContainer(overrides: [
    preferencesProvider.overrideWithValue(preferences),
    repositoryProvider.overrideWithValue(repository),
    sourceRegistryProvider
        .overrideWithValue(SourceRegistry.fixed(missing ? [] : [source])),
  ]);
  final router = GoRouter(initialLocation: '/series', routes: [
    GoRoute(
        path: '/series',
        builder: (context, state) => const SeriesScreen(
              sourceId: 'test',
              url: 'blue-echo',
            )),
    GoRoute(
        path: '/read',
        builder: (context, state) {
          final query = state.uri.queryParameters;
          return realReader
              ? ReaderScreen(
                  sourceId: 'test',
                  url: 'blue-echo',
                  unitUrl: query['unit']!,
                  fromStart: query['start'] == '1',
                  startAtEnd: query['end'] == '1',
                )
              : Scaffold(
                  body: Text(
                      'Opened ${query['unit']} start=${query['start'] ?? '0'}'));
        }),
    GoRoute(
        path: '/sources',
        builder: (_, state) => const Scaffold(body: Text('Sources screen'))),
    GoRoute(
        path: '/browse',
        builder: (_, state) => const Scaffold(body: Text('Browse source'))),
    GoRoute(
        path: '/migrate',
        builder: (_, state) => const Scaffold(body: Text('Migration screen'))),
  ]);
  final capture = GlobalKey();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    container.dispose();
    await repository.close();
  });
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: RepaintBoundary(
        key: capture,
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          theme: bestTheme(Brightness.dark),
          locale: Locale(language),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        )),
  ));
  await tester.pumpAndSettle();
  return _Fixture(container, repository, media, units, source, router, capture);
}

Future<void> _capture(
    WidgetTester tester, _Fixture fixture, String name) async {
  await tester.pump();
  await tester.runAsync(() async {
    final boundary = fixture.capture.currentContext!.findRenderObject()!
        as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    await Directory('build').create(recursive: true);
    await File('build/series-$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
  });
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
      (
        BestFontFamily.heading,
        'packages/best_ui/assets/fonts/Cairo-Regular.ttf'
      ),
      (
        BestFontFamily.mono,
        'packages/best_ui/assets/fonts/JetBrainsMono-Medium.ttf'
      ),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
  });

  testWidgets('continue names and opens the latest partial chapter',
      (tester) async {
    final fixture = await _open(tester, progress: {1: (2, 10), 3: (4, 20)});
    expect(find.text('Chapter 3 · Page 5 of 10'), findsOneWidget);
    expect(fixture.source.unitCalls, 1);
    await _capture(tester, fixture, 'phone-en');
    await tester.tap(find.widgetWithText(FilledButton, 'Continue reading'));
    await tester.pumpAndSettle();
    expect(find.text('Opened chapter-3 start=0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'finished works offer explicit replay, not the final page of the final chapter',
      (tester) async {
    await _open(tester, complete: true);
    await tester.tap(
        find.widgetWithText(FilledButton, 'Read again from the beginning'));
    await tester.pumpAndSettle();
    expect(find.text('Opened chapter-1 start=1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('progress updates on return without another source request',
      (tester) async {
    final fixture = await _open(tester, progress: {1: (2, 10)});
    await fixture.repository.saveProgress(UnitProgress(
      unitId: fixture.units[1].id,
      position: 5,
      total: 10,
      updatedAt: 100,
    ));
    await tester.pump();
    await fixture.container.read(localWorkProvider(fixture.media.id).future);
    await tester.pumpAndSettle();
    expect(find.text('Chapter 2 · Page 6 of 10'), findsOneWidget);
    expect(fixture.source.unitCalls, 1);
    await fixture.repository.saveProgress(UnitProgress(
      unitId: fixture.units[2].id,
      position: 6,
      total: 10,
      updatedAt: 200,
    ));
    await tester.pump();
    await fixture.container.read(localWorkProvider(fixture.media.id).future);
    await tester.pumpAndSettle();
    expect(find.text('Chapter 3 · Page 7 of 10'), findsOneWidget);
    expect(fixture.source.unitCalls, 1);
  });

  testWidgets(
      'wide layouts separate overview and chapter tools and keep cached data usable',
      (tester) async {
    final fixture = await _open(tester,
        size: const Size(1120, 844), fail: true, offlineChapter: true);
    expect(find.byKey(const ValueKey('series-cache-notice')), findsOneWidget);
    final search = find.byKey(const ValueKey('series-unit-search'));
    expect(tester.getCenter(search).dx, greaterThan(340));
    await _capture(tester, fixture, 'tablet-en');
    await tester
        .tap(find.widgetWithText(TextButton, 'Show downloaded chapters'));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('series-unit-${fixture.units.first.id}')),
        findsOneWidget);
    expect(find.byKey(ValueKey('series-unit-${fixture.units[1].id}')),
        findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Arabic search and large text fit a narrow phone without losing chapters',
      (tester) async {
    final fixture = await _open(tester,
        size: const Size(320, 640), language: 'ar', textScale: 1.35);
    await _capture(tester, fixture, 'phone-ar');
    final search = find.byKey(const ValueKey('series-unit-search'));
    await tester.scrollUntilVisible(
      search,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.enterText(search, 'الفصل ٢');
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('series-unit-${fixture.units[1].id}')),
        findsOneWidget);
    expect(find.byKey(ValueKey('series-unit-${fixture.units.first.id}')),
        findsNothing);
    expect((await fixture.repository.unitsFor(fixture.media.id)), hasLength(3));
    await _capture(tester, fixture, 'chapters-ar');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'UI filtering never reverses or truncates chapter navigation in the real router',
      (tester) async {
    final fixture = await _open(tester, realReader: true);
    final search = find.byKey(const ValueKey('series-unit-search'));
    await tester.scrollUntilVisible(
      search,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.enterText(search, '2');
    await tester.pumpAndSettle();
    final row = find.byKey(ValueKey('series-unit-${fixture.units[1].id}'));
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(fixture.source.resourcesRequested, ['chapter-2', 'chapter-3']);
    expect(find.text('Chapter 3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'an unavailable source does not hide stored chapter or download information',
      (tester) async {
    final fixture = await _open(tester,
        size: const Size(1120, 844), missing: true, offlineChapter: true);
    expect(find.text('This source is not installed'), findsWidgets);
    await tester
        .tap(find.widgetWithText(TextButton, 'Show downloaded chapters'));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('series-unit-${fixture.units.first.id}')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a short synopsis does not pretend it needs expansion',
      (tester) async {
    await _open(tester, size: const Size(1120, 844));
    expect(find.text('More'), findsNothing);
  });

  testWidgets('favoriting a discovered work adds it to the shelf deliberately',
      (tester) async {
    final fixture = await _open(tester, inLibrary: false);
    await tester.tap(find.byTooltip('Favorite'));
    await tester.pumpAndSettle();
    final saved = await fixture.repository.mediaById(fixture.media.id);
    expect(saved!.favorite, isTrue);
    expect(saved.inLibrary, isTrue);
    expect(fixture.source.unitCalls, 1);
  });
}
