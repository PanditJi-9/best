import 'dart:io';
import 'dart:ui' as ui;

import 'package:best_app/src/l10n/generated/app_localizations.dart';
import 'package:best_app/src/providers.dart';
import 'package:best_app/src/reader/page_image_cache.dart';
import 'package:best_app/src/screens/reader_screen.dart';
import 'package:best_app/src/widgets/reader_page_grid.dart';
import 'package:best_app/src/widgets/reader_gesture_viewport.dart';
import 'package:best_data/best_data.dart';
import 'package:best_domain/best_domain.dart';
import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

late Uint8List _scanFixture;

/// Only the byte source is a fixture; Flutter still decodes and renders a real
/// PNG. Disk-cache behavior is covered separately by page_image_cache_test.
class _FixtureImageCache extends PageImageCache {
  _FixtureImageCache(this.bytes)
    : super(client: MockClient((_) async => http.Response('', 404)));

  final Uint8List bytes;

  @override
  Future<Uint8List?> load(ImageResource resource) => Future.value(bytes);
}

class _Fixture {
  const _Fixture(
    this.container,
    this.repository,
    this.media,
    this.units,
    this.requests,
    this.capture,
  );

  final ProviderContainer container;
  final MemoryLibraryRepository repository;
  final Media media;
  final List<MediaUnit> units;
  final List<String> requests;
  final GlobalKey capture;
}

Future<_Fixture> _openReader(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  String language = 'en',
  Map<String, Object> preferences = const {},
  int pages = 8,
  int initialPage = 0,
  int initialChapter = 1,
  bool offline = false,
  double textScale = 1,
  bool partial = false,
  int? expectedPages,
  int? completedPages,
  int? savedTotal,
  bool fromStart = false,
  bool completed = false,
  bool showControls = true,
  Uint8List? scanBytes,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(preferences);
  final store = await SharedPreferences.getInstance();
  final repository = MemoryLibraryRepository();
  final media = Media(
    ref: const SourceRef('test', 'reader-fixture'),
    title: 'A quiet place to read manga',
    kind: MediaKind.manga,
    inLibrary: true,
  );
  final units = [
    for (var chapter = 1; chapter <= 3; chapter++)
      MediaUnit(
        mediaId: media.id,
        url: 'chapter-$chapter',
        number: chapter.toDouble(),
        title: 'Chapter $chapter',
        kind: UnitKind.chapter,
        pageCount: expectedPages ?? pages,
      ),
  ];
  await repository.saveMedia(media);
  await repository.saveUnits(units);
  if (initialPage > 0 || completed) {
    await repository.saveProgress(
      UnitProgress(
        unitId: units[initialChapter - 1].id,
        position: initialPage,
        total: savedTotal ?? expectedPages ?? pages,
        completed: completed,
        updatedAt: 1,
      ),
    );
  }
  final requests = <String>[];
  final capture = GlobalKey();
  if (scanBytes != null) {
    const cacheKey = ValueKey('image-cache-fixture');
    await tester.pumpWidget(const MaterialApp(home: SizedBox(key: cacheKey)));
    final context = tester.element(find.byKey(cacheKey));
    await tester.runAsync(() async {
      final width = size.width.round().clamp(320, 2048).toInt();
      for (final decode in <int?>[
        null,
        width,
        (width * 2).clamp(320, 2048).toInt(),
        (width * 4).clamp(320, 2048).toInt(),
      ]) {
        ImageProvider<Object> image = MemoryImage(scanBytes);
        if (decode != null) image = ResizeImage(image, width: decode);
        await precacheImage(image, context);
      }
    });
  }
  final container = ProviderContainer(
    overrides: [
      repositoryProvider.overrideWithValue(repository),
      preferencesProvider.overrideWithValue(store),
      if (scanBytes != null)
        pageImageCacheProvider.overrideWithValue(_FixtureImageCache(scanBytes)),
      readerProvider.overrideWith((ref, key) async {
        requests.add(key.unitUrl);
        final repaired =
            completedPages != null &&
            requests.where((url) => url == key.unitUrl).length > 1;
        final available = repaired ? completedPages : pages;
        final unit = units.firstWhere((unit) => unit.url == key.unitUrl);
        return ReaderData(
          media: media,
          unit: unit,
          units: units,
          resources: [
            for (var page = 0; page < available; page++)
              if (scanBytes == null)
                SyntheticPage(page, 'Scan ${page + 1}')
              else
                ImageResource(
                  'https://reader-fixture.invalid/${key.unitUrl}/$page.png',
                ),
          ],
          progress: await repository.progressFor(unit.id),
          offline: offline,
          partial: partial && !repaired,
          totalPages: expectedPages,
        );
      }),
    ],
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await repository.close();
  });

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: RepaintBoundary(
        key: capture,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: bestTheme(Brightness.dark),
          locale: Locale(language),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: ReaderScreen(
            sourceId: 'test',
            url: 'reader-fixture',
            unitUrl: 'chapter-$initialChapter',
            fromStart: fromStart,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (showControls) await _ensureChrome(tester);
  return _Fixture(container, repository, media, units, requests, capture);
}

double _chromeOpacity(WidgetTester tester) => tester
    .widget<AnimatedOpacity>(
      find.ancestor(
        of: find.byKey(const ValueKey('reader-controls')),
        matching: find.byType(AnimatedOpacity),
      ),
    )
    .opacity;

Future<void> _tapMenu(WidgetTester tester) async {
  // A confirmed single tap waits for the double-tap window. Keep taps out of
  // the short scroll-stop cooldown rather than treating a fling stop as menu.
  await tester.pump(const Duration(milliseconds: 200));
  await tester.tapAt(tester.getCenter(find.byType(ReaderGestureViewport)));
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
}

Future<void> _ensureChrome(WidgetTester tester) async {
  if (_chromeOpacity(tester) == 0) await _tapMenu(tester);
}

ReaderGestureViewportState _viewport(WidgetTester tester) => tester
    .state<ReaderGestureViewportState>(find.byType(ReaderGestureViewport));

Future<void> _pinch(WidgetTester tester, double factor) async {
  final center = tester.getCenter(find.byType(ReaderGestureViewport));
  final first = await tester.startGesture(
    center - const Offset(40, 0),
    pointer: 11,
  );
  final second = await tester.startGesture(
    center + const Offset(40, 0),
    pointer: 12,
  );
  await tester.pump();
  await first.moveTo(center - Offset(40 * factor, 0));
  await second.moveTo(center + Offset(40 * factor, 0));
  await tester.pump();
  await second.up();
  await first.up();
  await tester.pumpAndSettle();
}

Future<void> _doubleTap(WidgetTester tester) async {
  final center = tester.getCenter(find.byType(ReaderGestureViewport));
  await tester.tapAt(center);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tapAt(center);
  await tester.pumpAndSettle();
}

Future<void> _capture(
  WidgetTester tester,
  _Fixture fixture,
  String name,
) async {
  await tester.pump();
  await tester.runAsync(() async {
    final boundary =
        fixture.capture.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    await Directory('build').create(recursive: true);
    await File(
      'build/reader-$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
  });
}

Finder _sheetText(String text) =>
    find.descendant(of: find.byType(BottomSheet), matching: find.text(text));

Finder _sheetChip(String text) =>
    find.ancestor(of: _sheetText(text), matching: find.byType(ChoiceChip));

Future<void> _openPageGrid(WidgetTester tester) async {
  await _ensureChrome(tester);
  final l10n = AppLocalizations.of(tester.element(find.byType(ReaderScreen)));
  await tester.tap(find.byTooltip(l10n.readerSettings));
  await tester.pumpAndSettle();
  await tester.ensureVisible(_sheetText(l10n.readerPageGrid));
  await tester.pumpAndSettle();
  await tester.tap(_sheetText(l10n.readerPageGrid));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    WidgetController.hitTestWarningShouldBeFatal = true;
    for (final font in [
      (
        BestFonts.text,
        'packages/best_ui/assets/fonts/IBMPlexSansArabic-Regular.ttf',
      ),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
      (
        BestFontFamily.heading,
        'packages/best_ui/assets/fonts/Cairo-Regular.ttf',
      ),
      (
        BestFontFamily.mono,
        'packages/best_ui/assets/fonts/JetBrainsMono-Medium.ttf',
      ),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 256, 1024),
      Paint()..color = const Color(0xFF4361EE),
    );
    canvas.drawRect(
      const Rect.fromLTWH(0, 340, 256, 340),
      Paint()..color = Colors.white,
    );
    canvas.drawRect(
      const Rect.fromLTWH(0, 680, 256, 344),
      Paint()..color = const Color(0xFF34D399),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(256, 1024);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    _scanFixture = bytes!.buffer.asUint8List();
    image.dispose();
    picture.dispose();
  });

  for (final rtl in [false, true]) {
    testWidgets('two scans follow reading direction, RTL=$rtl', (tester) async {
      final fixture = await _openReader(
        tester,
        size: const Size(1100, 700),
        language: rtl ? 'ar' : 'en',
        preferences: {
          'reader_spread_mode': 'doublePage',
          'reader_cover_alone': false,
          'reader_direction': rtl ? 'rtl' : 'ltr',
        },
      );
      final first = tester.getCenter(find.text('Scan 1'));
      final second = tester.getCenter(find.text('Scan 2'));
      expect(rtl ? first.dx > second.dx : first.dx < second.dx, isTrue);
      expect(first.dx, inInclusiveRange(0, 1100));
      expect(second.dx, inInclusiveRange(0, 1100));
      await _capture(tester, fixture, rtl ? 'spread-ar' : 'spread-en');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('adaptive pairing preserves the exact scan through rotation', (
    tester,
  ) async {
    final fixture = await _openReader(
      tester,
      initialPage: 3,
      preferences: {'reader_spread_mode': 'adaptive'},
    );
    expect(find.text('Page 4 of 8'), findsOneWidget);
    tester.view.physicalSize = const Size(1100, 700);
    await tester.pumpAndSettle();
    expect(find.text('Pages 4–5 of 8'), findsOneWidget);
    expect(find.text('Scan 4'), findsOneWidget);
    expect(find.text('Scan 5'), findsOneWidget);
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(find.text('Page 4 of 8'), findsOneWidget);
    expect(find.text('Scan 4'), findsOneWidget);
    expect(fixture.requests, ['chapter-1']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'cover alignment can change without losing the selected source page',
    (tester) async {
      final fixture = await _openReader(
        tester,
        size: const Size(1100, 700),
        preferences: {'reader_spread_mode': 'doublePage'},
      );
      expect(find.text('Page 1 of 8'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.text('Pages 2–3 of 8'), findsOneWidget);
      fixture.container
          .read(readerSettingsControllerProvider(fixture.media.id))
          .setReaderCoverAlone(false);
      await tester.pumpAndSettle();
      expect(find.text('Pages 1–2 of 8'), findsOneWidget);
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      expect(find.text('Page 2 of 8'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'page turning steps by a pair and completion uses real page counts',
    (tester) async {
      final fixture = await _openReader(
        tester,
        size: const Size(1100, 700),
        pages: 4,
        preferences: {
          'reader_spread_mode': 'doublePage',
          'reader_cover_alone': false,
        },
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.text('Scan 3'), findsOneWidget);
      expect(find.text('Scan 4'), findsOneWidget);
      await _ensureChrome(tester);
      expect(find.byTooltip('End of chapter'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
      final progress = await fixture.repository.progressFor(
        fixture.units.first.id,
      );
      expect(progress!.position, 2);
      expect(progress.total, 4);
      expect(progress.completed, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(fixture.requests.last, 'chapter-2');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'work preferences change only this reader and restore defaults on reset',
    (tester) async {
      final fixture = await _openReader(tester, initialPage: 2);
      await tester.tap(find.byTooltip('Reader settings'));
      await tester.pumpAndSettle();
      await tester.tap(_sheetChip('This work'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(_sheetChip('Right to left'));
      await tester.pumpAndSettle();
      await tester.tap(_sheetChip('Right to left'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(_sheetChip('Vertical'));
      await tester.pumpAndSettle();
      await tester.tap(_sheetChip('Vertical'));
      await tester.pumpAndSettle();
      final work = fixture.container.read(
        readerSettingsForProvider(fixture.media.id),
      );
      expect(work.readerMode, ReaderMode.vertical);
      expect(work.readerDirection, ReaderDirection.rtl);
      expect(
        fixture.container.read(settingsProvider).readerMode,
        ReaderMode.paged,
      );
      expect(
        fixture.container.read(settingsProvider).readerDirection,
        ReaderDirection.ltr,
      );
      await tester.ensureVisible(_sheetChip('App defaults'));
      await tester.pumpAndSettle();
      await tester.tap(_sheetChip('App defaults'));
      await tester.pumpAndSettle();
      expect(fixture.container.read(readerProfilesProvider), isEmpty);
      expect(
        fixture.container
            .read(readerSettingsForProvider(fixture.media.id))
            .readerMode,
        ReaderMode.paged,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Arabic offline chrome and settings fit a 320 dp phone with large text',
    (tester) async {
      final fixture = await _openReader(
        tester,
        size: const Size(320, 640),
        language: 'ar',
        offline: true,
        textScale: 1.35,
      );
      final bar = tester.widget<AppBar>(find.byType(AppBar));
      expect(bar.actions, hasLength(1));
      expect(bar.bottom, isNull);
      final title = find
          .descendant(
            of: find.byKey(const ValueKey('reader-chapter-picker')),
            matching: find.byType(Text),
          )
          .first;
      expect(
        tester.renderObject<RenderParagraph>(title).didExceedMaxLines,
        isFalse,
      );
      await _capture(tester, fixture, 'small-ar');
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('إعدادات القارئ'));
      await tester.pumpAndSettle();
      expect(_sheetText('هذا العمل'), findsOneWidget);
      await _capture(tester, fixture, 'settings-ar');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('one toolkit keeps scale and filters out of the top bar', (
    tester,
  ) async {
    final fixture = await _openReader(tester, initialPage: 2);
    final bar = tester.widget<AppBar>(find.byType(AppBar));
    expect(bar.actions, hasLength(1));
    expect(bar.bottom, isNull);
    await _capture(tester, fixture, 'dock-en');

    await tester.tap(find.byTooltip('Reader settings'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(_sheetChip('Fit width'));
    await tester.pumpAndSettle();
    await tester.tap(_sheetChip('Fit width'));
    await tester.pumpAndSettle();
    expect(
      fixture.container
          .read(readerSettingsForProvider(fixture.media.id))
          .readerFit,
      ReaderFit.width,
    );
    await tester.ensureVisible(_sheetText('Colour filter'));
    await tester.pumpAndSettle();
    await tester.tap(_sheetText('Colour filter'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'Greyscale'));
    await tester.pumpAndSettle();
    expect(
      fixture.container
          .read(readerSettingsForProvider(fixture.media.id))
          .readerFilterMode,
      'greyscale',
    );
    expect(
      tester.widget<PageView>(find.byType(PageView)).controller!.page,
      closeTo(2, 0.01),
    );
    expect(fixture.requests, ['chapter-1']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scrubbing previews locally and seeks once on release', (
    tester,
  ) async {
    final fixture = await _openReader(tester, initialPage: 1);
    final slider = find.byKey(const ValueKey('reader-progress-slider'));
    final rect = tester.getRect(slider);
    final trackWidth = rect.width - 44;
    final gesture = await tester.startGesture(
      Offset(rect.left + 22 + trackWidth / 7, rect.center.dy),
    );
    await tester.pump();
    await gesture.moveTo(
      Offset(rect.left + 22 + trackWidth * 0.65, rect.center.dy),
    );
    await tester.pump();
    final preview = tester.widget<Slider>(slider).value.round() - 1;
    expect(preview, inInclusiveRange(2, 6));
    expect(
      tester.widget<PageView>(find.byType(PageView)).controller!.page,
      closeTo(1, 0.01),
    );

    // Holding or releasing the scrubber cannot make the menu blink. No pages
    // are fetched or recorded before the finger is released.
    await tester.pump(const Duration(seconds: 5));
    final dockOpacity = find.ancestor(
      of: find.byKey(const ValueKey('reader-controls')),
      matching: find.byType(AnimatedOpacity),
    );
    expect(tester.widget<AnimatedOpacity>(dockOpacity).opacity, 1);
    expect(
      (await fixture.repository.progressFor(fixture.units.first.id))!.position,
      1,
    );
    await _capture(tester, fixture, 'scrub-preview');

    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      tester.widget<PageView>(find.byType(PageView)).controller!.page,
      closeTo(preview.toDouble(), 0.01),
    );
    expect(
      (await fixture.repository.progressFor(fixture.units.first.id))!.position,
      preview,
    );
    expect(fixture.requests, ['chapter-1']);
    await tester.pump(const Duration(milliseconds: 4250));
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedOpacity>(dockOpacity).opacity, 1);
    await _tapMenu(tester);
    expect(tester.widget<AnimatedOpacity>(dockOpacity).opacity, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a new twenty-page chapter opens on the first scan', (
    tester,
  ) async {
    await _openReader(tester, pages: 20, preferences: {'reader_mode': 'paged'});
    expect(find.text('Scan 1'), findsOneWidget);
    expect(find.text('Page 1 of 20'), findsOneWidget);
    expect(
      tester.widget<PageView>(find.byType(PageView)).controller!.page,
      closeTo(0, 0.01),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching layouts keeps the exact page instead of page 2 or 3', (
    tester,
  ) async {
    await _openReader(
      tester,
      pages: 20,
      initialPage: 4,
      preferences: {'reader_mode': 'paged'},
    );
    expect(find.text('Page 5 of 20'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reader-quick-mode')));
    await tester.pumpAndSettle();
    expect(find.text('Scan 5'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reader-quick-mode')));
    await tester.pumpAndSettle();
    expect(find.text('Page 5 of 20'), findsOneWidget);
    expect(
      tester.widget<PageView>(find.byType(PageView)).controller!.page,
      closeTo(4, 0.01),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('pinching keeps the same decoded scan and shows no reload', (
    tester,
  ) async {
    await _openReader(
      tester,
      pages: 3,
      showControls: false,
      scanBytes: _scanFixture,
    );
    int? width() => tester
        .widgetList<Image>(find.byType(Image))
        .map((image) => image.image)
        .whereType<ResizeImage>()
        .map((image) => image.width)
        .firstWhere((width) => width != null);

    final before = width();
    await _pinch(tester, 2);
    expect(_viewport(tester).scale, closeTo(2, 0.01));
    expect(width(), before);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(RawImage), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  for (final fit in ['screen', 'width', 'height', 'original']) {
    testWidgets('real decoded scans pinch in $fit mode without a page turn', (
      tester,
    ) async {
      final fixture = await _openReader(
        tester,
        pages: 3,
        showControls: false,
        scanBytes: _scanFixture,
        preferences: {'reader_fit': fit},
      );
      expect(
        tester.widget<RawImage>(find.byType(RawImage).first).image,
        isNotNull,
      );
      expect(_chromeOpacity(tester), 0);
      await _pinch(tester, 2);
      expect(_viewport(tester).scale, closeTo(2, 0.01));
      expect(
        tester.widget<PageView>(find.byType(PageView)).controller!.page,
        closeTo(0, 0.01),
      );
      expect(_chromeOpacity(tester), 0);
      expect(
        await fixture.repository.progressFor(fixture.units.first.id),
        isNull,
      );
      await _pinch(tester, 0.5);
      expect(_viewport(tester).scale, closeTo(1, 0.01));
      expect(fixture.requests, ['chapter-1']);
      expect(tester.takeException(), isNull);
    });
  }

  for (final rtl in [false, true]) {
    testWidgets('zoomed panning does not flip scans, RTL=$rtl', (tester) async {
      final fixture = await _openReader(
        tester,
        initialPage: 1,
        showControls: false,
        language: rtl ? 'ar' : 'en',
        preferences: {'reader_direction': rtl ? 'rtl' : 'ltr'},
      );
      await _pinch(tester, 2);
      final before = tester.getCenter(find.text('Scan 2'));
      final start = tester.getCenter(find.byType(ReaderGestureViewport));
      final finger = await tester.startGesture(start);
      await finger.moveTo(start + const Offset(55, 65));
      await tester.pump();
      final after = tester.getCenter(find.text('Scan 2'));
      expect(after.dx - before.dx, closeTo(55, 1));
      expect(after.dy - before.dy, closeTo(65, 1));
      expect(
        tester.widget<PageView>(find.byType(PageView)).controller!.page,
        closeTo(1, 0.01),
      );
      await finger.up();
      await tester.pumpAndSettle();
      await _capture(
        tester,
        fixture,
        rtl ? 'gesture-pan-ar' : 'gesture-pan-en',
      );
      await _doubleTap(tester);
      expect(_viewport(tester).scale, closeTo(1, 0.01));
      await tester.drag(find.byType(PageView), Offset(rtl ? 260 : -260, 0));
      await tester.pumpAndSettle();
      expect(
        tester.widget<PageView>(find.byType(PageView)).controller!.page,
        closeTo(2, 0.01),
      );
      expect(_chromeOpacity(tester), 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('two held fingers and a short drag cannot toggle the menu', (
    tester,
  ) async {
    await _openReader(tester);
    final center = tester.getCenter(find.byType(ReaderGestureViewport));
    final first = await tester.startGesture(
      center - const Offset(35, 0),
      pointer: 31,
    );
    final second = await tester.startGesture(
      center + const Offset(35, 0),
      pointer: 32,
    );
    await tester.pump(const Duration(seconds: 6));
    expect(_chromeOpacity(tester), 1);
    await second.up();
    await first.up();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(_chromeOpacity(tester), 1);
    final finger = await tester.startGesture(center);
    await finger.moveTo(center - const Offset(0, 10));
    await finger.up();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(_chromeOpacity(tester), 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'reading hides once and never reveals bars at a chapter boundary',
    (tester) async {
      final fixture = await _openReader(tester, pages: 2);
      await tester.pump(const Duration(seconds: 12));
      expect(_chromeOpacity(tester), 1);
      await tester.drag(find.byType(PageView), const Offset(-260, 0));
      await tester.pumpAndSettle();
      expect(_chromeOpacity(tester), 0);
      await tester.pump(const Duration(seconds: 12));
      expect(_chromeOpacity(tester), 0);
      await _capture(tester, fixture, 'gesture-fullscreen-end');
      await tester.drag(find.byType(PageView), const Offset(-180, 0));
      await tester.pumpAndSettle();
      expect(
        tester.widget<ReaderScreen>(find.byType(ReaderScreen)).unitUrl,
        'chapter-2',
      );
      expect(_chromeOpacity(tester), 0);
      await _tapMenu(tester);
      expect(_chromeOpacity(tester), 1);
      await tester.pump(const Duration(seconds: 12));
      expect(_chromeOpacity(tester), 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('double-tap and second-tap drag provide quick zoom', (
    tester,
  ) async {
    await _openReader(tester, showControls: false);
    final center = tester.getCenter(find.byType(ReaderGestureViewport));
    await _doubleTap(tester);
    expect(_viewport(tester).scale, closeTo(2, 0.01));
    await _doubleTap(tester);
    expect(_viewport(tester).scale, closeTo(1, 0.01));
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 100));
    final finger = await tester.startGesture(center);
    await tester.pump();
    await finger.moveTo(center - const Offset(0, 140));
    await tester.pump();
    expect(_viewport(tester).scale, inInclusiveRange(1.9, 2.1));
    await finger.up();
    await tester.pumpAndSettle();
    expect(
      tester.widget<PageView>(find.byType(PageView)).controller!.page,
      closeTo(0, 0.01),
    );
    expect(_chromeOpacity(tester), 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a late pinch and the finger left behind cannot advance pages', (
    tester,
  ) async {
    await _openReader(tester, showControls: false);
    final center = tester.getCenter(find.byType(ReaderGestureViewport));
    final first = await tester.startGesture(center, pointer: 41);
    await first.moveTo(center - const Offset(35, 0));
    await tester.pump();
    final second = await tester.startGesture(
      center + const Offset(45, 0),
      pointer: 42,
    );
    await tester.pump();
    await first.moveTo(center - const Offset(75, 0));
    await second.moveTo(center + const Offset(85, 0));
    await tester.pump();
    expect(_viewport(tester).scale, closeTo(2, 0.01));
    await second.up();
    await first.moveTo(center - const Offset(165, 0));
    await tester.pump();
    expect(
      tester.widget<PageView>(find.byType(PageView)).controller!.page,
      closeTo(0, 0.01),
    );
    await first.up();
    await tester.pumpAndSettle();
    expect(_chromeOpacity(tester), 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'webtoon pinch preserves its image anchor and native scroll speed',
    (tester) async {
      final fixture = await _openReader(
        tester,
        pages: 3,
        showControls: false,
        scanBytes: _scanFixture,
        preferences: {'reader_mode': 'vertical'},
      );
      final before = tester.getRect(find.byType(RawImage).first);
      final center = tester.getCenter(find.byType(ReaderGestureViewport));
      final fraction = (center.dy - before.top) / before.height;
      await _pinch(tester, 2);
      final after = tester.getRect(find.byType(RawImage).first);
      expect(after.top + fraction * after.height, closeTo(center.dy, 3));
      expect(
        await fixture.repository.progressFor(fixture.units.first.id),
        isNull,
      );
      final finger = await tester.startGesture(center);
      await finger.moveTo(center - const Offset(0, 60));
      await tester.pump();
      final scrollStart = tester.getRect(find.byType(RawImage).first).top;
      await finger.moveTo(center - const Offset(0, 180));
      await tester.pump();
      final scrollEnd = tester.getRect(find.byType(RawImage).first).top;
      expect(scrollEnd - scrollStart, closeTo(-120, 3));
      await finger.up();
      await tester.pumpAndSettle();
      expect(_viewport(tester).scale, closeTo(2, 0.01));
      expect(_chromeOpacity(tester), 0);
      await _capture(tester, fixture, 'gesture-webtoon-zoom');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('fit-width scans still scroll vertically when enlarged', (
    tester,
  ) async {
    await _openReader(
      tester,
      pages: 3,
      showControls: false,
      scanBytes: _scanFixture,
      preferences: {'reader_fit': 'width'},
    );
    await _pinch(tester, 2);
    final center = tester.getCenter(find.byType(ReaderGestureViewport));
    final finger = await tester.startGesture(center);
    await finger.moveTo(center - const Offset(0, 60));
    await tester.pump();
    final controller = tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView).first)
        .controller!;
    final before = controller.offset;
    await finger.moveTo(center - const Offset(0, 180));
    await tester.pump();
    expect(controller.offset - before, closeTo(60, 3));
    await finger.up();
    await tester.pumpAndSettle();
    expect(
      tester.widget<PageView>(find.byType(PageView)).controller!.page,
      closeTo(0, 0.01),
    );
    expect(_chromeOpacity(tester), 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pinch scales stay between half size and four times fit', (
    tester,
  ) async {
    await _openReader(tester, showControls: false);
    await _pinch(tester, 0.1);
    expect(_viewport(tester).scale, closeTo(0.5, 0.01));
    for (var i = 0; i < 4; i++) {
      await _pinch(tester, 2);
    }
    expect(_viewport(tester).scale, closeTo(4, 0.01));
    expect(_chromeOpacity(tester), 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'an enlarged webtoon continues across images without menu flashes',
    (tester) async {
      final fixture = await _openReader(
        tester,
        showControls: false,
        preferences: {'reader_mode': 'vertical'},
      );
      await _pinch(tester, 2);
      expect(
        await fixture.repository.progressFor(fixture.units.first.id),
        isNull,
      );
      for (var i = 0; i < 2; i++) {
        const start = Offset(195, 700);
        final finger = await tester.startGesture(start);
        await finger.moveTo(
          start - const Offset(0, 60),
          timeStamp: const Duration(milliseconds: 100),
        );
        await tester.pump();
        await finger.moveTo(
          start - const Offset(0, 500),
          timeStamp: const Duration(milliseconds: 600),
        );
        await tester.pump();
        await finger.moveTo(
          start - const Offset(0, 500),
          timeStamp: const Duration(seconds: 2),
        );
        await finger.up(timeStamp: const Duration(milliseconds: 2100));
        await tester.pumpAndSettle();
      }
      await tester.pump(const Duration(milliseconds: 400));
      final progress = await fixture.repository.progressFor(
        fixture.units.first.id,
      );
      expect(progress, isNotNull);
      expect(progress!.position, greaterThanOrEqualTo(1));
      expect(_viewport(tester).scale, closeTo(2, 0.01));
      expect(_chromeOpacity(tester), 0);
      expect(fixture.requests, ['chapter-1']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the Arabic webtoon toolkit preserves the current page', (
    tester,
  ) async {
    final fixture = await _openReader(
      tester,
      language: 'ar',
      initialPage: 3,
      preferences: {'reader_direction': 'rtl'},
    );
    final context = tester.element(find.byType(ReaderScreen));
    final l10n = AppLocalizations.of(context);
    final close = MaterialLocalizations.of(context).closeButtonTooltip;
    await tester.tap(find.byTooltip(l10n.readerSettings));
    await tester.pumpAndSettle();
    await tester.ensureVisible(_sheetChip(l10n.readerModeVertical));
    await tester.pumpAndSettle();
    await tester.tap(_sheetChip(l10n.readerModeVertical));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(close));
    await tester.pumpAndSettle();
    expect(find.text(l10n.pageOf(4, 8)), findsOneWidget);
    expect(tester.widget<AppBar>(find.byType(AppBar)).actions, hasLength(1));
    await _capture(tester, fixture, 'webtoon-controls-ar');

    await tester.tap(find.byTooltip(l10n.readerSettings));
    await tester.pumpAndSettle();
    await tester.ensureVisible(_sheetChip(l10n.readerModePaged));
    await tester.pumpAndSettle();
    await tester.tap(_sheetChip(l10n.readerModePaged));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(close));
    await tester.pumpAndSettle();
    expect(find.text(l10n.pageOf(4, 8)), findsOneWidget);
    expect(fixture.requests, ['chapter-1']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('minimal overlays keep the full viewport and chapter selection', (
    tester,
  ) async {
    final fixture = await _openReader(
      tester,
      size: const Size(320, 640),
      language: 'ar',
      initialChapter: 2,
      textScale: 1.35,
      preferences: {'reader_direction': 'rtl'},
    );
    final bar = tester.widget<AppBar>(find.byType(AppBar));
    expect(bar.toolbarHeight, 48);
    expect(bar.actions, hasLength(1));
    expect(
      tester
          .getSize(find.byKey(const ValueKey('reader-progress-strip')))
          .height,
      48,
    );
    expect(tester.getSize(find.byType(PageView)), const Size(320, 640));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('reader-controls')),
        matching: find.byType(IconButton),
      ),
      findsNothing,
    );
    await _tapMenu(tester);
    expect(tester.getSize(find.byType(PageView)), const Size(320, 640));
    await _tapMenu(tester);

    await tester.tap(find.byKey(const ValueKey('reader-chapter-picker')));
    await tester.pumpAndSettle();
    final third = find.byKey(ValueKey('chapter-picker-${fixture.units[2].id}'));
    await tester.ensureVisible(third);
    await tester.pumpAndSettle();
    await tester.tap(third);
    await tester.pumpAndSettle();
    expect(fixture.requests.last, 'chapter-3');
    expect(
      tester.widget<ReaderScreen>(find.byType(ReaderScreen)).unitUrl,
      'chapter-3',
    );
    await _ensureChrome(tester);
    await tester.tap(find.byKey(const ValueKey('reader-chapter-picker')));
    await tester.pumpAndSettle();
    final second = find.byKey(
      ValueKey('chapter-picker-${fixture.units[1].id}'),
    );
    await tester.ensureVisible(second);
    await tester.pumpAndSettle();
    await tester.tap(second);
    await tester.pumpAndSettle();
    expect(
      tester.widget<ReaderScreen>(find.byType(ReaderScreen)).unitUrl,
      'chapter-2',
    );
    // This chapter was already opened: the provider reuses its resources
    // instead of performing another source request just to navigate back.
    expect(fixture.requests, ['chapter-2', 'chapter-3']);
    expect(find.text('Scan 1'), findsOneWidget);
    await _ensureChrome(tester);
    await _capture(tester, fixture, 'minimal-controls-ar');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a swipe reaching the final page does not also skip the chapter',
    (tester) async {
      final fixture = await _openReader(tester, pages: 2);
      await tester.drag(find.byType(PageView), const Offset(-600, 0));
      await tester.pumpAndSettle();
      await _ensureChrome(tester);
      expect(find.byTooltip('End of chapter'), findsOneWidget);
      expect(fixture.requests, ['chapter-1']);
      await tester.drag(find.byType(PageView), const Offset(-24, 0));
      await tester.pumpAndSettle();
      expect(fixture.requests, ['chapter-1']);
      await tester.drag(find.byType(PageView), const Offset(-180, 0));
      await tester.pumpAndSettle();
      expect(fixture.requests.last, 'chapter-2');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('forward edge swipes work in right-to-left chapters', (
    tester,
  ) async {
    final fixture = await _openReader(
      tester,
      pages: 3,
      initialPage: 2,
      preferences: {'reader_direction': 'rtl'},
    );
    await tester.drag(find.byType(PageView), const Offset(180, 0));
    await tester.pumpAndSettle();
    expect(fixture.requests.last, 'chapter-2');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a backward edge swipe opens the previous chapter at its end', (
    tester,
  ) async {
    final fixture = await _openReader(tester, initialChapter: 2);
    await tester.drag(find.byType(PageView), const Offset(180, 0));
    await tester.pumpAndSettle();
    expect(fixture.requests.last, 'chapter-1');
    expect(find.text('Scan 8'), findsOneWidget);
    await _ensureChrome(tester);
    expect(find.byTooltip('End of chapter'), findsOneWidget);
    await _capture(tester, fixture, 'minimal-end-en');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'one-page webtoons can continue into the next chapter with a keyboard',
    (tester) async {
      final fixture = await _openReader(
        tester,
        pages: 1,
        preferences: {'reader_mode': 'vertical'},
      );
      expect(
        tester
            .widget<Slider>(
              find.byKey(const ValueKey('reader-progress-slider')),
            )
            .onChanged,
        isNull,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(fixture.requests.last, 'chapter-2');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'modified shortcuts and modal sheets do not turn the hidden page',
    (tester) async {
      final fixture = await _openReader(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(fixture.container.read(readerBookmarksProvider), isEmpty);
      expect(find.text('Page 1 of 8'), findsOneWidget);
      await tester.tap(find.byTooltip('Reader settings'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      final position = tester.widget<Slider>(find.byType(Slider)).value;
      expect(position, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('grid bookmarks stay in source-page coordinates when paired', (
    tester,
  ) async {
    final fixture = await _openReader(
      tester,
      size: const Size(1100, 700),
      pages: 6,
      preferences: {
        'reader_spread_mode': 'doublePage',
        'reader_cover_alone': false,
      },
    );
    await _openPageGrid(tester);
    final fourth = find
        .descendant(
          of: find.byType(ReaderPageGridSheet),
          matching: find.text('4'),
        )
        .first;
    await tester.longPress(fourth);
    await tester.pumpAndSettle();
    expect(
      fixture.container.read(readerBookmarksProvider)[fixture.units.first.id],
      [3],
    );
    await _capture(tester, fixture, 'page-grid');
    await tester.tap(fourth);
    await tester.pumpAndSettle();
    expect(find.text('Pages 3–4 of 6'), findsOneWidget);
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(find.text('Page 4 of 6'), findsOneWidget);
    expect(
      fixture.container.read(readerBookmarksProvider)[fixture.units.first.id],
      [3],
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'partial chapters keep their real total and cannot auto-complete or skip missing pages',
    (tester) async {
      final fixture = await _openReader(
        tester,
        pages: 2,
        partial: true,
        expectedPages: 20,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.text('Page 2 of 20'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
      final saved = await fixture.repository.progressFor(
        fixture.units.first.id,
      );
      expect(saved!.total, 20);
      expect(saved.completed, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(fixture.requests, ['chapter-1']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a short offline prefix cannot overwrite a later saved reading position',
    (tester) async {
      final fixture = await _openReader(
        tester,
        pages: 2,
        partial: true,
        expectedPages: 20,
        initialPage: 8,
      );
      expect(find.text('Page 2 of 20'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      final saved = await fixture.repository.progressFor(
        fixture.units.first.id,
      );
      expect(saved!.position, 8);
      expect(saved.completed, isFalse);
    },
  );

  testWidgets(
    'explicit replay starts at page one and keeps the completed fact',
    (tester) async {
      final fixture = await _openReader(
        tester,
        initialPage: 7,
        completed: true,
        fromStart: true,
      );
      expect(find.text('Page 1 of 8'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));
      final saved = await fixture.repository.progressFor(
        fixture.units.first.id,
      );
      expect(saved!.position, 1);
      expect(saved.completed, isTrue);
    },
  );

  for (final mode in ['paged', 'vertical', 'paired']) {
    testWidgets(
      'finishing a partial download restores the saved page in $mode mode',
      (tester) async {
        final fixture = await _openReader(
          tester,
          size: mode == 'paired' ? const Size(1100, 700) : const Size(390, 844),
          pages: 2,
          initialPage: 8,
          expectedPages: 20,
          completedPages: 20,
          partial: true,
          preferences: {
            'reader_mode': mode == 'paired' ? 'paged' : mode,
            if (mode == 'paired') ...{
              'reader_spread_mode': 'doublePage',
              'reader_cover_alone': false,
            },
          },
        );
        final unit = fixture.units.first;
        final task = DownloadTask(
          unitId: unit.id,
          mediaId: fixture.media.id,
          sourceId: fixture.media.ref.sourceId,
          mediaUrl: fixture.media.ref.url,
          unitUrl: unit.url,
          mediaTitle: fixture.media.title,
          unitTitle: unit.title,
          total: 20,
          completed: 2,
          status: DownloadStatus.paused,
        );
        await fixture.repository.saveDownload(task);
        await tester.pump();
        await fixture.container.read(downloadForProvider(unit.id).future);
        await tester.pumpAndSettle();
        await fixture.repository.saveDownload(
          task.copyWith(status: DownloadStatus.done, completed: 20),
        );
        await tester.pump();
        await fixture.container.read(downloadForProvider(unit.id).future);
        await tester.pumpAndSettle();
        expect(
          find.text(mode == 'paired' ? 'Pages 9–10 of 20' : 'Page 9 of 20'),
          findsOneWidget,
        );
        await tester.pump(const Duration(milliseconds: 400));
        final progress = (await fixture.repository.progressFor(unit.id))!;
        expect(progress.position, 8);
        expect(progress.completed, isFalse);
        final activity = await fixture.repository.activity();
        expect(activity.fold<int>(0, (total, day) => total + day.pages), 0);
        expect(fixture.requests, ['chapter-1', 'chapter-1']);
        await tester.sendKeyEvent(
          mode == 'vertical'
              ? LogicalKeyboardKey.arrowDown
              : LogicalKeyboardKey.arrowRight,
        );
        await tester.pumpAndSettle();
        final afterTurning = await fixture.repository.activity();
        expect(
          afterTurning.fold<int>(0, (total, day) => total + day.pages),
          mode == 'paired' ? 2 : 1,
        );
      },
    );
  }

  for (final mode in ['paged', 'vertical']) {
    testWidgets(
      'unknown partial totals stay unknown in the $mode reader and page grid',
      (tester) async {
        final fixture = await _openReader(
          tester,
          pages: 2,
          partial: true,
          initialPage: 8,
          savedTotal: 0,
          language: mode == 'vertical' ? 'ar' : 'en',
          size: mode == 'vertical'
              ? const Size(320, 640)
              : const Size(390, 844),
          textScale: mode == 'vertical' ? 1.35 : 1,
          preferences: {'reader_mode': mode},
        );
        final l10n = AppLocalizations.of(
          tester.element(find.byType(ReaderScreen)),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
        expect(find.text(l10n.readerSavedPage(1)), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 400));
        final unit = fixture.units.first;
        final saved = (await fixture.repository.progressFor(unit.id))!;
        expect(saved.position, 8);
        expect(saved.total, 0);
        expect(saved.completed, isFalse);
        fixture.container
            .read(readerBookmarksProvider.notifier)
            .toggle(unit.id, 8);
        await _openPageGrid(tester);
        expect(
          tester
              .widget<ReaderPageGridSheet>(find.byType(ReaderPageGridSheet))
              .totalPages,
          0,
        );
        expect(_sheetText(l10n.readerSavedPage(1)), findsOneWidget);
        expect(_sheetText(l10n.pageOf(1, 2)), findsNothing);
        await _capture(tester, fixture, 'unknown-total-grid-$mode');
        await tester.tap(_sheetChip('${l10n.readerBookmarks} · 1'));
        await tester.pumpAndSettle();
        expect(_sheetText(l10n.readerBookmarksEmpty), findsNothing);
        expect(_sheetText(l10n.readerBookmarksUnavailable), findsOneWidget);
        expect(fixture.container.read(readerBookmarksProvider)[unit.id], [8]);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'an explicit backward chapter hop opens at the end, not an old partial position',
    (tester) async {
      final fixture = await _openReader(tester, initialChapter: 2);
      await fixture.repository.saveProgress(
        UnitProgress(
          unitId: fixture.units.first.id,
          position: 2,
          total: 8,
          started: true,
          updatedAt: 1,
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(find.text('Page 8 of 8'), findsOneWidget);
      expect(fixture.requests, ['chapter-2', 'chapter-1']);
    },
  );

  testWidgets('the quick dock bookmarks a page and flips mode in one tap', (
    tester,
  ) async {
    final fixture = await _openReader(tester);
    await _ensureChrome(tester);
    final unit = fixture.units.first;
    expect(fixture.container.read(readerBookmarksProvider)[unit.id], isNull);

    await tester.tap(find.byKey(const ValueKey('reader-quick-bookmark')));
    await tester.pumpAndSettle();
    expect(fixture.container.read(readerBookmarksProvider)[unit.id], [0]);
    expect(find.byTooltip('Remove bookmark'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('reader-quick-mode')));
    await tester.pumpAndSettle();
    expect(
      fixture.container
          .read(readerSettingsForProvider(fixture.media.id))
          .readerMode,
      ReaderMode.vertical,
    );
    await tester.tap(find.byKey(const ValueKey('reader-quick-mode')));
    await tester.pumpAndSettle();
    expect(
      fixture.container
          .read(readerSettingsForProvider(fixture.media.id))
          .readerMode,
      ReaderMode.paged,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('auto-scroll is offered in continuous mode and pauses on tap', (
    tester,
  ) async {
    await _openReader(tester);
    await _ensureChrome(tester);
    expect(find.byKey(const ValueKey('reader-auto-scroll')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('reader-quick-mode')));
    await tester.pumpAndSettle();
    final control = find.byKey(const ValueKey('reader-auto-scroll'));
    expect(control, findsOneWidget);

    await tester.tap(control);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(
      find.descendant(of: control, matching: find.byIcon(Icons.pause_rounded)),
      findsOneWidget,
    );

    await tester.tap(control);
    await tester.pump();
    await tester.pump();
    expect(
      find.descendant(
        of: control,
        matching: find.byIcon(Icons.slow_motion_video_rounded),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
