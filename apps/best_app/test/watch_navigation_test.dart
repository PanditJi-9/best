import 'dart:async';

import 'package:best_app/src/l10n/generated/app_localizations.dart';
import 'package:best_app/src/navigation.dart';
import 'package:best_app/src/providers.dart';
import 'package:best_app/src/screens/watch_screen.dart';
import 'package:best_app/src/widgets/chapter_list_sheet.dart';
import 'package:best_domain/best_domain.dart';
import 'package:best_data/best_data.dart';
import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'support/render_capture.dart';

/// Instrumented player commands, not playback evidence. Real decoding and an
/// advancing extension stream remain the separate Android smoke gate.
class _VideoPlatform extends VideoPlayerPlatform {
  final created = <String>[];
  final played = <int>[];
  final paused = <int>[];
  final disposed = <int>[];
  final released = <int>{};
  final playing = <int, bool>{};
  final positions = <int, Duration>{};
  final events = <int, StreamController<VideoEvent>>{};

  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = created.length + 1;
    created.add(options.dataSource.uri!);
    playing[id] = false;
    positions[id] = Duration.zero;
    events[id] = StreamController<VideoEvent>()
      ..add(VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(minutes: 10),
          size: const Size(1920, 1080)));
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => events[playerId]!.stream;

  @override
  Future<void> play(int playerId) async {
    played.add(playerId);
    playing[playerId] = true;
  }

  @override
  Future<void> pause(int playerId) async {
    paused.add(playerId);
    playing[playerId] = false;
  }

  @override
  Future<void> dispose(int playerId) async {
    disposed.add(playerId);
    playing.remove(playerId);
    await events.remove(playerId)?.close();
    released.add(playerId);
  }

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    positions[playerId] = position;
  }

  @override
  Future<Duration> getPosition(int playerId) async =>
      positions[playerId] ?? Duration.zero;
  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {}
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}
  @override
  Future<void> setAllowBackgroundPlayback(bool allowBackgroundPlayback) async {}
  @override
  Widget buildViewWithOptions(VideoViewOptions options) => const Center(
        child:
            Text('Video test surface', style: TextStyle(color: Colors.white54)),
      );
}

Future<void> _waitForDisposal(
  WidgetTester tester,
  _VideoPlatform platform,
  Iterable<int> playerIds,
) async {
  final expected = playerIds.toSet();
  // A render capture runs in the real async zone. Stream cancellation can then
  // cross both that zone and the test's fake clock; drain each without guessing
  // a playback duration or weakening the resource-release assertion.
  for (var attempt = 0; attempt < 50; attempt++) {
    await tester.pump();
    if (platform.released.containsAll(expected)) return;
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  }
  expect(platform.released, containsAll(expected),
      reason: 'Replaced and unmounted video players must finish disposal.');
}

Future<
    ({
      MemoryLibraryRepository repository,
      GoRouter router,
      GlobalKey capture
    })> _open(
  WidgetTester tester,
  _VideoPlatform platform,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  const media = Media(
      ref: SourceRef('test', 'quiet-anime'),
      title: 'A saved anime',
      kind: MediaKind.anime);
  final units = [
    for (var n = 1; n <= 3; n++)
      MediaUnit(
          mediaId: media.id,
          url: 'episode-$n',
          number: n.toDouble(),
          title: 'Episode $n',
          kind: UnitKind.episode)
  ];
  final repository = MemoryLibraryRepository();
  await repository.saveMedia(media);
  await repository.saveUnits(units);
  await repository.saveProgress(UnitProgress(
      unitId: units[1].id,
      position: 37,
      total: 600,
      started: true,
      updatedAt: 1));
  final container = ProviderContainer(overrides: [
    repositoryProvider.overrideWithValue(repository),
    watchProvider.overrideWith((ref, key) async {
      final unit = units.firstWhere((unit) => unit.url == key.unitUrl);
      return WatchData(
          media: media,
          unit: unit,
          units: units,
          stream: VideoResource('https://video.test/${unit.url}.mp4'),
          progress: await repository.progressFor(unit.id));
    }),
  ]);
  final router =
      GoRouter(initialLocation: Routes.watchOf(media, units.first), routes: [
    GoRoute(
        path: '/watch',
        builder: (_, state) => WatchScreen(
            sourceId: 'test',
            url: media.ref.url,
            unitUrl: state.uri.queryParameters['unit']!)),
  ]);
  final capture = GlobalKey();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await _waitForDisposal(tester, platform,
        [for (var id = 1; id <= platform.created.length; id++) id]);
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
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        )),
  ));
  await tester.pumpAndSettle();
  return (repository: repository, router: router, capture: capture);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _VideoPlatform platform;
  setUpAll(() async {
    WidgetController.hitTestWarningShouldBeFatal = true;
    await loadBestTestFonts();
  });
  setUp(() {
    final previous = VideoPlayerPlatform.instance;
    platform = _VideoPlatform();
    VideoPlayerPlatform.instance = platform;
    addTearDown(() => VideoPlayerPlatform.instance = previous);
  });

  testWidgets(
      'choosing an episode pauses the old player, resumes the target and replaces its route',
      (tester) async {
    final fixture = await _open(tester, platform);
    expect(platform.playing[1], isTrue);
    await tester.tap(find.byKey(const ValueKey('watch-episode-picker')));
    await tester.pumpAndSettle();
    expect(find.text('Episodes'), findsOneWidget);
    expect(find.text('Chapters'), findsNothing);
    expect(platform.playing[1], isFalse);
    await captureRender(
        tester, fixture.capture, 'chapter-tools-episodes-en.png');
    await tester.tap(find.text('Episode 2').last);
    await tester.pumpAndSettle();
    await _waitForDisposal(tester, platform, [1]);
    expect(platform.created, [
      'https://video.test/episode-1.mp4',
      'https://video.test/episode-2.mp4'
    ]);
    expect(platform.positions[2], const Duration(seconds: 37));
    expect(platform.playing[2], isTrue);
    expect(platform.disposed, contains(1));
    expect(find.byType(VideoPlayer, skipOffstage: false), findsOneWidget);
    expect(fixture.router.canPop(), isFalse);
    final progress = await fixture.repository.allProgress();
    expect(progress.any((row) => row.started && row.position == 0), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dismissing the episode list resumes the same playing episode',
      (tester) async {
    await _open(tester, platform);
    await tester.tap(find.byKey(const ValueKey('watch-episode-picker')));
    await tester.pumpAndSettle();
    expect(platform.playing[1], isFalse);
    Navigator.of(tester.element(find.byType(ChapterListSheet))).pop();
    await tester.pumpAndSettle();
    expect(platform.created, hasLength(1));
    expect(platform.playing[1], isTrue);
  });

  testWidgets(
      'closing the list never starts an episode that was already paused',
      (tester) async {
    await _open(tester, platform);
    await tester.tap(find.byTooltip('Pause'));
    await tester.pumpAndSettle();
    expect(platform.playing[1], isFalse);
    await tester.tap(find.byKey(const ValueKey('watch-episode-picker')));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(ChapterListSheet))).pop();
    await tester.pumpAndSettle();
    expect(platform.playing[1], isFalse);
    expect(platform.played, [1]);
  });
}
