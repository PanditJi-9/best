import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:best_domain/best_domain.dart';
import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../l10n/generated/app_localizations.dart';
import '../labels.dart';
import '../navigation.dart';
import '../providers.dart';

/// The video surface for an episode.
///
/// The screen owns one [VideoPlayerController] and one progress row. Every
/// five seconds (and on pause, back and dispose) the position is written in
/// seconds, so the shelf can offer the same episode on the next launch. The
/// player is intentionally dark in both themes: video is the content, not the
/// chrome around it.
class WatchScreen extends ConsumerWidget {
  const WatchScreen({
    super.key,
    required this.sourceId,
    required this.url,
    required this.unitUrl,
  });

  final String sourceId;
  final String url;
  final String unitUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final key = (sourceId: sourceId, url: url, unitUrl: unitUrl);
    final data = ref.watch(watchProvider(key));

    return Theme(
      data: bestTheme(Brightness.dark),
      child: data.when(
        loading: () => const _PlayerScaffold(
          child:
              Center(child: CircularProgressIndicator(color: Colors.white70)),
        ),
        error: (error, stack) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
          ),
          body: EmptyState(
            icon: Icons.play_disabled_outlined,
            title: l10n.playbackError,
            body: '$error',
            action: FilledButton.icon(
              onPressed: () => ref.invalidate(watchProvider(key)),
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(l10n.retry),
            ),
          ),
        ),
        data: (data) => _WatchView(key: ValueKey(data.unit.id), data: data),
      ),
    );
  }
}

class _PlayerScaffold extends StatelessWidget {
  const _PlayerScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: child),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 4,
            left: 4,
            child: IconButton(
              tooltip: AppLocalizations.of(context).backToSeries,
              onPressed: () => _leave(context),
              icon: const Icon(Icons.arrow_back, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _WatchView extends ConsumerStatefulWidget {
  const _WatchView({super.key, required this.data});

  final WatchData data;

  @override
  ConsumerState<_WatchView> createState() => _WatchViewState();
}

class _WatchViewState extends ConsumerState<_WatchView> {
  VideoPlayerController? _controller;
  bool _ready = false;
  String? _error;
  bool _controlsVisible = true;
  bool _fullscreen = false;
  bool _awake = false;
  bool _saving = false;
  bool _completedSaved = false;
  int _lastSavedSecond = -1;

  /// Whole seconds of playback not yet written to the activity log. A save
  /// lands every five seconds, so this is a coarse clock, not a stopwatch.
  int _watchedSeconds = 0;

  /// Captions for this stream. Empty when the source ships none, or when the
  /// file could not be read: a broken subtitle must never stop a film.
  List<SubtitleCue> _cues = const [];
  bool _subtitlesOn = true;
  String? _subtitleText;

  int _attempt = 0;
  double _speed = 1;
  double? _dragSeconds;
  Timer? _hideTimer;

  /// A completed unit is never moved backwards by a replay. The row keeps its
  /// end position until the person finishes the episode again.
  bool get _wasCompleted => widget.data.progress?.completed ?? false;

  @override
  void initState() {
    super.initState();
    _completedSaved = _wasCompleted;
    unawaited(_open());
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _saveFinal();
    final controller = _controller;
    controller?.removeListener(_onValue);
    unawaited(controller?.dispose() ?? Future<void>.value());
    unawaited(_keepAwake(false));
    if (_fullscreen) {
      unawaited(SystemChrome.setPreferredOrientations(const []));
      unawaited(
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge),
      );
    }
    super.dispose();
  }

  Future<void> _open() async {
    final attempt = ++_attempt;
    final previous = _controller;
    _controller = null;
    if (previous != null) {
      previous.removeListener(_onValue);
      await previous.dispose();
    }
    if (!mounted) return;
    setState(() {
      _ready = false;
      _error = null;
      _dragSeconds = null;
    });

    final controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.data.stream.url),
      httpHeaders: widget.data.stream.headers,
    );
    _controller = controller;
    controller.addListener(_onValue);
    unawaited(_loadSubtitles());

    try {
      await controller.initialize();
      if (!mounted || attempt != _attempt) {
        await controller.dispose();
        return;
      }

      final start = PlaybackProgress.resumeAt(
        savedSeconds: widget.data.progress?.position ?? 0,
        duration: controller.value.duration,
      );
      if (start > Duration.zero) {
        await controller.seekTo(start);
      }
      await controller.setPlaybackSpeed(_speed);
      await controller.play();
      await _keepAwake(true);
      if (!mounted || attempt != _attempt) return;

      setState(() => _ready = true);
      _scheduleHide();
    } catch (error) {
      if (!mounted || attempt != _attempt) return;
      setState(() => _error = '$error');
    }
  }

  /// Reads the caption track once per stream: a bundled `asset://` file, or a
  /// URL from the source. Failure is silent and the CC button stays hidden.
  Future<void> _loadSubtitles() async {
    final url = widget.data.stream.subtitleUrl;
    if (url == null) {
      if (mounted && _cues.isNotEmpty) {
        setState(() {
          _cues = const [];
          _subtitleText = null;
        });
      }
      return;
    }
    try {
      final String raw;
      if (url.startsWith('asset://')) {
        raw = await rootBundle.loadString(url.substring('asset://'.length));
      } else {
        final response = await ref.read(httpClientProvider).get(Uri.parse(url));
        if (response.statusCode != 200) return;
        raw = utf8.decode(response.bodyBytes, allowMalformed: true);
      }
      final cues = Subtitles.parse(raw);
      if (!mounted || cues.isEmpty) return;
      setState(() {
        _cues = cues;
        _subtitleText = null;
      });
    } catch (_) {
      // Captions are a bonus, not a requirement.
    }
  }

  /// Only rebuilds when the visible line changes, not on every player tick.
  void _syncSubtitle(Duration position) {
    final text = _subtitlesOn && _cues.isNotEmpty
        ? Subtitles.textAt(_cues, position)
        : null;
    if (text == _subtitleText) return;
    setState(() => _subtitleText = text);
  }

  void _toggleSubtitles() {
    setState(() {
      _subtitlesOn = !_subtitlesOn;
      if (!_subtitlesOn) _subtitleText = null;
    });
    _showControls();
  }

  void _onValue() {
    final controller = _controller;
    if (controller == null || !mounted) return;
    final value = controller.value;

    if (value.hasError && _error == null) {
      setState(() => _error = value.errorDescription ?? 'Playback failed.');
      return;
    }
    if (!value.isInitialized) return;

    _syncSubtitle(value.position);
    _maybeSave(value);
    unawaited(_keepAwake(value.isPlaying));
  }

  void _maybeSave(VideoPlayerValue value) {
    if (_saving) return;
    final finished = PlaybackProgress.isFinished(
      position: value.position,
      duration: value.duration,
    );
    if (_wasCompleted && !finished) return;

    final second = value.position.inSeconds;
    if (!finished && (second - _lastSavedSecond).abs() < 5) return;
    if (finished && _completedSaved) return;

    final row = PlaybackProgress.toProgress(
      unitId: widget.data.unit.id,
      position: value.position,
      duration: value.duration,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      completed: _wasCompleted,
    );
    if (row == null) return;

    _lastSavedSecond = second;
    if (finished) _completedSaved = true;
    if (value.isPlaying) {
      _watchedSeconds += 5;
      if (_watchedSeconds >= 60) {
        final minutes = _watchedSeconds ~/ 60;
        _watchedSeconds -= minutes * 60;
        unawaited(
          ref.read(repositoryProvider).recordActivity(minutes: minutes),
        );
      }
    }
    _saving = true;
    unawaited(
      ref.read(repositoryProvider).saveProgress(row).whenComplete(() {
        _saving = false;
      }),
    );
  }

  void _saveFinal() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final value = controller.value;
    final finished = PlaybackProgress.isFinished(
      position: value.position,
      duration: value.duration,
    );
    if (_wasCompleted && !finished) return;

    final row = PlaybackProgress.toProgress(
      unitId: widget.data.unit.id,
      position: value.position,
      duration: value.duration,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      completed: _wasCompleted,
    );
    if (row == null) return;
    unawaited(ref.read(repositoryProvider).saveProgress(row));
  }

  Future<void> _keepAwake(bool enabled) async {
    if (_awake == enabled) return;
    _awake = enabled;
    try {
      await WakelockPlus.toggle(enable: enabled);
    } catch (_) {
      // A platform without the plugin still plays video; the screen dimming is
      // a comfort issue, not a reason to fail the episode.
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      if (_controller?.value.isPlaying ?? false) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _showControls() {
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  void _toggleControls() {
    _hideTimer?.cancel();
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  Future<void> _togglePlay() async {
    final controller = _controller;
    if (controller == null) return;
    final value = controller.value;

    if (value.isCompleted) {
      await controller.seekTo(Duration.zero);
      await controller.play();
      _showControls();
      return;
    }
    if (value.isPlaying) {
      await controller.pause();
      _hideTimer?.cancel();
      if (!_controlsVisible) setState(() => _controlsVisible = true);
    } else {
      await controller.play();
      _showControls();
    }
  }

  Future<void> _seekBy(int seconds) async {
    final controller = _controller;
    if (controller == null) return;
    final value = controller.value;
    final target = value.position + Duration(seconds: seconds);
    final upper = value.duration > Duration.zero ? value.duration : target;
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > upper ? upper : target);
    await controller.seekTo(clamped);
    _showControls();
  }

  Future<void> _setSpeed(double speed) async {
    setState(() => _speed = speed);
    await _controller?.setPlaybackSpeed(speed);
    _showControls();
  }

  Future<void> _toggleFullscreen() async {
    final next = !_fullscreen;
    setState(() => _fullscreen = next);
    if (next) {
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      await SystemChrome.setPreferredOrientations(const []);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    _showControls();
  }

  Future<void> _handleBack() async {
    if (_fullscreen) {
      await _toggleFullscreen();
      return;
    }
    _leave(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = _controller;

    return PopScope(
      canPop: !_fullscreen,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _fullscreen) unawaited(_toggleFullscreen());
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: controller == null
            ? _loading(l10n)
            : ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: controller,
                builder: (context, value, child) {
                  if (_error != null) return _errorView(l10n);
                  if (!_ready || !value.isInitialized) return _loading(l10n);

                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      Center(
                        child: AspectRatio(
                          aspectRatio: value.aspectRatio,
                          child: VideoPlayer(controller),
                        ),
                      ),
                      if (value.isBuffering)
                        const Center(
                          child: CircularProgressIndicator(
                            color: Colors.white70,
                          ),
                        ),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _toggleControls,
                        child: AnimatedOpacity(
                          opacity: _controlsVisible ? 1 : 0,
                          duration: const Duration(milliseconds: 180),
                          child: IgnorePointer(
                            ignoring: !_controlsVisible,
                            child: _controls(context, l10n, controller, value),
                          ),
                        ),
                      ),
                      if (_subtitleText != null)
                        _SubtitleOverlay(
                          text: _subtitleText!,
                          bottom: _controlsVisible ? 96 : 26,
                        ),
                    ],
                  );
                },
              ),
      ),
    );
  }

  Widget _loading(AppLocalizations l10n) {
    return Stack(
      children: [
        const Center(
          child: CircularProgressIndicator(color: Colors.white70),
        ),
        Positioned(
          top: MediaQuery.paddingOf(context).top + 4,
          left: 4,
          child: IconButton(
            tooltip: l10n.backToSeries,
            onPressed: _handleBack,
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),
        ),
      ],
    );
  }

  Widget _errorView(AppLocalizations l10n) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.play_disabled_outlined,
              color: Colors.white54,
              size: 52,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.playbackError,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? '',
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: _open,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(l10n.retry),
            ),
            TextButton(
              onPressed: _handleBack,
              child: Text(l10n.backToSeries),
            ),
          ],
        ),
      ),
    );
  }

  Widget _controls(
    BuildContext context,
    AppLocalizations l10n,
    VideoPlayerController controller,
    VideoPlayerValue value,
  ) {
    final padding = MediaQuery.paddingOf(context);
    final duration = value.duration;
    final totalMs = duration.inMilliseconds;
    final positionMs = _dragSeconds != null
        ? (_dragSeconds! * 1000).round()
        : value.position.inMilliseconds;
    final shownPosition = Duration(
      milliseconds: positionMs.clamp(0, math.max(totalMs, 0)),
    );

    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black87, Colors.transparent],
              ),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(4, padding.top + 4, 12, 32),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    tooltip: l10n.backToSeries,
                    onPressed: _handleBack,
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.data.media.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.data.unit.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                            ),
                          ),
                          if (widget.data.sample) ...[
                            const SizedBox(height: 4),
                            Text(
                              l10n.sampleStream,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 10,
                                letterSpacing: 0,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _RoundButton(
                icon: Icons.replay_10,
                tooltip: l10n.skipBack,
                onPressed: () => _seekBy(-10),
              ),
              const SizedBox(width: 26),
              _RoundButton(
                icon: value.isPlaying
                    ? Icons.pause
                    : (value.isCompleted ? Icons.replay : Icons.play_arrow),
                tooltip: value.isPlaying
                    ? l10n.pause
                    : (value.isCompleted ? l10n.replay : l10n.play),
                big: true,
                onPressed: _togglePlay,
              ),
              const SizedBox(width: 26),
              _RoundButton(
                icon: Icons.forward_10,
                tooltip: l10n.skipForward,
                onPressed: () => _seekBy(10),
              ),
            ],
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black87, Colors.transparent],
              ),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 44, 16, padding.bottom + 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        activeTrackColor: BestColors.jade,
                        inactiveTrackColor: Colors.white24,
                        thumbColor: BestColors.jade,
                        overlayColor: BestColors.jade.withValues(alpha: 0.18),
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 16,
                        ),
                      ),
                      child: Slider(
                        value: totalMs <= 0
                            ? 0
                            : positionMs.clamp(0, totalMs).toDouble(),
                        max: totalMs <= 0 ? 1 : totalMs.toDouble(),
                        onChangeStart: (value) {
                          _hideTimer?.cancel();
                          setState(() => _dragSeconds = value / 1000);
                        },
                        onChanged: (value) {
                          setState(() => _dragSeconds = value / 1000);
                        },
                        onChangeEnd: (value) async {
                          await controller.seekTo(
                            Duration(milliseconds: value.round()),
                          );
                          if (mounted) setState(() => _dragSeconds = null);
                          _showControls();
                        },
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(
                          '${formatClock(shownPosition.inSeconds)} / '
                          '${formatClock(duration.inSeconds)}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (_cues.isNotEmpty)
                        IconButton(
                          tooltip: _subtitlesOn
                              ? l10n.subtitlesOn
                              : l10n.subtitlesOff,
                          onPressed: _toggleSubtitles,
                          icon: Icon(
                            _subtitlesOn
                                ? Icons.closed_caption
                                : Icons.closed_caption_off_outlined,
                            color: _subtitlesOn
                                ? BestColors.jade
                                : Colors.white70,
                          ),
                        ),
                      PopupMenuButton<double>(
                        tooltip: l10n.playbackSpeed,
                        initialValue: _speed,
                        onSelected: _setSpeed,
                        itemBuilder: (context) => [
                          for (final speed in const [0.75, 1.0, 1.25, 1.5, 2.0])
                            PopupMenuItem<double>(
                              value: speed,
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 24,
                                    child: speed == _speed
                                        ? const Icon(Icons.check, size: 16)
                                        : null,
                                  ),
                                  Text('${speed}x'),
                                ],
                              ),
                            ),
                        ],
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          child: Text(
                            '${_speed}x',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip:
                            _fullscreen ? l10n.exitFullscreen : l10n.fullscreen,
                        onPressed: _toggleFullscreen,
                        icon: Icon(
                          _fullscreen
                              ? Icons.fullscreen_exit
                              : Icons.fullscreen,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Captions sit above the picture, not inside the control layer, so pausing to
/// read a line does not also hide it. Two outlines keep white text readable on
/// a bright frame without a background box.
class _SubtitleOverlay extends StatelessWidget {
  const _SubtitleOverlay({required this.text, required this.bottom});

  final String text;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 18,
      right: 18,
      bottom: bottom,
      child: IgnorePointer(
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.only(
            bottom: MediaQuery.paddingOf(context).bottom,
          ),
          child: Center(
            child: Text(
              text,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                height: 1.32,
                fontWeight: FontWeight.w600,
                shadows: [
                  Shadow(blurRadius: 6, color: Colors.black87),
                  Shadow(blurRadius: 2, offset: Offset(1, 1), color: Colors.black),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.big = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final size = big ? 68.0 : 46.0;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      iconSize: big ? 38 : 24,
      style: IconButton.styleFrom(
        backgroundColor:
            big ? BestColors.jade : Colors.black.withValues(alpha: 0.35),
        foregroundColor: big ? BestColors.ink : Colors.white,
        fixedSize: Size(size, size),
      ),
      icon: Icon(icon),
    );
  }
}

void _leave(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(Routes.home);
  }
}
