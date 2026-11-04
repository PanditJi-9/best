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
