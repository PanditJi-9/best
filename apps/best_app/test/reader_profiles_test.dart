import 'dart:convert';

import 'package:best_app/src/providers.dart';
import 'package:best_domain/best_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(SharedPreferences, ProviderContainer)> setup(
    Map<String, Object> values,
  ) async {
    SharedPreferences.setMockInitialValues(values);
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      preferencesProvider.overrideWithValue(preferences),
    ]);
    addTearDown(container.dispose);
    return (preferences, container);
  }

  test('opening a work uses old defaults without creating a profile', () async {
    final (preferences, container) = await setup({
      'reader_mode': 'vertical',
      'reader_direction': 'rtl',
    });
    final settings = container.read(readerSettingsForProvider('work-a'));
    expect(settings.readerMode, ReaderMode.vertical);
    expect(settings.readerDirection, ReaderDirection.rtl);
    expect(settings.readerSpreadMode, ReaderSpreadMode.single);
    expect(container.read(readerProfilesProvider), isEmpty);
    expect(preferences.getString('reader_profiles_v1'), isNull);
  });

  test('a work snapshots its defaults and ignores later global layout changes',
      () async {
    final (_, container) = await setup({'reader_mode': 'vertical'});
    final editor = container.read(readerSettingsControllerProvider('work-a'));
    editor.rememberForWork(true);
    container.read(settingsProvider.notifier).setReaderMode(ReaderMode.paged);

    expect(container.read(readerSettingsForProvider('work-a')).readerMode,
        ReaderMode.vertical);
    expect(container.read(readerSettingsForProvider('work-b')).readerMode,
        ReaderMode.paged);
    expect(container.read(settingsProvider).readerMode, ReaderMode.paged);
  });

  test('editing a work never changes another work or the general defaults',
      () async {
    final (preferences, container) = await setup({});
    final a = container.read(readerSettingsControllerProvider('work-a'));
    final b = container.read(readerSettingsControllerProvider('work-b'));
    a.rememberForWork(true);
    b.rememberForWork(true);
    a.setReaderMode(ReaderMode.vertical);
    a.setReaderDirection(ReaderDirection.rtl);
    a.setReaderFit(ReaderFit.width);
    a.setReaderBackground(ReaderBackground.sepia);
    a.setReaderWebtoonGap(16);
    a.setReaderTapZones(false);
    a.setReaderFilter(mode: 'invert', brightness: -40);
    a.setReaderSpreadMode(ReaderSpreadMode.adaptive);
    a.setReaderCoverAlone(false);
    await Future<void>.delayed(Duration.zero);

    final changed = container.read(readerSettingsForProvider('work-a'));
    expect(
        changed.readerPreferences,
        const ReaderPreferences(
          mode: ReaderMode.vertical,
          direction: ReaderDirection.rtl,
          fit: ReaderFit.width,
          background: ReaderBackground.sepia,
          webtoonGap: 16,
          tapZones: false,
          filterMode: 'invert',
          brightness: -40,
          spreadMode: ReaderSpreadMode.adaptive,
          coverAlone: false,
        ));
    expect(
        container.read(readerSettingsForProvider('work-b')).readerPreferences,
        const ReaderPreferences());
    expect(container.read(settingsProvider).readerPreferences,
        const ReaderPreferences());
    expect(preferences.getString('reader_mode'), isNull);

    final reloaded = ProviderContainer(overrides: [
      preferencesProvider.overrideWithValue(preferences),
    ]);
    addTearDown(reloaded.dispose);
    expect(reloaded.read(readerSettingsForProvider('work-a')).readerPreferences,
        changed.readerPreferences);
    expect(reloaded.read(readerSettingsForProvider('work-b')).readerPreferences,
        const ReaderPreferences());
  });

  test('works without a profile still edit and persist global defaults',
      () async {
    final (preferences, container) = await setup({});
    final editor = container.read(readerSettingsControllerProvider('work-a'));
    editor.setReaderDirection(ReaderDirection.rtl);
    editor.setReaderSpreadMode(ReaderSpreadMode.doublePage);
    editor.setReaderCoverAlone(false);
    await Future<void>.delayed(Duration.zero);

    expect(preferences.getString('reader_direction'), 'rtl');
    expect(preferences.getString('reader_spread_mode'), 'doublePage');
    expect(preferences.getBool('reader_cover_alone'), isFalse);
    expect(container.read(readerProfilesProvider), isEmpty);
    expect(container.read(readerSettingsForProvider('work-b')).readerSpreadMode,
        ReaderSpreadMode.doublePage);
  });

  test('reset restores global defaults and preserves other work profiles',
      () async {
    final (preferences, container) = await setup({});
    final a = container.read(readerSettingsControllerProvider('work-a'));
    final b = container.read(readerSettingsControllerProvider('work-b'));
    a.rememberForWork(true);
    b.rememberForWork(true);
    a.setReaderMode(ReaderMode.vertical);
    b.setReaderBackground(ReaderBackground.white);
    a.rememberForWork(false);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(readerSettingsForProvider('work-a')).readerMode,
        ReaderMode.paged);
    expect(container.read(readerSettingsForProvider('work-b')).readerBackground,
        ReaderBackground.white);
    final Object? stored =
        jsonDecode(preferences.getString('reader_profiles_v1')!);
    expect(stored, isA<Map<String, Object?>>());
    expect((stored! as Map<String, Object?>).keys, ['work-b']);
  });

  test('wake, preload and OCR stay device-wide with a work profile', () async {
    final (_, container) = await setup({
      'language': 'ar',
      'wifi_only': true,
      'storage_cap_gb': 6,
      'biometric_lock_enabled': true,
    });
    final editor = container.read(readerSettingsControllerProvider('work-a'));
    editor.rememberForWork(true);
    editor.setReaderMode(ReaderMode.vertical);
    editor.setReaderKeepAwake(false);
    editor.setReaderPreload(false);
    editor.setOcrTranslationEnabled(true);

    for (final id in ['work-a', 'work-b']) {
      final settings = container.read(readerSettingsForProvider(id));
      expect(settings.readerKeepAwake, isFalse);
      expect(settings.readerPreload, isFalse);
      expect(settings.ocrTranslationEnabled, isTrue);
      expect(settings.languageCode, 'ar');
      expect(settings.wifiOnly, isTrue);
      expect(settings.storageCapGb, 6);
      expect(settings.biometricLockEnabled, isTrue);
    }
    expect(container.read(readerProfilesProvider)['work-a']!.toJson().keys,
        isNot(contains('ocrTranslationEnabled')));
  });

  test('malformed preference data cannot lock the reader', () async {
    for (final raw in ['not json', '[]', 'null']) {
      final (_, container) = await setup({'reader_profiles_v1': raw});
      expect(container.read(readerProfilesProvider), isEmpty);
      expect(container.read(readerSettingsForProvider('work-a')).readerMode,
          ReaderMode.paged);
    }
  });

  test('bad profile entries are skipped without discarding valid work choices',
      () async {
    final (_, container) = await setup({
      'reader_profiles_v1': jsonEncode({
        'work-a': {'direction': 'rtl'},
        'work-b': 7,
        '': {'mode': 'vertical'},
      }),
    });
    expect(container.read(readerProfilesProvider).keys, ['work-a']);
    expect(container.read(readerSettingsForProvider('work-a')).readerDirection,
        ReaderDirection.rtl);
  });

  test('profile writes preserve bookmarks and all unrelated preferences',
      () async {
    const bookmarks = '{"chapter-1":[2,8]}';
    final (preferences, container) = await setup({
      'reader_bookmarks_v1': bookmarks,
      'language': 'ar',
      'categories_v1': <String>['Manga', 'Webtoons'],
    });
    final editor = container.read(readerSettingsControllerProvider('work-a'));
    editor.rememberForWork(true);
    editor.setReaderDirection(ReaderDirection.rtl);
    editor.rememberForWork(false);
    await Future<void>.delayed(Duration.zero);
    expect(preferences.getString('reader_bookmarks_v1'), bookmarks);
    expect(preferences.getString('language'), 'ar');
    expect(preferences.getStringList('categories_v1'), ['Manga', 'Webtoons']);
  });
}
