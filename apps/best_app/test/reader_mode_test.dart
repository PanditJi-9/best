import 'package:best_app/src/l10n/generated/app_localizations.dart';
import 'package:best_app/src/providers.dart';
import 'package:best_app/src/screens/reader_screen.dart';
import 'package:best_data/best_data.dart';
import 'package:best_domain/best_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SharedPreferences> _preferences(
  Map<String, Object> values,
) async {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the reader mode is stored and restored', () async {
    final preferences = await _preferences(
      <String, Object>{'reader_mode': 'vertical'},
    );
    final container = ProviderContainer(
      overrides: [preferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(container.dispose);

    expect(container.read(settingsProvider).readerMode, ReaderMode.vertical);

    container.read(settingsProvider.notifier).setReaderMode(ReaderMode.paged);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(settingsProvider).readerMode, ReaderMode.paged);
    expect(preferences.getString('reader_mode'), 'paged');
  });

  test('reader direction, fit, background and filter persist', () async {
    final preferences = await _preferences(<String, Object>{});
    final container = ProviderContainer(
      overrides: [preferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(settingsProvider.notifier);
    notifier.setReaderDirection(ReaderDirection.rtl);
    notifier.setReaderFit(ReaderFit.width);
    notifier.setReaderBackground(ReaderBackground.sepia);
    notifier.setReaderTapZones(false);
    notifier.setReaderFilter(mode: 'invert', brightness: -40);
    notifier.setReaderPreload(false);
    notifier.setReaderWebtoonGap(16);
    await Future<void>.delayed(Duration.zero);

    expect(preferences.getString('reader_direction'), 'rtl');
    expect(preferences.getString('reader_fit'), 'width');
    expect(preferences.getString('reader_background'), 'sepia');
    expect(preferences.getBool('reader_tap_zones'), isFalse);
    expect(preferences.getString('reader_filter_mode'), 'invert');
    expect(preferences.getInt('reader_brightness'), -40);
    expect(preferences.getBool('reader_preload'), isFalse);
    expect(preferences.getInt('reader_webtoon_gap'), 16);

    final reloaded = ProviderContainer(
      overrides: [preferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(reloaded.dispose);
    final settings = reloaded.read(settingsProvider);
    expect(settings.readerDirection, ReaderDirection.rtl);
    expect(settings.readerFit, ReaderFit.width);
    expect(settings.readerBackground, ReaderBackground.sepia);
    expect(settings.readerTapZones, isFalse);
    expect(settings.readerFilterMode, 'invert');
    expect(settings.readerBrightness, -40);
    expect(settings.readerPreload, isFalse);
    expect(settings.readerWebtoonGap, 16);
  });

  test('bookmarks persist per chapter and can be removed', () async {
    final preferences = await _preferences(<String, Object>{});
    final container = ProviderContainer(
      overrides: [preferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(container.dispose);

    final bookmarks = container.read(readerBookmarksProvider.notifier);
    bookmarks.toggle('unit-a', 5);
    bookmarks.toggle('unit-a', 2);
    bookmarks.toggle('unit-b', 0);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(readerBookmarksProvider)['unit-a'], <int>[2, 5]);
    expect(preferences.getString('reader_bookmarks_v1'), isNotNull);

    final reloaded = ProviderContainer(
      overrides: [preferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(reloaded.dispose);
    expect(reloaded.read(readerBookmarksProvider)['unit-a'], <int>[2, 5]);
    expect(reloaded.read(readerBookmarksProvider)['unit-b'], <int>[0]);

    reloaded.read(readerBookmarksProvider.notifier).toggle('unit-a', 2);
    await Future<void>.delayed(Duration.zero);
    expect(reloaded.read(readerBookmarksProvider)['unit-a'], <int>[5]);
  });

  test('an unknown stored mode falls back to paged', () async {
    final preferences = await _preferences(
      <String, Object>{'reader_mode': 'diagonal'},
    );
    final container = ProviderContainer(
      overrides: [preferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(container.dispose);

    expect(container.read(settingsProvider).readerMode, ReaderMode.paged);
  });

  testWidgets('the reader switches between paged and vertical', (tester) async {
    final preferences = await _preferences(<String, Object>{});
    final media = Media(
      ref: const SourceRef('test', 'blue-echo'),
      title: 'Blue Echo',
      kind: MediaKind.webtoon,
    );
    final unit = MediaUnit(
      mediaId: media.id,
      url: 'unit-1',
      number: 1,
      title: 'Chapter 1',
      kind: UnitKind.chapter,
      pageCount: 3,
    );
    final data = ReaderData(
      media: media,
      unit: unit,
      resources: const [
        SyntheticPage(0, 'One'),
        SyntheticPage(1, 'Two'),
        SyntheticPage(2, 'Three'),
      ],
      progress: null,
    );
    final container = ProviderContainer(
      overrides: [
        repositoryProvider.overrideWithValue(MemoryLibraryRepository()),
        preferencesProvider.overrideWithValue(preferences),
        readerProvider.overrideWith((ref, key) async => data),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ReaderScreen(
            sourceId: 'test',
            url: 'blue-echo',
            unitUrl: 'unit-1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Page 1 of 3'), findsOneWidget);
    expect(find.byTooltip('Vertical'), findsOneWidget);

    await tester.tap(find.byTooltip('Vertical'));
    await tester.pumpAndSettle();

    expect(
      container.read(settingsProvider).readerMode,
      ReaderMode.vertical,
    );
    expect(find.byTooltip('Paged'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Paged'));
    await tester.pumpAndSettle();

    expect(container.read(settingsProvider).readerMode, ReaderMode.paged);
    expect(find.text('Page 1 of 3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
