import 'dart:convert';
import 'dart:io';

import 'package:best_app/src/backup/backup_file_sharer.dart';
import 'package:best_app/src/backup/backup_file_store.dart';
import 'package:best_app/src/l10n/generated/app_localizations.dart';
import 'package:best_app/src/providers.dart';
import 'package:best_app/src/screens/backup_screen.dart';
import 'package:best_data/best_data.dart';
import 'package:best_domain/best_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ShareCapture extends BackupFileSharer {
  String? filePath;
  String? chooserTitle;

  @override
  Future<void> share(String path, {required String title, Rect? origin}) async {
    filePath = path;
    chooserTitle = title;
  }
}

class _MemoryFileStore extends BackupFileStore {
  String? document;

  @override
  Future<File> write(String text, Directory directory) async {
    document = text;
    return File('${directory.path}/best-backup.json');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final work = Media(
    ref: const SourceRef('test', 'reader-backup'),
    title: 'A saved story',
    kind: MediaKind.manga,
    inLibrary: true,
  );
  final unit = MediaUnit(
    mediaId: work.id,
    url: 'chapter-1',
    number: 1,
    title: 'Chapter 1',
    kind: UnitKind.chapter,
    pageCount: 10,
  );

  Future<(SharedPreferences, ProviderContainer, MemoryLibraryRepository)> setup(
    Map<String, Object> values,
  ) async {
    SharedPreferences.setMockInitialValues(values);
    final preferences = await SharedPreferences.getInstance();
    final repository = MemoryLibraryRepository();
    final container = ProviderContainer(overrides: [
      preferencesProvider.overrideWithValue(preferences),
      repositoryProvider.overrideWithValue(repository),
    ]);
    addTearDown(() async {
      container.dispose();
      await repository.close();
    });
    return (preferences, container, repository);
  }

  String backup({ReaderStateSnapshot reader = const ReaderStateSnapshot()}) =>
      LibraryBackup.encode(
        LibrarySnapshot(media: [
          work
        ], units: [
          unit
        ], progress: [
          UnitProgress(unitId: unit.id, position: 3, total: 10, updatedAt: 1),
        ]),
        categories: const ['An empty category'],
        reader: reader,
      );

  test(
      'export includes reader choices and empty categories, but not device secrets',
      () async {
    final (_, container, repository) = await setup({
      'language': 'ar',
      'wifi_only': true,
      'sync_password': 'do-not-export-this',
      'suwayomi_url': 'https://user:private-password@example.test/',
      'hidden_categories_v1': <String>['Private'],
    });
    await repository.saveMedia(work);
    await repository.saveUnits([unit]);
    await container.read(categoriesProvider.notifier).add('An empty category');
    container
        .read(readerSettingsControllerProvider(work.id))
        .rememberForWork(true);
    container
        .read(readerSettingsControllerProvider(work.id))
        .setReaderMode(ReaderMode.vertical);
    container.read(readerBookmarksProvider.notifier).toggle(unit.id, 4);

    final exported = await container.read(backupControllerProvider).export();
    final document = LibraryBackup.decodeDocument(exported.text);
    expect(document.categories, ['An empty category']);
    expect(document.reader.profiles[work.id]!.mode, ReaderMode.vertical);
    expect(document.reader.bookmarks[unit.id], [4]);
    expect(exported.text, isNot(contains('do-not-export-this')));
    expect(exported.text, isNot(contains('private-password')));
    expect(exported.text, isNot(contains('hidden_categories_v1')));
    expect(exported.text, isNot(contains('wifi_only')));
  });

  test(
      'restore persists marks and missing work styles while preserving local choices',
      () async {
    final (preferences, container, repository) = await setup({
      'reader_mode': 'vertical',
      'reader_bookmarks_v1': jsonEncode({
        unit.id: [2, 7]
      }),
      'reader_profiles_v1': jsonEncode({
        work.id:
            const ReaderPreferences(direction: ReaderDirection.rtl).toJson(),
      }),
    });
    await repository.saveMedia(work);
    await repository.saveUnits([unit]);
    await repository.saveProgress(UnitProgress(
      unitId: unit.id,
      position: 8,
      total: 10,
      updatedAt: 100,
    ));
    await container.read(backupControllerProvider).restore(backup(
          reader: ReaderStateSnapshot(
            defaults: const ReaderPreferences(),
            profiles: {
              work.id: const ReaderPreferences(direction: ReaderDirection.ltr),
              'other-work':
                  const ReaderPreferences(background: ReaderBackground.sepia),
            },
            bookmarks: {
              unit.id: const [1, 7]
            },
          ),
        ));
    expect(container.read(settingsProvider).readerMode, ReaderMode.vertical);
    expect(container.read(readerProfilesProvider)[work.id]!.direction,
        ReaderDirection.rtl);
    expect(container.read(readerProfilesProvider)['other-work']!.background,
        ReaderBackground.sepia);
    expect(container.read(readerBookmarksProvider)[unit.id], [1, 2, 7]);
    expect(container.read(categoriesProvider), ['An empty category']);
    expect((await repository.progressFor(unit.id))!.position, 8);

    final reloaded = ProviderContainer(overrides: [
      preferencesProvider.overrideWithValue(preferences),
    ]);
    addTearDown(reloaded.dispose);
    expect(reloaded.read(readerBookmarksProvider)[unit.id], [1, 2, 7]);
    expect(reloaded.read(readerProfilesProvider)[work.id]!.direction,
        ReaderDirection.rtl);
  });

  test(
      'a new device restores presentation defaults without weakening its policies',
      () async {
    final (preferences, container, _) = await setup({
      'language': 'ar',
      'wifi_only': true,
      'reader_keep_awake': false,
      'biometric_lock_enabled': true,
    });
    await container.read(backupControllerProvider).restore(backup(
          reader: const ReaderStateSnapshot(
              defaults: ReaderPreferences(
            direction: ReaderDirection.rtl,
            background: ReaderBackground.sepia,
          )),
        ));
    final settings = container.read(settingsProvider);
    expect(settings.readerDirection, ReaderDirection.rtl);
    expect(settings.readerBackground, ReaderBackground.sepia);
    expect(settings.languageCode, 'ar');
    expect(settings.wifiOnly, isTrue);
    expect(settings.readerKeepAwake, isFalse);
    expect(settings.biometricLockEnabled, isTrue);
    expect(preferences.getString('reader_direction'), 'rtl');
  });

  test(
      'invalid reader data cannot cause a partial library or preference restore',
      () async {
    final (_, container, repository) = await setup({});
    final document = jsonDecode(backup()) as Map<String, Object?>;
    document['reader'] = {
      'bookmarks': {
        unit.id: [-1]
      }
    };
    await expectLater(
      container.read(backupControllerProvider).restore(jsonEncode(document)),
      throwsA(isA<BackupException>()),
    );
    expect(await repository.allMedia(), isEmpty);
    expect(container.read(categoriesProvider), isEmpty);
    expect(container.read(readerProfilesProvider), isEmpty);
    expect(container.read(readerBookmarksProvider), isEmpty);
  });

  testWidgets(
      'export sends a readable backup file to the system sharing boundary',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final directory = Directory('/test/backup-share');
    final repository = MemoryLibraryRepository();
    final share = _ShareCapture();
    final store = _MemoryFileStore();
    final container = ProviderContainer(overrides: [
      preferencesProvider.overrideWithValue(preferences),
      repositoryProvider.overrideWithValue(repository),
      downloadRootProvider.overrideWithValue(directory),
      backupFileSharerProvider.overrideWithValue(share),
      backupFileStoreProvider.overrideWithValue(store),
    ]);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      await repository.close();
    });
    await repository.saveMedia(work);
    await repository.saveUnits([unit]);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const BackupScreen(),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Export backup file'));
    await tester.pumpAndSettle();
    final document = LibraryBackup.decodeDocument(store.document!);
    expect(document.snapshot.media.single.id, work.id);
    expect(share.filePath, endsWith('.json'));
    expect(share.chooserTitle, 'Backup & restore');
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 45)));

  test(
      'the real backup writer flushes readable JSON without overwriting a copy',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('best-backup-files-');
    addTearDown(() => directory.delete(recursive: true));
    const store = BackupFileStore();
    final first = await store.write(backup(), directory);
    final second = await store.write(backup(), directory);
    expect(first.path, isNot(second.path));
    expect(
        LibraryBackup.decodeDocument(await first.readAsString())
            .snapshot
            .media
            .single
            .id,
        work.id);
    expect(await second.exists(), isTrue);
  });
}
