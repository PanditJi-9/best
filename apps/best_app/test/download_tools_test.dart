import 'dart:async';
import 'dart:io';

import 'package:best_app/src/l10n/generated/app_localizations.dart';
import 'package:best_app/src/providers.dart';
import 'package:best_app/src/screens/downloads_screen.dart';
import 'package:best_app/src/widgets/download_integrity_dialog.dart';
import 'package:best_app/src/widgets/reader_download_tile.dart';
import 'package:best_data/best_data.dart';
import 'package:best_domain/best_domain.dart';
import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/render_capture.dart';

class _Source implements SourceAdapter {
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
  Future<List<MediaUnit>> units(Media media) async => [];
  @override
  Future<List<MediaResource>> resources(MediaUnit unit) async => [];
}

/// UI boundary fixture only. Real hashes, files, signed requests and repair
/// byte accounting are exercised by best_data's download-manager tests.
class _Manager extends DownloadManager {
  _Manager(MemoryLibraryRepository repository, SourceRegistry registry)
      : this._(
            repository,
            registry,
            MockClient(
                (_) async => throw StateError('No UI check may fetch bytes')));

  _Manager._(this.repository, SourceRegistry registry, this.client)
      : super(
            repository: repository,
            registry: registry,
            client: client,
            root: Directory('/test/downloads'));

  final MemoryLibraryRepository repository;
  final http.Client client;
  DownloadIntegrityReport report =
      const DownloadIntegrityReport(total: 3, available: 3, verified: 3);
  int checks = 0;
  int repairs = 0;
  int pauses = 0;
  int resumes = 0;
  int enqueues = 0;
  Completer<void>? enqueueGate;

  @override
  Future<DownloadIntegrityReport> checkStored(String unitId) async {
    checks++;
    final task = await repository.downloadFor(unitId);
    if (task != null && task.isFinished && report.hasProblems && !report.busy) {
      await repository.saveDownload(task.copyWith(
          status: DownloadStatus.failed,
          completed: report.available,
          error: DownloadException.storedPagesChanged));
    }
    return report;
  }

  @override
  Future<DownloadIntegrityReport> repair(String unitId) async {
    repairs++;
    final task = (await repository.downloadFor(unitId))!;
    await repository.saveDownload(task.copyWith(
        status: report.isComplete ? DownloadStatus.done : DownloadStatus.queued,
        completed: report.available,
        clearError: true));
    return report;
  }

  @override
  Future<void> pause(String unitId) async {
    pauses++;
    final task = (await repository.downloadFor(unitId))!;
    await repository.saveDownload(task.copyWith(status: DownloadStatus.paused));
    report = DownloadIntegrityReport(
        total: report.total,
        available: report.available,
        verified: report.verified,
        missing: report.missing,
        changed: report.changed);
  }

  @override
  Future<void> resume(String unitId) async {
    resumes++;
    final task = (await repository.downloadFor(unitId))!;
    await repository.saveDownload(task.copyWith(status: DownloadStatus.queued));
  }

  @override
  Future<void> retry(String unitId) => resume(unitId);

  @override
  Future<DownloadTask> enqueue(Media media, MediaUnit unit) async {
    enqueues++;
    await enqueueGate?.future;
    final task = DownloadTask(
        unitId: unit.id,
        mediaId: media.id,
        sourceId: media.ref.sourceId,
        mediaUrl: media.ref.url,
        unitUrl: unit.url,
        mediaTitle: media.title,
        unitTitle: unit.title,
        total: unit.pageCount);
    await repository.saveDownload(task);
    return task;
  }

  @override
  void dispose() {
    client.close();
    super.dispose();
  }
}

const _media = Media(
    ref: SourceRef('test', 'blue-echo'),
    title: 'Blue Echo',
    kind: MediaKind.manga);
final _unit = MediaUnit(
    mediaId: _media.id,
    url: 'chapter-1',
    number: 1,
    title: 'Chapter 1',
    kind: UnitKind.chapter,
    pageCount: 3);

DownloadTask _task(
    {Media media = _media,
    int chapter = 1,
    DownloadStatus status = DownloadStatus.done}) {
  final unit = MediaUnit(
      mediaId: media.id,
      url: 'chapter-$chapter',
      number: chapter.toDouble(),
      title: 'Chapter $chapter',
      kind: UnitKind.chapter);
  return DownloadTask(
      unitId: unit.id,
      mediaId: media.id,
      sourceId: media.ref.sourceId,
      mediaUrl: media.ref.url,
      unitUrl: unit.url,
      mediaTitle: media.title,
      unitTitle: unit.title,
      total: 3,
      completed: status == DownloadStatus.done ? 3 : 1,
      bytes: status == DownloadStatus.done ? 12000 : 4000,
      directory: '/test/offline/${media.ref.url}/chapter-$chapter',
      status: status);
}

class _Fixture {
  const _Fixture(this.repository, this.manager, this.container, this.capture);
  final MemoryLibraryRepository repository;
  final _Manager manager;
  final ProviderContainer container;
  final GlobalKey capture;
}

Future<_Fixture> _open(
  WidgetTester tester, {
  List<DownloadTask> tasks = const [],
  bool readerTile = false,
  bool sourceMissing = false,
  String language = 'en',
  Size size = const Size(390, 844),
  double textScale = 1,
  DownloadIntegrityReport? report,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final repository = MemoryLibraryRepository();
  await repository.saveMedia(_media);
  await repository.saveUnits([_unit]);
  for (final task in tasks) {
    await repository.saveDownload(task);
  }
  final registry = SourceRegistry.fixed(sourceMissing ? [] : [_Source()]);
  final manager = _Manager(repository, registry);
  if (report != null) manager.report = report;
  final container = ProviderContainer(overrides: [
    repositoryProvider.overrideWithValue(repository),
    preferencesProvider.overrideWithValue(preferences),
    sourceRegistryProvider.overrideWithValue(registry),
    downloadManagerProvider.overrideWithValue(manager),
  ]);
  final capture = GlobalKey();
  final router = GoRouter(routes: [
    GoRoute(
        path: '/',
        builder: (_, state) => Scaffold(
            body: readerTile
                ? SingleChildScrollView(
                    child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: ReaderDownloadTile(media: _media, unit: _unit)))
                : const DownloadsScreen())),
    GoRoute(
        path: '/sources',
        builder: (_, state) => const Scaffold(body: Text('Source directory'))),
    GoRoute(
        path: '/read',
        builder: (_, state) => const Scaffold(body: Text('Offline reader'))),
  ]);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    container.dispose();
    manager.dispose();
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
              child: child!),
        )),
  ));
  await tester.pumpAndSettle();
  return _Fixture(repository, manager, container, capture);
}

Future<void> _checkFromRow(WidgetTester tester, DownloadTask task) async {
  final row = find.byKey(ValueKey('download-${task.unitId}'));
  await tester.ensureVisible(row);
  await tester.pumpAndSettle();
  await tester.tap(find.descendant(of: row, matching: find.byTooltip('More')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Check saved pages'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    WidgetController.hitTestWarningShouldBeFatal = true;
    await loadBestTestFonts();
  });

  testWidgets('file checks do not queue repair until it is explicitly selected',
      (tester) async {
    final task = _task();
    final fixture = await _open(tester,
        tasks: [task],
        report: const DownloadIntegrityReport(
            total: 3, available: 1, verified: 1, missing: [1], changed: [2]));
    await fixture.repository.saveProgress(UnitProgress(
        unitId: task.unitId,
        position: 8,
        total: 20,
        started: true,
        updatedAt: 1));
    await _checkFromRow(tester, task);
    expect(fixture.manager.checks, 1);
    expect(fixture.manager.repairs, 0);
    expect(find.text('Missing files: 1'), findsOneWidget);
    expect(find.text('Empty or changed files: 1'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Repair download'));
    await tester.pumpAndSettle();
    expect(fixture.manager.repairs, 1);
    expect(find.text('Repair queued'), findsOneWidget);
    expect((await fixture.repository.progressFor(task.unitId))!.position, 8);
    expect((await fixture.repository.downloadFor(task.unitId))!.directory,
        task.directory);
  });

  testWidgets('legacy files are not presented as checksum-verified',
      (tester) async {
    final task = _task();
    await _open(tester,
        tasks: [task],
        report: const DownloadIntegrityReport(total: 3, available: 3));
    await _checkFromRow(tester, task);
    expect(find.textContaining('no saved checksum'), findsOneWidget);
    expect(find.textContaining('match their saved SHA-256'), findsNothing);
    expect(find.text('Repair download'), findsNothing);
  });

  testWidgets('download search and failed filter leave saved rows untouched',
      (tester) async {
    const arabic = Media(
        ref: SourceRef('test', 'forest'),
        title: 'أسرار الغابة',
        kind: MediaKind.manga);
    final done = _task();
    final failed =
        _task(media: arabic, chapter: 2, status: DownloadStatus.failed);
    final paused = _task(chapter: 3, status: DownloadStatus.paused);
    final fixture = await _open(tester, tasks: [done, failed, paused]);
    await captureRender(tester, fixture.capture, 'download-tools-list-en.png');
    await tester.enterText(
        find.byKey(const ValueKey('downloads-search')), 'اسرار');
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('download-${failed.unitId}')), findsOneWidget);
    expect(find.byKey(ValueKey('download-${done.unitId}')), findsNothing);
    await tester.enterText(
        find.byKey(const ValueKey('downloads-search')), 'الفصل ٢');
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('download-${failed.unitId}')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('downloads-search')), '');
    final chip = find.text('Failed · 1');
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('download-${failed.unitId}')), findsOneWidget);
    expect(find.byKey(ValueKey('download-${paused.unitId}')), findsNothing);
    expect(await fixture.repository.downloads(), hasLength(3));
  });

  testWidgets(
      'reader controls pause and resume the same task rather than enqueue it again',
      (tester) async {
    final task = _task(status: DownloadStatus.queued);
    final fixture = await _open(tester, tasks: [task], readerTile: true);
    await tester.tap(find.byTooltip('Pause download'));
    await tester.pumpAndSettle();
    expect(find.text('Paused'), findsOneWidget);
    expect(fixture.manager.pauses, 1);
    await tester.tap(find.byTooltip('Resume download'));
    await tester.pumpAndSettle();
    expect(fixture.manager.resumes, 1);
    expect(fixture.manager.enqueues, 0);
    expect((await fixture.repository.downloadFor(task.unitId))!.completed, 1);
  });

  testWidgets('a new reader download ignores overlapping taps', (tester) async {
    final fixture = await _open(tester, readerTile: true);
    final gate = Completer<void>();
    fixture.manager.enqueueGate = gate;
    await tester.tap(find.byTooltip('Download chapter'));
    await tester.tap(find.byTooltip('Download chapter'));
    gate.complete();
    await tester.pumpAndSettle();
    expect(fixture.manager.enqueues, 1);
  });

  testWidgets(
      'a source-free damaged archive offers recovery, not destructive replacement',
      (tester) async {
    final task = _task();
    final fixture = await _open(tester,
        tasks: [task],
        sourceMissing: true,
        report: const DownloadIntegrityReport(
            total: 3, available: 2, missing: [1]));
    await _checkFromRow(tester, task);
    expect(find.text('Repair download'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, 'Source directory'));
    await tester.pumpAndSettle();
    expect(find.text('Source directory'), findsOneWidget);
    expect(await fixture.repository.downloads(), hasLength(1));
    expect(fixture.manager.repairs, 0);
  });

  testWidgets(
      'Arabic integrity and paused controls fit a narrow large-text phone',
      (tester) async {
    final task = _task(status: DownloadStatus.paused);
    final fixture = await _open(tester,
        tasks: [task],
        readerTile: true,
        language: 'ar',
        size: const Size(320, 640),
        textScale: 1.35,
        report: const DownloadIntegrityReport(
            total: 3, available: 1, missing: [1], changed: [2]));
    await captureRender(
        tester, fixture.capture, 'download-tools-reader-ar.png');
    await tester.tap(find.text('فحص الصفحات المحفوظة'));
    await tester.pumpAndSettle();
    expect(find.text('الملفات الناقصة: 1'), findsOneWidget);
    await captureRender(
        tester, fixture.capture, 'download-tools-integrity-ar.png');
    expect(tester.takeException(), isNull);
  });

  testWidgets('active checks require a pause and then run another local check',
      (tester) async {
    final task = _task(status: DownloadStatus.running);
    final fixture = await _open(tester,
        tasks: [task],
        report:
            const DownloadIntegrityReport(total: 3, available: 1, busy: true));
    await tester.pumpWidget(UncontrolledProviderScope(
        container: fixture.container,
        child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: DownloadIntegrityDialog(task: task))));
    await tester.pumpAndSettle();
    expect(find.text('Repair download'), findsNothing);
    await tester.tap(find.text('Pause download'));
    await tester.pumpAndSettle();
    expect(fixture.manager.pauses, 1);
    expect(fixture.manager.checks, 2);
  });
}
