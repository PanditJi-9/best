import 'dart:async';
import 'dart:io';

import 'package:best_domain/best_domain.dart';
import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../extension_host.dart';
import '../l10n/generated/app_localizations.dart';
import '../labels.dart';
import '../navigation.dart';
import '../ocr/bubble_overlay_widget.dart';
import '../ocr/ocr_client.dart';
import '../providers.dart';
import '../reader/vertical_strip.dart';
import '../widgets/chapter_list_sheet.dart';
import '../widgets/reader_color_filter.dart';
import '../widgets/reader_controls_bar.dart';
import '../widgets/reader_gesture_viewport.dart';
import '../widgets/reader_page_grid.dart';
import '../widgets/reader_quick_dock.dart';
import '../widgets/reader_reading_hud.dart';
import '../widgets/reader_settings_sheet.dart';

class ReaderScreen extends ConsumerWidget {
  const ReaderScreen({
    super.key,
    required this.sourceId,
    required this.url,
    required this.unitUrl,
    this.startAtEnd = false,
    this.fromStart = false,
  });

  final String sourceId;
  final String url;
  final String unitUrl;
  final bool fromStart;

  /// Going *back* a chapter starts on its last page, the way a paper volume
  /// works. Without saved progress, opening it at page one would reverse the
  /// reading flow the person just asked for.
  final bool startAtEnd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final key = (sourceId: sourceId, url: url, unitUrl: unitUrl);
    final data = ref.watch(readerProvider(key));

    return data.when(
      loading: () => const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      ),
      error: (error, stack) => Theme(
        data: bestTheme(Brightness.dark),
        child: Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
          ),
          backgroundColor: Colors.black,
          body: EmptyState(
            icon: Icons.broken_image_outlined,
            title: error is SourceNotInstalled
                ? l10n.sourceNotInstalledTitle
                : l10n.sourceError,
            body: error is SourceNotInstalled
                ? l10n.sourceNotInstalledBody
                : '$error',
            action: FilledButton.icon(
              onPressed: error is SourceNotInstalled
                  ? () => context.push(Routes.sources)
                  : () => ref.invalidate(readerProvider(key)),
              icon: Icon(
                error is SourceNotInstalled
                    ? Icons.extension_outlined
                    : Icons.refresh,
                size: 18,
              ),
              label: Text(
                error is SourceNotInstalled ? l10n.directoryTitle : l10n.retry,
              ),
            ),
          ),
        ),
      ),
      data: (reader) => _ReaderView(
        key: ValueKey(reader.unit.id),
        data: reader,
        startAtEnd: startAtEnd,
        fromStart: fromStart,
      ),
    );
  }
}

class _ReaderView extends ConsumerStatefulWidget {
  const _ReaderView({
    super.key,
    required this.data,
    this.startAtEnd = false,
    this.fromStart = false,
  });

  final ReaderData data;
  final bool startAtEnd;
  final bool fromStart;

  @override
  ConsumerState<_ReaderView> createState() => _ReaderViewState();
}

class _VerticalZoomAnchor {
  _VerticalZoomAnchor(this.index, this.fraction, this.focal);

  final int index;
  final double fraction;
  double focal;
}

class _ReaderViewState extends ConsumerState<_ReaderView>
    with WidgetsBindingObserver {
  /// Readers replace each other when a chapter ends, and the old one is
  /// disposed *after* the new one starts. Restoring the system UI or releasing
  /// the wakelock on every dispose would therefore undo the new chapter.
  static int _openReaders = 0;

  PageController? _pagedController;
  ReaderPageLayout? _pagedLayout;
  ReaderDirection? _pagedDirection;
  ReaderMode? _lastMode;
  late final LibraryRepository _repository;
  final ItemScrollController _verticalController = ItemScrollController();
  final ScrollOffsetController _verticalOffsetController =
      ScrollOffsetController();
  final GlobalKey<ReaderGestureViewportState> _viewportKey = GlobalKey();
  final ItemPositionsListener _verticalPositions =
      ItemPositionsListener.create();
  late int _index;
  Timer? _saveTimer;
  Timer? _autoScrollTimer;

  /// Reading time is local activity, like pages. Count visible minutes in
  /// whole-minute steps so statistics and the streak include reading, not only
  /// video. A partial minute is carried into the next flush.
  Timer? _readingTimer;
  DateTime? _readingSince;
  int _pendingReadingSeconds = 0;

  /// Share of the strip above the reading line, from 0 to 1. A notifier keeps
  /// scrolling from rebuilding the whole reader for a percentage.
  final ValueNotifier<double> _verticalProgress = ValueNotifier<double>(0);
  late double _autoScrollSpeed = ref.read(readerAutoScrollSpeedProvider);
  bool _autoScrolling = false;

  /// The furthest page reached in this session. Activity counts new ground
  /// only: flipping back and forth is one page read, not twenty.
  late int _furthest;

  List<MediaResource> get _resources => widget.data.resources;

  bool _showChrome = false;
  bool _readerZoomed = false;
  bool _gestureInputLocked = false;
  bool _scrubbing = false;
  bool _freezeVerticalPositions = false;
  bool _zoomGestureEnded = false;
  bool _zoomCorrectionRunning = false;
  bool _zoomCorrectionQueued = false;
  bool _manualScrollScheduled = false;
  bool _manualZoomScroll = false;
  double _pendingManualScroll = 0;
  int _zoomRevision = 0;
  int _navigationGestureRevision = 0;
  _VerticalZoomAnchor? _zoomAnchor;
  bool _awake = false;
  bool _openingUnit = false;
  bool _refreshingPartial = false;
  bool _unfinishedDownloadSeen = false;
  bool _restoreActivityBaseline = false;
  bool _restoringVerticalPosition = false;
  int _verticalRestoreRevision = 0;
  bool _dragStartedAtStart = false;
  bool _dragStartedAtEnd = false;
  double _edgeDrag = 0;
  double _verticalOverscroll = 0;

  AppSettings get _readerSettings =>
      ref.read(readerSettingsForProvider(widget.data.media.id));
  ReaderSettingsController get _readerController =>
      ref.read(readerSettingsControllerProvider(widget.data.media.id));
  ReaderColorFilter get _colorFilter => _filterFrom(_readerSettings);

  int get _lastVisiblePage => _pagedLayout?.lastVisiblePage(_index) ?? _index;

  /// Decode scans once at twice the display width instead of their full source
  /// size. Zooming then magnifies the pixels that are already decoded; it must
  /// never swap the image provider and make the page look like it reloaded.
  /// Original size is the exception: it exists to inspect the whole scan, so
  /// it keeps the full resolution. Returns null for that full decode.
  int? get _decodeWidth {
    final settings = _readerSettings;
    if (settings.readerMode == ReaderMode.paged &&
        settings.readerFit == ReaderFit.original) {
      return null;
    }
    final media = MediaQuery.maybeOf(context);
    if (media == null) return null;
    return (media.size.width * media.devicePixelRatio * 2)
        .round()
        .clamp(720, 1600)
        .toInt();
  }

  int get _chapterTotal {
    final expected = widget.data.totalPages ?? _resources.length;
    return expected > _resources.length ? expected : _resources.length;
  }

  bool get _atAvailableEnd =>
      _resources.isNotEmpty && _lastVisiblePage >= _resources.length - 1;
  bool get _atEnd =>
      !widget.data.partial &&
      _resources.isNotEmpty &&
      _lastVisiblePage >= _chapterTotal - 1;

  /// Pages already handed to the cache this session. Preloading the same page
  /// on every scroll tick would be wasted work.
  final Set<int> _prefetched = <int>{};

  /// The next chapter whose opening pages were warmed. Kept separate from the
  /// page set because it belongs to another unit.
  String? _prefetchedNextUnit;

  void _toggleChrome() {
    if (_gestureInputLocked || ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    setState(() => _showChrome = !_showChrome);
  }

  /// Reading can dismiss the menu once, but can never bring it back. Only a
  /// confirmed tap or the menu shortcut changes hidden chrome to visible.
  void _hideChromeForReading() {
    if (!mounted || !_showChrome || _scrubbing) return;
    if (ModalRoute.of(context)?.isCurrent == false) return;
    setState(() => _showChrome = false);
  }

  void _onViewportInputLock(bool locked) {
    _gestureInputLocked = locked;
    if (locked) {
      _stopAutoScroll();
      _navigationGestureRevision++;
      _edgeDrag = 0;
      _verticalOverscroll = 0;
      if (_pagedLayout != null && (_pagedController?.hasClients ?? false)) {
        _pagedController!.jumpToPage(_pagedLayout!.viewForPage(_index));
      }
    } else if (_manualZoomScroll) {
      _freezeVerticalPositions = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onVerticalPositions();
      });
    }
  }

  void _onViewportZoom(ReaderZoomChange change) {
    _readerZoomed = change.scale > 1.001;
    if (!change.preserveContent) {
      _zoomRevision++;
      _zoomAnchor = null;
      _freezeVerticalPositions = false;
      return;
    }
    if (_readerSettings.readerMode != ReaderMode.vertical) return;
    // A zoom that begins after the previous gesture ended is a new gesture, so
    // the point under its fingers is measured again rather than carried over.
    if (_zoomGestureEnded) _zoomAnchor = null;
    _freezeVerticalPositions = true;
    _zoomGestureEnded = false;
    final height = _viewportKey.currentState?.viewportSize.height ?? 0;
    if (height <= 0) return;
    final before = (change.beforeFocal.dy / height).clamp(0.0, 1.0);
    final after = (change.focalPoint.dy / height).clamp(0.0, 1.0).toDouble();
    if (_zoomAnchor == null) {
      final positions = _verticalPositions.itemPositions.value.toList();
      if (positions.isEmpty) return;
      positions.sort((a, b) => a.index.compareTo(b.index));
      final item = positions.firstWhere(
        (position) =>
            position.itemLeadingEdge <= before &&
            position.itemTrailingEdge > before,
        orElse: () => positions.first,
      );
      final extent = item.itemTrailingEdge - item.itemLeadingEdge;
      if (extent <= 0) return;
      _zoomAnchor = _VerticalZoomAnchor(
        item.index,
        ((before - item.itemLeadingEdge) / extent).clamp(0.0, 1.0).toDouble(),
        after,
      );
    } else {
      _zoomAnchor!.focal = after;
    }
    _scheduleZoomCorrection();
  }

  void _scheduleZoomCorrection() {
    if (_zoomAnchor == null) return;
    _zoomCorrectionQueued = true;
    if (_zoomCorrectionRunning) return;
    unawaited(_runZoomCorrections());
  }

  /// Corrections never overlap. Each one measures the list only after the
  /// frames that applied the previous correction have been laid out and
  /// published. Measuring earlier corrects against a stale layout, so the list
  /// overshoots and swings back and forth on every frame.
  Future<void> _runZoomCorrections() async {
    _zoomCorrectionRunning = true;
    try {
      while (_zoomCorrectionQueued && mounted) {
        _zoomCorrectionQueued = false;
        await WidgetsBinding.instance.endOfFrame;
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        await _correctZoomAnchor(_zoomRevision);
      }
    } finally {
      _zoomCorrectionRunning = false;
    }
  }

  Future<void> _correctZoomAnchor(int revision) async {
    final anchor = _zoomAnchor;
    final viewport = _viewportKey.currentState;
    if (anchor != null && viewport != null && _verticalController.isAttached) {
      final positions = _verticalPositions.itemPositions.value.where(
        (position) => position.index == anchor.index,
      );
      if (positions.isNotEmpty) {
        final item = positions.first;
        final current =
            item.itemLeadingEdge +
            anchor.fraction * (item.itemTrailingEdge - item.itemLeadingEdge);
        final correction =
            (current - anchor.focal) *
            viewport.viewportSize.height /
            viewport.scale;
        if (correction.abs() > 0.5) {
          try {
            await _verticalOffsetController.animateScroll(
              offset: correction,
              duration: const Duration(milliseconds: 1),
            );
          } catch (_) {
            // A chapter or layout may have been replaced while its positions arrived.
          }
        }
      }
    }
    if (!mounted || revision != _zoomRevision) return;
    // Once the gesture is over and no correction is still queued, the anchor
    // has done its job on every path, including a missing item. Drop it so a
    // stale anchor cannot pull the list back to an old item at the next zoom.
    if (_zoomGestureEnded && !_zoomCorrectionQueued) _zoomAnchor = null;
  }

  void _onViewportZoomEnd() {
    _zoomGestureEnded = true;
    _scheduleZoomCorrection();
    if (_manualZoomScroll && !_gestureInputLocked) {
      _freezeVerticalPositions = false;
      _manualZoomScroll = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onVerticalPositions();
      });
    }
  }

  void _onManualViewportScroll(double offset) {
    if (_readerSettings.readerMode != ReaderMode.vertical) return;
    _zoomRevision++;
    _zoomAnchor = null;
    _manualZoomScroll = true;
    _pendingManualScroll += offset;
    if (_manualScrollScheduled) return;
    _manualScrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _manualScrollScheduled = false;
      if (!mounted || !_verticalController.isAttached) return;
      final scroll = _pendingManualScroll;
      _pendingManualScroll = 0;
      unawaited(() async {
        try {
          await _verticalOffsetController.animateScroll(
            offset: scroll,
            duration: const Duration(milliseconds: 1),
          );
        } catch (_) {
          // The reader can be closed between the pointer and this frame.
        }
        if (!mounted || _gestureInputLocked) return;
        _freezeVerticalPositions = false;
        _onVerticalPositions();
      }());
    });
  }

  void _updateFilter(ReaderColorFilter filter) {
    _readerController.setReaderFilter(
      mode: filter.mode.name,
      brightness: filter.customBrightnessOffset,
    );
  }

  void _showColorFilterSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(BestRadius.sheet),
        ),
      ),
      builder: (context) => ReaderColorFilterSheet(
        filter: _colorFilter,
        onChanged: _updateFilter,
      ),
    );
  }

  void _showReaderSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(BestRadius.sheet),
        ),
      ),
      builder: (context) => ReaderSettingsSheet(
        media: widget.data.media,
        unit: widget.data.unit,
        onOpenChapters: _showChaptersSheet,
        onOpenColorFilter: _showColorFilterSheet,
        onOpenPageGrid: () => _showPageGrid(),
        onOpenBookmarks: _showBookmarks,
      ),
    );
  }

  void _showPageGrid({bool bookmarksOnly = false}) {
    if (_resources.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(BestRadius.sheet),
        ),
      ),
      builder: (sheetContext) => ReaderPageGridSheet(
        resources: _resources,
        unitId: widget.data.unit.id,
        current: _index,
        totalPages: widget.data.partial && widget.data.totalPages == null
            ? 0
            : _chapterTotal,
        initialBookmarksOnly: bookmarksOnly,
        onSelected: (index) {
          Navigator.of(sheetContext).pop();
          _jumpToPage(index);
        },
      ),
    );
  }

  void _showBookmarks() => _showPageGrid(bookmarksOnly: true);

  void _jumpToPage(int index) {
    _stopAutoScroll();
    final total = _resources.length;
    if (total == 0) return;
    _viewportKey.currentState?.reset();
    final target = index.clamp(0, total - 1);
    if (target != _index) setState(() => _index = target);
    if (_readerSettings.readerMode == ReaderMode.vertical) {
      if (_verticalController.isAttached) {
        _verticalController.jumpTo(index: target);
      }
    } else if (_pagedController?.hasClients ?? false) {
      _pagedController!.jumpToPage(_pagedLayout!.viewForPage(target));
    }
    _markRead(_lastVisiblePage);
    _saveNow();
    _precacheAround(_lastVisiblePage);
  }

  void _toggleBookmark() {
    if (_resources.isEmpty) return;
    final l10n = AppLocalizations.of(context);
    final bookmarks = ref.read(readerBookmarksProvider);
    final wasMarked = (bookmarks[widget.data.unit.id] ?? const <int>[])
        .contains(_index);
    ref
        .read(readerBookmarksProvider.notifier)
        .toggle(widget.data.unit.id, _index);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(milliseconds: 1300),
          content: Text(
            wasMarked
                ? l10n.readerBookmarkRemoved
                : l10n.readerBookmarkAdded(_index + 1),
          ),
        ),
      );
  }

  void _toggleMode() {
    _stopAutoScroll();
    final current = _readerSettings.readerMode;
    _readerController.setReaderMode(
      current == ReaderMode.paged ? ReaderMode.vertical : ReaderMode.paged,
    );
    // The new layout keeps the same scan bytes, but its neighbours may never
    // have been decoded. Warm them now so the first scrolls after a switch do
    // not each wait for a fresh decode.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _precacheAround(_index);
    });
    unawaited(HapticFeedback.selectionClick());
  }

  String? get _autoScrollSpeedLabel => autoScrollSpeedLabel(_autoScrollSpeed);

  /// Long-pressing the auto-scroll button steps through 1x, 2x, 3x and 0.5x.
  void _cycleAutoScrollSpeed() {
    final next = nextAutoScrollSpeed(_autoScrollSpeed);
    setState(() => _autoScrollSpeed = next);
    ref.read(readerAutoScrollSpeedProvider.notifier).setSpeed(next);
    unawaited(HapticFeedback.selectionClick());
  }

  /// Continuous mode can crawl at reading speed, one line at a time. It is a
  /// deliberate mode: any drag, pinch, page jump or chapter change gives the
  /// reader their hands back instead of fighting an invisible motor.
  void _toggleAutoScroll() {
    if (_autoScrolling) {
      _stopAutoScroll();
      return;
    }
    if (_resources.isEmpty ||
        _readerSettings.readerMode != ReaderMode.vertical) {
      return;
    }
    _autoScrollTimer?.cancel();
    setState(() => _autoScrolling = true);
    unawaited(HapticFeedback.selectionClick());
    _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 50), (
      timer,
    ) {
      if (!mounted || !_autoScrolling) {
        timer.cancel();
        return;
      }
      if (!_verticalController.isAttached) return;
      unawaited(() async {
        try {
          await _verticalOffsetController.animateScroll(
            offset: 2 * _autoScrollSpeed,
            duration: const Duration(milliseconds: 52),
          );
        } catch (_) {
          // A chapter or layout can replace the list while the timer fires.
        }
      }());
    });
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    if (!_autoScrolling) return;
    _autoScrolling = false;
    if (!mounted) return;
    // Scroll notifications can arrive during layout; repaint the pause icon on
    // the next frame without marking the tree dirty mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_autoScrolling) setState(() {});
    });
  }

  void _showChaptersSheet() {
    final units = widget.data.units;
    if (units.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(BestRadius.sheet),
        ),
      ),
      builder: (sheetContext) => ChapterListSheet(
        units: units,
        currentUnitId: widget.data.unit.id,
        workTitle: widget.data.media.displayTitle,
        onSelected: (unit) {
          Navigator.of(sheetContext).pop();
          _openUnit(unit);
        },
      ),
    );
  }

  /// Replaces the route so a chapter does not stack dozens of readers on the
  /// back stack, and saves the current page before the old state is disposed.
  void _openUnit(MediaUnit unit, {bool startAtEnd = false}) {
    if (!mounted || _openingUnit) return;
    if (ModalRoute.of(context)?.isCurrent == false) return;
    _stopAutoScroll();
    _openingUnit = true;
    _saveNow();
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      router.pushReplacement(
        Routes.reader(
          sourceId: widget.data.media.ref.sourceId,
          url: widget.data.media.ref.url,
          unitUrl: unit.url,
          atEnd: startAtEnd,
        ),
      );
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ReaderScreen(
          sourceId: widget.data.media.ref.sourceId,
          url: widget.data.media.ref.url,
          unitUrl: unit.url,
          startAtEnd: startAtEnd,
        ),
      ),
    );
  }

  int get _unitIndex =>
      widget.data.units.indexWhere((unit) => unit.id == widget.data.unit.id);

  MediaUnit? get _previousUnit {
    final index = _unitIndex;
    if (index <= 0) return null;
    return widget.data.units[index - 1];
  }

  MediaUnit? get _nextUnit {
    final index = _unitIndex;
    if (index < 0 || index >= widget.data.units.length - 1) return null;
    return widget.data.units[index + 1];
  }

  /// The chapter the strip's end card offers. A partly offline chapter offers
  /// none, the rule the control bar and auto-advance already follow, so the end
  /// of the loaded pages cannot skip the missing ones.
  MediaUnit? get _stripEndUnit => widget.data.partial ? null : _nextUnit;

  void _openPreviousUnit() {
    final previous = _previousUnit;
    if (previous == null) return;
    _openUnit(previous, startAtEnd: true);
  }

  void _openNextUnit() {
    if (widget.data.partial) {
      _showPartialWarning();
      return;
    }
    final next = _nextUnit;
    if (next == null) return;
    _openUnit(next);
  }

  void _showPartialWarning() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).readerPartialOffline),
      ),
    );
  }

  /// The outer thirds turn a page; the middle third toggles the controls. In a
  /// right-to-left chapter the forward zone is the left side, matching the way
  /// the pages themselves move.
  void _handleTap(Offset position, double width) {
    if (_gestureInputLocked || ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    final settings = _readerSettings;
    if (settings.readerMode == ReaderMode.vertical ||
        !settings.readerTapZones) {
      _toggleChrome();
      return;
    }
    final dx = position.dx;
    // Enlarged scans are inspected by panning. Edge taps cannot turn the page
    // underneath them; the centre remains the explicit menu target.
    if (_readerZoomed) {
      final zones = settings.readerTapZoneSize;
      if (dx >= width * zones.middleStart && dx <= width * zones.middleEnd) {
        _toggleChrome();
      }
      return;
    }
    final zones = settings.readerTapZoneSize;
    if (dx < width * zones.middleStart) {
      _turnPage(settings.readerDirection.isRtl ? 1 : -1);
    } else if (dx > width * zones.middleEnd) {
      _turnPage(settings.readerDirection.isRtl ? -1 : 1);
    } else {
      _toggleChrome();
    }
  }

  void _turnPage(int delta) {
    if (_readerZoomed || _gestureInputLocked) return;
    final layout = _pagedLayout;
    if (layout == null || layout.viewCount == 0 || _openingUnit) return;
    final current = layout.viewForPage(_index);
    final target = (current + delta).clamp(0, layout.viewCount - 1);
    if (target == current) {
      // At the edge, the same forward gesture continues the story instead of
      // dead-ending on a static page. Backward starts the previous chapter on
      // its last page, so the reading direction is preserved.
      if (delta > 0) {
        _openNextUnit();
      } else {
        _openPreviousUnit();
      }
      return;
    }
    unawaited(HapticFeedback.selectionClick());
    _pagedController?.animateToPage(
      target,
      duration: BestMotion.fast,
      curve: BestMotion.curve,
    );
    _hideChromeForReading();
  }

  Future<void> _setAwake(bool enabled) async {
    if (_awake == enabled) return;
    _awake = enabled;
    try {
      await WakelockPlus.toggle(enable: enabled);
    } catch (_) {
      // A platform without the plugin still reads; only the screen sleeps.
    }
  }

  ReaderColorFilter _filterFrom(AppSettings settings) {
    final mode = ReaderColorFilterMode.values.firstWhere(
      (candidate) => candidate.name == settings.readerFilterMode,
      orElse: () => ReaderColorFilterMode.none,
    );
    return ReaderColorFilter(
      mode: mode,
      customBrightnessOffset: settings.readerBrightness.clamp(-75, 0).toInt(),
    );
  }

  /// Warm the disk cache and the decoded image cache around the current page.
  ///
  /// Ordinary image URLs and extension pages are both written to
  /// [PageImageCache]. Extension pages use the host's signed response through
  /// [PageImageCache.loadWith], so the warm-up never issues a second,
  /// differently-signed request. Bytes are then decoded at the same stable
  /// width the page will use, so the next swipe or mode switch paints at once.
  void _precacheAround(int index) {
    if (!mounted) return;
    if (!_readerSettings.readerPreload) return;
    final total = _resources.length;
    if (total == 0) return;
    final extension = extensionSourceIdOf(widget.data.media.ref.sourceId);
    final host = extension == null ? null : ref.read(extensionHostProvider);
    final cache = ref.read(pageImageCacheProvider);
    final cacheWidth = _decodeWidth;
    for (final offset in const <int>[1, 2, 3, -1, -2]) {
      final target = index + offset;
      if (target < 0 || target >= total) continue;
      if (!_prefetched.add(target)) continue;
      final resource = _resources[target];
      try {
        if (resource is ImageResource) {
          unawaited(() async {
            try {
              final bytes = extension == null
                  ? await cache.load(resource)
                  : await cache.loadWith(
                      resource,
                      () => host!.imageBytes(
                        extension,
                        resource.url,
                        headers: resource.headers,
                      ),
                    );
              if (!mounted || bytes == null || bytes.isEmpty) return;
              ImageProvider<Object> provider = MemoryImage(bytes);
              if (cacheWidth != null) {
                provider = ResizeImage(provider, width: cacheWidth);
              }
              await precacheImage(provider, context, onError: (_, __) {});
            } catch (_) {
              // The page itself will retry; warming the cache is best effort.
            }
          }());
        } else if (resource is FileResource) {
          ImageProvider<Object> provider = FileImage(File(resource.path));
          if (cacheWidth != null) {
            provider = ResizeImage(provider, width: cacheWidth);
          }
          unawaited(precacheImage(provider, context, onError: (_, __) {}));
        }
      } catch (_) {
        // A failed warm-up is never a reading failure; the page reports its own
        // error and offers a retry.
      }
    }
  }

  void _stepVertical(int delta) {
    if (_gestureInputLocked) return;
    final total = _resources.length;
    if (total == 0) return;
    final target = (_index + delta).clamp(0, total - 1);
    if (target == _index) {
      if (delta > 0) {
        _openNextUnit();
      } else {
        _openPreviousUnit();
      }
      return;
    }
    if (_verticalController.isAttached) {
      _hideChromeForReading();
      _verticalController.scrollTo(
        index: target,
        duration: BestMotion.fast,
        curve: BestMotion.curve,
      );
    }
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    // A sheet, dialog or the next chapter route owns the keyboard while it is
    // on top; otherwise an arrow pressed in chapter search would also flip the
    // hidden page behind it.
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return KeyEventResult.ignored;
    final settings = _readerSettings;
    final vertical = settings.readerMode == ReaderMode.vertical;
    final rtl = settings.readerDirection.isRtl;
    final key = event.logicalKey;

    if (_readerZoomed &&
        (key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowRight ||
            key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowDown ||
            key == LogicalKeyboardKey.pageUp ||
            key == LogicalKeyboardKey.pageDown ||
            key == LogicalKeyboardKey.space)) {
      final size = MediaQuery.sizeOf(context);
      final offset = switch (key) {
        LogicalKeyboardKey.arrowLeft => Offset(size.width * 0.6, 0),
        LogicalKeyboardKey.arrowRight => Offset(-size.width * 0.6, 0),
        LogicalKeyboardKey.arrowUp ||
        LogicalKeyboardKey.pageUp => Offset(0, size.height * 0.6),
        _ => Offset(0, -size.height * 0.6),
      };
      _viewportKey.currentState?.panBy(offset);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowLeft) {
      vertical ? _stepVertical(-1) : _turnPage(rtl ? 1 : -1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      vertical ? _stepVertical(1) : _turnPage(rtl ? -1 : 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.pageDown ||
        key == LogicalKeyboardKey.space) {
      vertical ? _stepVertical(1) : _turnPage(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.pageUp) {
      vertical ? _stepVertical(-1) : _turnPage(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyB) {
      _toggleBookmark();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyG) {
      _showPageGrid();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyM) {
      _toggleMode();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyS) {
      _showReaderSettings();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyF) {
      _toggleChrome();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void initState() {
    super.initState();
    _repository = ref.read(repositoryProvider);
    final settings = _readerSettings;
    final total = _resources.length;
    final saved = widget.data.progress?.position;
    if (total == 0) {
      _index = 0;
      // An empty/error reading surface still needs a visible way back.
      _showChrome = true;
    } else if (widget.fromStart) {
      _index = 0;
    } else if (widget.startAtEnd) {
      _index = total - 1;
    } else if (saved != null) {
      _index = saved.clamp(0, total - 1);
    } else {
      _index = 0;
    }
    _furthest = _index;
    _verticalPositions.itemPositions.addListener(_onVerticalPositions);
    WidgetsBinding.instance.addObserver(this);
    _startReadingClock();
    _openReaders++;
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
    if (settings.readerKeepAwake) {
      unawaited(_setAwake(true));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _precacheAround(_index);
        _maybePrefetchNextUnit(_index);
      }
    });
  }

  @override
  void didUpdateWidget(_ReaderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final total = _resources.length;
    if (total == 0) {
      _index = 0;
      _restoreActivityBaseline = false;
      _restoringVerticalPosition = false;
      _verticalRestoreRevision++;
    } else if ((oldWidget.data.partial && !widget.data.partial) ||
        _restoringVerticalPosition) {
      _index = (widget.data.progress?.position ?? _index).clamp(0, total - 1);
      _furthest = _furthest < _index ? _index : _furthest;
      _restoreActivityBaseline = true;
      // A longer item list retains its old offset. Ignore stale prefix
      // positions until the saved-page jump has been laid out.
      if (_readerSettings.readerMode == ReaderMode.vertical) {
        _restoringVerticalPosition = true;
        final revision = ++_verticalRestoreRevision;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || revision != _verticalRestoreRevision) return;
          if (_verticalController.isAttached) {
            _verticalController.jumpTo(index: _index);
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || revision != _verticalRestoreRevision) return;
            _restoringVerticalPosition = false;
            _onVerticalPositions();
          });
          WidgetsBinding.instance.scheduleFrame();
        });
      } else {
        _restoringVerticalPosition = false;
        _verticalRestoreRevision++;
      }
    } else {
      _index = _index.clamp(0, total - 1);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startReadingClock();
      return;
    }
    // A phone in a pocket is not reading time. Flush before the process can be
    // suspended so the last minute is not lost, then stop the clock.
    _flushReadingTime();
    _readingTimer?.cancel();
    _readingSince = null;
  }

  @override
  void didHaveMemoryPressure() {
    // Flutter already drops its decoded-image cache; drop our byte cache too
    // so a low-memory device keeps the reader alive instead of being killed.
    ref.read(pageImageCacheProvider).trimMemory();
    PaintingBinding.instance.imageCache.clear();
  }

  void _startReadingClock() {
    if (_readingTimer != null || !mounted) return;
    if (WidgetsBinding.instance.lifecycleState != null &&
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    _readingSince = DateTime.now();
    _readingTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _flushReadingTime(),
    );
  }

  void _flushReadingTime() {
    final since = _readingSince;
    if (since == null) return;
    final now = DateTime.now();
    _readingSince = now;
    _pendingReadingSeconds += now.difference(since).inSeconds;
    if (_pendingReadingSeconds < 60) return;
    final minutes = _pendingReadingSeconds ~/ 60;
    _pendingReadingSeconds -= minutes * 60;
    unawaited(_repository.recordActivity(minutes: minutes));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _readingTimer?.cancel();
    _flushReadingTime();
    _verticalProgress.dispose();
    _autoScrollTimer?.cancel();
    _saveTimer?.cancel();
    _saveNow();
    _verticalPositions.itemPositions.removeListener(_onVerticalPositions);
    _pagedController?.dispose();
    _openReaders = _openReaders > 0 ? _openReaders - 1 : 0;
    if (_openReaders == 0) {
      unawaited(_setAwake(false));
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    }
    super.dispose();
  }

  void _onPageChanged(int view, ReaderPageLayout layout) {
    if (!mounted || !identical(layout, _pagedLayout)) return;
    final pages = layout.pagesForView(view);
    if (pages.isEmpty) return;
    // A jump or a reflow keeps the exact source page selected, including the
    // second scan of a pair. Only a swipe into a different pair changes it.
    final index = pages.contains(_index) ? _index : pages.first;
    if (index == _index) return;
    _viewportKey.currentState?.reset();
    setState(() => _index = index);
    _markRead(pages.last);
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 320), _saveNow);
    _precacheAround(pages.last);
    _maybePrefetchNextUnit(pages.last);
  }

  /// Continuous mode has no page callback, so the item under the top of the
  /// viewport is the current page. Its top half is the threshold: a page is
  /// reached when the reader can actually see it, not when its first pixel
  /// enters from below.
  void _onVerticalPositions() {
    if (!mounted ||
        _restoringVerticalPosition ||
        _freezeVerticalPositions ||
        _gestureInputLocked ||
        ModalRoute.of(context)?.isCurrent == false ||
        _readerSettings.readerMode != ReaderMode.vertical) {
      return;
    }
    final total = _resources.length;
    if (total == 0) return;
    final positions = _verticalPositions.itemPositions.value
        .where((position) => position.itemTrailingEdge > 0)
        .toList();
    if (positions.isEmpty) return;
    positions.sort((a, b) => a.index.compareTo(b.index));
    final current = positions.firstWhere(
      (position) =>
          position.itemLeadingEdge <= 0.5 && position.itemTrailingEdge > 0.5,
      orElse: () => positions.first,
    );
    // Progress follows the strip itself: the page at the reading line plus how
    // far that page has been crossed, so a tall webtoon page moves the bar.
    final lastVisible = positions.last;
    final atStripEnd = isAtVerticalStripEnd(
      lastIndex: lastVisible.index,
      itemCount: total + (_stripEndUnit == null ? 0 : 1),
      trailing: lastVisible.itemTrailingEdge,
    );
    // A partial chapter's loaded end is not its end, so it never reads complete.
    _verticalProgress.value = verticalStripProgress(
      pageCount: total,
      index: current.index,
      leading: current.itemLeadingEdge,
      trailing: current.itemTrailingEdge,
      atStripEnd: atStripEnd && !widget.data.partial,
    );
    final index = current.index.clamp(0, total - 1);
    // Auto-scroll ends at the bottom of the strip. Stopping once the reading
    // line reached the last page cut off a tall final page.
    if (_autoScrolling && atStripEnd) _stopAutoScroll();
    if (index == _index) return;
    setState(() => _index = index);
    _markRead(index);
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 320), _saveNow);
    _precacheAround(index);
    _maybePrefetchNextUnit(index);
  }

  /// Warm the first pages of the next chapter when the reader is close to its
  /// end, so auto-advance and the end-card tap do not open on a spinner. It is
  /// best effort: a failed request leaves the normal chapter load untouched.
  void _maybePrefetchNextUnit(int page) {
    if (!mounted ||
        !_readerSettings.readerPreload ||
        widget.data.partial ||
        widget.data.offline) {
      return;
    }
    final total = _chapterTotal;
    if (total <= 0 || page < total - 3) return;
    final next = _nextUnit;
    if (next == null || _prefetchedNextUnit == next.id) return;
    _prefetchedNextUnit = next.id;
    unawaited(() async {
      try {
        final key = (
          sourceId: widget.data.media.ref.sourceId,
          url: widget.data.media.ref.url,
          unitUrl: next.url,
        );
        final data = await ref.read(readerProvider(key).future);
        if (!mounted) return;
        final extension = extensionSourceIdOf(widget.data.media.ref.sourceId);
        final host = extension == null ? null : ref.read(extensionHostProvider);
        final cache = ref.read(pageImageCacheProvider);
        final cacheWidth = _decodeWidth;
        for (final resource in data.resources.take(2)) {
          if (!mounted) return;
          if (resource is ImageResource) {
            final bytes = extension == null
                ? await cache.load(resource)
                : await cache.loadWith(
                    resource,
                    () => host!.imageBytes(
                      extension,
                      resource.url,
                      headers: resource.headers,
                    ),
                  );
            if (!mounted || bytes == null || bytes.isEmpty) continue;
            ImageProvider<Object> provider = MemoryImage(bytes);
            if (cacheWidth != null) {
              provider = ResizeImage(provider, width: cacheWidth);
            }
            await precacheImage(provider, context, onError: (_, __) {});
          } else if (resource is FileResource) {
            ImageProvider<Object> provider = FileImage(File(resource.path));
            if (cacheWidth != null) {
              provider = ResizeImage(provider, width: cacheWidth);
            }
            await precacheImage(provider, context, onError: (_, __) {});
          }
        }
      } catch (_) {
        // The next chapter will load normally when the reader asks for it.
        _prefetchedNextUnit = null;
      }
    }());
  }

  void _markRead(int index) {
    if (index <= _furthest) return;
    final fresh = index - _furthest;
    _furthest = index;
    unawaited(_repository.recordActivity(pages: fresh));
  }

  void _saveNow() {
    final total = _resources.length;
    if (total == 0) return;
    final saved = widget.data.progress?.position ?? 0;
    final position = widget.data.partial && saved > _index ? saved : _index;
    unawaited(
      _repository.saveProgress(
        UnitProgress(
          unitId: widget.data.unit.id,
          position: position,
          total: widget.data.partial && widget.data.totalPages == null
              ? (widget.data.progress?.total ?? 0)
              : _chapterTotal,
          completed: _atEnd,
          started: true,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      ),
    );
  }

  Color _backgroundFor(ReaderBackground background) {
    return switch (background) {
      ReaderBackground.black => Colors.black,
      ReaderBackground.charcoal => const Color(0xFF1C1C1E),
      ReaderBackground.sepia => const Color(0xFFF2E6D0),
      ReaderBackground.white => Colors.white,
    };
  }

  void _configurePagedLayout(AppSettings settings, Size viewport) {
    if (_lastMode != null && _lastMode != settings.readerMode) {
      // A new scroll view is laid out before it knows which page is under the
      // reader's eyes. Freeze position callbacks and place the saved page
      // explicitly, so a layout switch can never report page 2 or 3 as the
      // starting page or persist a phantom scroll position.
      _verticalRestoreRevision++;
      if (settings.readerMode == ReaderMode.vertical) {
        _restoringVerticalPosition = true;
        final revision = _verticalRestoreRevision;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || revision != _verticalRestoreRevision) return;
          if (_verticalController.isAttached) {
            _verticalController.jumpTo(index: _index);
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || revision != _verticalRestoreRevision) return;
            _restoringVerticalPosition = false;
            _onVerticalPositions();
          });
          WidgetsBinding.instance.scheduleFrame();
        });
      } else {
        _restoringVerticalPosition = false;
      }
    }
    _lastMode = settings.readerMode;
    final next =
        settings.readerMode == ReaderMode.paged && _resources.isNotEmpty
        ? ReaderPageLayout(
            pageCount: _resources.length,
            doublePage: settings.readerPreferences.usesSpreads(
              width: viewport.width,
              height: viewport.height,
            ),
            coverAlone: settings.readerCoverAlone,
          )
        : null;
    if (_restoreActivityBaseline) {
      // The restored scan can land in a pair. Its visible neighbour belongs to
      // the restoration baseline too, not to a new reading gesture.
      final restoredLastPage = next?.lastVisiblePage(_index) ?? _index;
      if (restoredLastPage > _furthest) {
        _furthest = restoredLastPage;
      }
      _restoreActivityBaseline = false;
    }
    if (next == _pagedLayout &&
        settings.readerDirection == _pagedDirection &&
        (next == null || _pagedController != null)) {
      return;
    }

    final oldController = _pagedController;
    _pagedLayout = next;
    _pagedDirection = settings.readerDirection;
    _pagedController = next == null
        ? null
        : PageController(
            initialPage: next.viewForPage(_index),
            keepPage: false,
          );
    _edgeDrag = 0;
    _dragStartedAtStart = false;
    _dragStartedAtEnd = false;

    // A controller's pixels refer to viewports, not source scans. Recreate it
    // when the grouping changes and detach the old view before disposing it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      oldController?.dispose();
      if (!mounted || next == null || !identical(next, _pagedLayout)) return;
      _markRead(_lastVisiblePage);
      _precacheAround(_lastVisiblePage);
    });
  }

  /// Vertical mode has no page boundaries, so "continue to the next chapter"
  /// is a deliberate pull past the end of the last page. At that point — and
  /// only when auto-advance is on — the next chapter opens by itself.
  bool _handleVerticalScroll(ScrollNotification notification) {
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _stopAutoScroll();
      _freezeVerticalPositions = false;
      _hideChromeForReading();
    }
    if (_readerZoomed || _gestureInputLocked) {
      _verticalOverscroll = 0;
      return false;
    }
    final metrics = notification.metrics;
    if (notification is ScrollStartNotification) {
      _verticalOverscroll = 0;
    } else if (notification is OverscrollNotification &&
        notification.overscroll > 0 &&
        metrics.extentAfter <= 0.5) {
      _verticalOverscroll += notification.overscroll;
    } else if (notification is ScrollEndNotification) {
      if (_autoScrolling && metrics.extentAfter <= 0.5) _stopAutoScroll();
      final go = _verticalOverscroll >= 72;
      _verticalOverscroll = 0;
      if (go &&
          _readerSettings.readerAutoAdvance &&
          !widget.data.partial &&
          _nextUnit != null) {
        final revision = _navigationGestureRevision;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              !_openingUnit &&
              !_readerZoomed &&
              !_gestureInputLocked &&
              revision == _navigationGestureRevision) {
            _openNextUnit();
          }
        });
      }
    }
    return false;
  }

  bool _handlePagedScroll(ScrollNotification notification) {
    if (_readerZoomed || _gestureInputLocked) {
      _edgeDrag = 0;
      return false;
    }
    if (notification.depth != 0 ||
        notification.metrics.axis != Axis.horizontal) {
      return false;
    }
    final metrics = notification.metrics;
    if (notification is ScrollStartNotification) {
      if (notification.dragDetails != null) _hideChromeForReading();
      _edgeDrag = 0;
      _dragStartedAtStart = metrics.pixels <= metrics.minScrollExtent + 0.5;
      _dragStartedAtEnd = metrics.pixels >= metrics.maxScrollExtent - 0.5;
    } else if (notification is OverscrollNotification &&
        notification.dragDetails != null) {
      if ((notification.overscroll > 0 && _dragStartedAtEnd) ||
          (notification.overscroll < 0 && _dragStartedAtStart)) {
        _edgeDrag += notification.overscroll;
      }
    } else if (notification is ScrollEndNotification) {
      final delta = _edgeDrag >= 88 ? 1 : (_edgeDrag <= -88 ? -1 : 0);
      final layout = _pagedLayout;
      _edgeDrag = 0;
      // Reaching the final page mid-swipe is not permission to skip chapters.
      // The gesture must start at the boundary and deliberately go beyond it.
      if (delta != 0) {
        final revision = _navigationGestureRevision;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted ||
              _openingUnit ||
              _readerZoomed ||
              _gestureInputLocked ||
              revision != _navigationGestureRevision ||
              !identical(layout, _pagedLayout)) {
            return;
          }
          delta > 0 ? _openNextUnit() : _openPreviousUnit();
        });
      }
    }
    return false;
  }

  Widget _buildPagedView(
    AppSettings settings,
    ReaderViewportGeometry geometry,
  ) {
    final layout = _pagedLayout!;
    final interfaceDirection = Directionality.of(context);
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) => identical(layout, _pagedLayout)
          ? _handlePagedScroll(notification)
          : false,
      // PageView already reverses for the reading direction. Inheriting Arabic
      // UI direction here would reverse its drag axis a second time.
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: PageView.builder(
          key: ValueKey((layout, settings.readerDirection)),
          reverse: settings.readerDirection.isRtl,
          physics:
              settings.readerFit == ReaderFit.original ||
                  geometry.zoomed ||
                  geometry.inputLocked
              ? const NeverScrollableScrollPhysics()
              : const PageScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(
                    parent: ClampingScrollPhysics(),
                  ),
                ),
          controller: _pagedController,
          onPageChanged: (view) => _onPageChanged(view, layout),
          itemCount: layout.viewCount,
          itemBuilder: (context, view) {
            final pages = layout.pagesForView(view);
            final activePages = layout.pagesForView(layout.viewForPage(_index));
            Widget scan(int page) => _ResourcePage(
              key: ValueKey(page),
              unitId: widget.data.unit.id,
              resource: _resources[page],
              sourceId: widget.data.media.ref.sourceId,
              index: page,
              total: _chapterTotal,
              fit: settings.readerFit,
              colorFilter: _colorFilter,
              viewportScale: geometry.scale,
              inputLocked: geometry.inputLocked,
              zoomFocal: geometry.focalPoint,
              manualScroll: geometry.manualScroll,
              active: activePages.contains(page),
            );
            final content = pages.length == 1
                ? scan(pages.single)
                : Row(
                    // Reading direction, not interface language, orders the artwork.
                    textDirection: settings.readerDirection.isRtl
                        ? TextDirection.rtl
                        : TextDirection.ltr,
                    children: [
                      Expanded(child: scan(pages.first)),
                      const SizedBox(width: BestSpace.xs),
                      Expanded(child: scan(pages.last)),
                    ],
                  );
            return Directionality(
              textDirection: interfaceDirection,
              child: content,
            );
          },
        ),
      ),
    );
  }

  Widget _buildReadingViewport(AppSettings settings, Color background) {
    return ReaderGestureViewport(
      key: _viewportKey,
      contentKey: (
        settings.readerMode,
        settings.readerFit,
        settings.readerDirection,
        _pagedLayout,
      ),
      scrollableContent:
          settings.readerMode == ReaderMode.vertical ||
          settings.readerFit == ReaderFit.width,
      onTap: (position) =>
          _handleTap(position, MediaQuery.sizeOf(context).width),
      onReadingDrag: _hideChromeForReading,
      onInputLock: _onViewportInputLock,
      onZoom: _onViewportZoom,
      onZoomEnd: _onViewportZoomEnd,
      onManualScroll: _onManualViewportScroll,
      builder: (context, geometry) => ColoredBox(
        color: background,
        child: settings.readerMode == ReaderMode.vertical
            ? NotificationListener<ScrollNotification>(
                onNotification: _handleVerticalScroll,
                child: ScrollablePositionedList.builder(
                  itemScrollController: _verticalController,
                  scrollOffsetController: _verticalOffsetController,
                  itemPositionsListener: _verticalPositions,
                  initialScrollIndex: _index,
                  physics: geometry.inputLocked
                      ? const NeverScrollableScrollPhysics()
                      : const ClampingScrollPhysics(),
                  minCacheExtent: 1600,
                  itemCount:
                      _resources.length + (_stripEndUnit == null ? 0 : 1),
                  itemBuilder: (context, index) {
                    if (index >= _resources.length) {
                      final next = _stripEndUnit;
                      return _VerticalChapterEnd(
                        title: next == null
                            ? null
                            : unitTitle(AppLocalizations.of(context), next),
                        onOpen: _openNextUnit,
                      );
                    }
                    final page = _ResourcePage(
                      key: ValueKey(index),
                      unitId: widget.data.unit.id,
                      resource: _resources[index],
                      sourceId: widget.data.media.ref.sourceId,
                      index: index,
                      total: _chapterTotal,
                      continuous: true,
                      fit: settings.readerFit,
                      colorFilter: _colorFilter,
                      viewportScale: geometry.scale,
                      inputLocked: geometry.inputLocked,
                      zoomFocal: geometry.focalPoint,
                      manualScroll: geometry.manualScroll,
                    );
                    final gap = settings.readerWebtoonGap;
                    return gap <= 0
                        ? page
                        : Padding(
                            padding: EdgeInsets.only(bottom: gap.toDouble()),
                            child: page,
                          );
                  },
                ),
              )
            : _buildPagedView(settings, geometry),
      ),
    );
  }

  /// The HUD uses the compact mono form from the design language, not the
  /// sentence already shown by the controls. It also keeps the two labels from
  /// competing for the same widget-test finder while both are in the tree.
  String _hudPositionLabel() {
    final page = (_index + 1).clamp(1, _chapterTotal <= 0 ? 1 : _chapterTotal);
    return '$page / $_chapterTotal';
  }

  String _pagePositionLabel(AppLocalizations l10n, [int? index]) {
    final page = index ?? _index;
    if (widget.data.partial && widget.data.totalPages == null) {
      return l10n.readerSavedPage(page + 1);
    }
    final pages = _pagedLayout?.pagesForView(_pagedLayout!.viewForPage(page));
    if (pages != null && pages.length == 2) {
      return l10n.readerSpreadPageOf(
        pages.first + 1,
        pages.last + 1,
        _chapterTotal,
      );
    }
    return l10n.pageOf(page + 1, _chapterTotal);
  }

  Widget _buildTopBarTitle(
    AppLocalizations l10n,
    MediaUnit unit,
    bool rightToLeft,
  ) {
    final title = unitTitle(l10n, unit);
    final interfaceDirection = Directionality.of(context);
    return Row(
      children: [
        _chapterStep(
          forward: false,
          rightToLeft: rightToLeft,
          tooltip: l10n.readerPreviousChapter,
          onPressed: _previousUnit == null ? null : _openPreviousUnit,
        ),
        Expanded(
          child: Tooltip(
            message: l10n.chapters,
            child: InkWell(
              key: const ValueKey('reader-chapter-picker'),
              onTap: widget.data.units.isNotEmpty ? _showChaptersSheet : null,
              borderRadius: BorderRadius.circular(BestRadius.sm),
              child: Padding(
                padding: const EdgeInsetsDirectional.only(start: 2, end: 4),
                child: Row(
                  children: [
                    Container(
                      width: 2.5,
                      height: 24,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: BestColors.aurora,
                        ),
                        borderRadius: BorderRadius.all(Radius.circular(2)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textDirection: autoTextDirection(
                              title,
                              interfaceDirection,
                            ),
                            style: const TextStyle(
                              fontFamily: BestFonts.display,
                              color: Colors.white,
                              fontSize: 15,
                              height: 1.15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            widget.data.media.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textDirection: autoTextDirection(
                              widget.data.media.displayTitle,
                              interfaceDirection,
                            ),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.62),
                              fontSize: 10,
                              height: 1.1,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        _chapterStep(
          forward: true,
          rightToLeft: rightToLeft,
          tooltip: l10n.readerNextChapter,
          onPressed: _nextUnit == null || widget.data.partial
              ? null
              : _openNextUnit,
        ),
      ],
    );
  }

  Widget _chapterStep({
    required bool forward,
    required bool rightToLeft,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    final icon = rightToLeft
        ? (forward ? Icons.chevron_left_rounded : Icons.chevron_right_rounded)
        : (forward ? Icons.chevron_right_rounded : Icons.chevron_left_rounded);
    return IconButton(
      key: ValueKey(forward ? 'reader-top-next' : 'reader-top-previous'),
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      color: Colors.white.withValues(alpha: 0.88),
      disabledColor: Colors.white.withValues(alpha: 0.22),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(
        width: 30,
        height: BestLayout.minTouch,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final unit = widget.data.unit;
    final total = _resources.length;
    final settings = ref.watch(readerSettingsForProvider(widget.data.media.id));
    final direction = settings.readerDirection;
    final background = _backgroundFor(settings.readerBackground);
    final viewport = MediaQuery.sizeOf(context);
    _configurePagedLayout(settings, viewport);

    // Device wake policy is shared; work profiles only override presentation.
    ref.listen(settingsProvider.select((s) => s.readerKeepAwake), (_, next) {
      unawaited(_setAwake(next));
    });
    if (!widget.data.partial) _refreshingPartial = false;
    ref.listen(downloadForProvider(unit.id), (previous, next) {
      if (!mounted || !widget.data.partial || _refreshingPartial) return;
      if (next.value?.isFinished == false) _unfinishedDownloadSeen = true;
      if (_unfinishedDownloadSeen && next.value?.isFinished == true) {
        _refreshingPartial = true;
        _saveNow();
        ref.invalidate(
          readerProvider((
            sourceId: widget.data.media.ref.sourceId,
            url: widget.data.media.ref.url,
            unitUrl: unit.url,
          )),
        );
      }
    });

    return Focus(
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: Scaffold(
        backgroundColor: background,
        extendBodyBehindAppBar: true,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(BestLayout.minTouch),
          child: AnimatedOpacity(
            opacity: _showChrome ? 1.0 : 0.0,
            duration: BestMotion.normal,
            child: IgnorePointer(
              ignoring: !_showChrome,
              child: AppBar(
                toolbarHeight: BestLayout.minTouch,
                leadingWidth: BestLayout.minTouch,
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.white,
                elevation: 0,
                scrolledUnderElevation: 0,
                surfaceTintColor: Colors.transparent,
                titleSpacing: 0,
                flexibleSpace: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xF5060508),
                        Color(0xB8060508),
                        Color(0x00060508),
                      ],
                      stops: [0, 0.72, 1],
                    ),
                  ),
                ),
                title: _buildTopBarTitle(l10n, unit, direction.isRtl),
                // One toolkit entry, not a row of competing shortcuts. Mode,
                // page scale, colour filters and OCR stay in the sheet.
                actions: [
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 4),
                    child: IconButton(
                      key: const ValueKey('reader-tools'),
                      tooltip: l10n.readerSettings,
                      onPressed: _showReaderSettings,
                      style: IconButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: Colors.white.withValues(alpha: 0.10),
                        minimumSize: const Size(38, 38),
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: const Icon(Icons.tune_rounded, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        body: total == 0
            ? Theme(
                data: bestTheme(Brightness.dark),
                child: Center(
                  child: EmptyState(
                    icon: Icons.play_circle_outline,
                    title: unit.kind == UnitKind.episode
                        ? l10n.videoInPlayer
                        : l10n.noPagesTitle,
                    body: unit.kind == UnitKind.episode
                        ? l10n.nothingHereBody
                        : l10n.noPagesBody,
                  ),
                ),
              )
            : Stack(
                children: [
                  _buildReadingViewport(settings, background),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: ReaderReadingHud(
                      chapterTitle: unitTitle(l10n, unit),
                      pageLabel: _hudPositionLabel(),
                      visible:
                          settings.readerMode == ReaderMode.vertical &&
                          !_showChrome,
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: AnimatedOpacity(
                      opacity: _showChrome ? 1.0 : 0.0,
                      duration: BestMotion.normal,
                      child: IgnorePointer(
                        ignoring: !_showChrome,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                background.withValues(alpha: 0),
                                BestColors.inkDeep.withValues(alpha: 0.58),
                                BestColors.inkDeep.withValues(alpha: 0.94),
                              ],
                              stops: const [0, 0.34, 1],
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ReaderQuickDock(
                                bookmarked:
                                    (ref.watch(
                                              readerBookmarksProvider,
                                            )[unit.id] ??
                                            const <int>[])
                                        .contains(_index),
                                vertical:
                                    settings.readerMode == ReaderMode.vertical,
                                onBookmark: _toggleBookmark,
                                onPages: _showPageGrid,
                                onChapters: _showChaptersSheet,
                                chaptersEnabled: widget.data.units.isNotEmpty,
                                onToggleMode: _toggleMode,
                                onDisplay: _showColorFilterSheet,
                              ),
                              ReaderControlsBar(
                                key: const ValueKey('reader-controls'),
                                chapterId: unit.id,
                                pageIndex: _index,
                                pageCount: total,
                                pageLabel: (page) =>
                                    _pagePositionLabel(l10n, page),
                                rightToLeft: direction.isRtl,
                                finished: _atEnd,
                                partialEnd:
                                    widget.data.partial && _atAvailableEnd,
                                nextChapterTitle: _nextUnit == null
                                    ? null
                                    : unitTitle(l10n, _nextUnit!),
                                onSeek: _jumpToPage,
                                onScrubStart: () => _scrubbing = true,
                                onScrubEnd: () => _scrubbing = false,
                                onNextChapter:
                                    _nextUnit == null || widget.data.partial
                                    ? null
                                    : _openNextUnit,
                                autoScrollAvailable:
                                    settings.readerMode == ReaderMode.vertical,
                                autoScrolling: _autoScrolling,
                                onToggleAutoScroll: _toggleAutoScroll,
                                autoScrollSpeedLabel: _autoScrollSpeedLabel,
                                onCycleAutoScrollSpeed: _cycleAutoScrollSpeed,
                                verticalProgress:
                                    settings.readerMode == ReaderMode.vertical
                                    ? _verticalProgress
                                    : null,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

Widget _pageFrame(
  BuildContext context,
  Widget child,
  int? frame,
  bool wasSynchronouslyLoaded, {
  bool reserveHeight = false,
  int? index,
  int? total,
}) {
  if (frame == null && !wasSynchronouslyLoaded) {
    return _PageLoading(index: index, total: total, fill: !reserveHeight);
  }
  // Announced by screen readers, and the smoke gate waits for it so a page
  // count alone can never be mistaken for a decoded image again.
  return Semantics(
    label: AppLocalizations.of(context).pageImage,
    image: true,
    child: child,
  );
}

/// The end of a continuous strip. The next chapter is one tap away here, not
/// only a drag past the last page or a small icon in the control bar.
class _VerticalChapterEnd extends StatelessWidget {
  const _VerticalChapterEnd({required this.title, required this.onOpen});

  final String? title;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 120),
      child: Center(
        child: FilledButton.icon(
          onPressed: onOpen,
          icon: const Icon(Icons.skip_next_rounded),
          label: Text(
            title == null
                ? l10n.readerNextChapter
                : '${l10n.readerNextChapter} · $title',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

/// The page slot while its image is still arriving.
///
/// Continuous mode reserves a page-shaped box so the strip keeps its scroll
/// extent; a spinner per page turned the reader into a column of tiny rings.
/// The page number tells the reader where they are without pretending the
/// page has loaded.
class _PageLoading extends StatelessWidget {
  const _PageLoading({this.index, this.total, required this.fill});

  final int? index;
  final int? total;
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final content = Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: BestColors.inkDeep.withValues(alpha: 0.70),
          borderRadius: BorderRadius.circular(BestRadius.pill),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 1.6,
                  color: BestColors.emberSoft,
                ),
              ),
              if (index != null && total != null && total! > 0) ...[
                const SizedBox(width: 8),
                Text(
                  l10n.pageOf(index! + 1, total!),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    if (fill) {
      return LayoutBuilder(
        builder: (context, constraints) {
          // FittedBox and original-size pan surfaces intentionally give their
          // children unbounded constraints. A loading scan is a viewport slot,
          // not an infinitely large image.
          final viewport = MediaQuery.sizeOf(context);
          return SizedBox(
            width: constraints.hasBoundedWidth
                ? constraints.maxWidth
                : viewport.width,
            height: constraints.hasBoundedHeight
                ? constraints.maxHeight
                : viewport.height,
            child: content,
          );
        },
      );
    }
    return SizedBox(
      width: double.infinity,
      height: MediaQuery.sizeOf(context).width * 1.4,
      child: content,
    );
  }
}

Widget _networkImage(
  String url,
  Map<String, String> headers, {
  BoxFit fit = BoxFit.contain,
  double? width,
  int? cacheWidth,
  Key? key,
  VoidCallback? onRetry,
  VoidCallback? onError,
  bool reserveHeight = false,
  int? index,
  int? total,
}) {
  return Image.network(
    url,
    key: key,
    headers: headers.isEmpty ? null : headers,
    width: width,
    cacheWidth: cacheWidth,
    fit: fit,
    filterQuality: FilterQuality.medium,
    frameBuilder:
        (
          BuildContext context,
          Widget child,
          int? frame,
          bool wasSynchronouslyLoaded,
        ) => _pageFrame(
          context,
          child,
          frame,
          wasSynchronouslyLoaded,
          reserveHeight: reserveHeight,
          index: index,
          total: total,
        ),
    loadingBuilder:
        (BuildContext context, Widget child, ImageChunkEvent? progress) {
          if (progress == null) return child;
          return _PageLoading(index: index, total: total, fill: !reserveHeight);
        },
    errorBuilder: (BuildContext context, Object error, StackTrace? stack) {
      onError?.call();
      return _PageError(
        message: '$error',
        onRetry: onRetry,
        index: index,
        total: total,
      );
    },
  );
}

class _PageError extends StatelessWidget {
  const _PageError({this.message, this.onRetry, this.index, this.total});

  final String? message;
  final VoidCallback? onRetry;
  final int? index;
  final int? total;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = message?.trim();
    final pageLabel = switch (index) {
      null => l10n.pageImageError,
      final page when total != null && total! > 0 => l10n.pageOf(
        page + 1,
        total!,
      ),
      final page => l10n.pageImageErrorPage(page + 1),
    };
    return Semantics(
      label: '$pageLabel. ${l10n.pageImageErrorBody}',
      container: true,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 280),
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: BestColors.inkDeep.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(BestRadius.lg),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.broken_image_outlined,
                color: BestColors.emberSoft,
                size: 34,
              ),
              const SizedBox(height: 12),
              Text(
                pageLabel,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.pageImageErrorBody,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              if (text != null && text.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white30, fontSize: 10),
                ),
              ],
              if (onRetry != null) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: onRetry,
                  style: TextButton.styleFrom(
                    foregroundColor: BestColors.emberSoft,
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: Text(l10n.retry),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _OcrPageOverlay extends ConsumerStatefulWidget {
  const _OcrPageOverlay({
    required this.unitId,
    required this.index,
    required this.getBytes,
    required this.continuous,
    required this.child,
  });

  final String unitId;
  final int index;
  final Future<Uint8List?> Function() getBytes;
  final bool continuous;
  final Widget child;

  @override
  ConsumerState<_OcrPageOverlay> createState() => _OcrPageOverlayState();
}

class _OcrPageOverlayState extends ConsumerState<_OcrPageOverlay> {
  PageOcrResult? _ocrResult;
  bool _loading = false;
  String? _lastUnitId;
  int? _lastIndex;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkOcr());
  }

  @override
  void didUpdateWidget(covariant _OcrPageOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.unitId != widget.unitId || oldWidget.index != widget.index) {
      _checkOcr();
    }
  }

  Future<void> _checkOcr() async {
    if (!mounted) return;
    final enabled = ref.read(settingsProvider).ocrTranslationEnabled;
    if (!enabled) {
      if (_ocrResult != null) setState(() => _ocrResult = null);
      return;
    }

    if (_ocrResult != null &&
        _lastUnitId == widget.unitId &&
        _lastIndex == widget.index) {
      return;
    }

    final repository = ref.read(repositoryProvider);
    final cached = await repository.getPageOcr(widget.unitId, widget.index);
    if (cached != null) {
      if (mounted) {
        setState(() {
          _ocrResult = cached;
          _lastUnitId = widget.unitId;
          _lastIndex = widget.index;
        });
      }
      return;
    }

    if (_loading) return;
    setState(() => _loading = true);

    try {
      final bytes = await widget.getBytes();
      if (bytes != null && bytes.isNotEmpty && mounted) {
        final client = ref.read(ocrClientProvider);
        final result = await client.processAndTranslatePage(
          unitId: widget.unitId,
          pageIndex: widget.index,
          imageBytes: bytes,
        );
        if (mounted) {
          setState(() {
            _ocrResult = result;
            _lastUnitId = widget.unitId;
            _lastIndex = widget.index;
          });
        }
      }
    } catch (_) {
      // Ignored
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    ref.listen(settingsProvider.select((s) => s.ocrTranslationEnabled), (
      prev,
      next,
    ) {
      if (next) {
        _checkOcr();
      } else {
        setState(() => _ocrResult = null);
      }
    });

    final ocr = _ocrResult;
    final enabled = ref.watch(
      settingsProvider.select((s) => s.ocrTranslationEnabled),
    );

    if (!enabled ||
        ocr == null ||
        ocr.bubbles.isEmpty ||
        ocr.imageWidth <= 0 ||
        ocr.imageHeight <= 0) {
      if (_loading && enabled) {
        return Stack(
          alignment: Alignment.center,
          children: [
            widget.child,
            Positioned(
              top: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: BestColors.jade.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: BestColors.jade,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      l10n.readerTranslating,
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      }
      return widget.child;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Original-size pages are laid out with unbounded constraints; a bubble
        // overlay has no width to position against, so the page stays clean.
        if (!constraints.maxWidth.isFinite) return widget.child;
        final cw = constraints.maxWidth;
        final ch = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : cw * 1.4;

        double displayW, displayH, offsetX, offsetY;
        final imageAspect = ocr.imageWidth / ocr.imageHeight;

        if (widget.continuous) {
          displayW = cw;
          displayH = cw / imageAspect;
          offsetX = 0;
          offsetY = 0;
        } else {
          final containerAspect = cw / ch;
          if (containerAspect > imageAspect) {
            displayH = ch;
            displayW = ch * imageAspect;
            offsetX = (cw - displayW) / 2;
            offsetY = 0;
          } else {
            displayW = cw;
            displayH = cw / imageAspect;
            offsetX = 0;
            offsetY = (ch - displayH) / 2;
          }
        }

        return Stack(
          alignment: Alignment.center,
          children: [
            widget.child,
            Positioned(
              left: offsetX,
              top: offsetY,
              width: displayW,
              height: displayH,
              child: BubbleOverlayWidget(
                bubbles: ocr.bubbles,
                imageWidth: ocr.imageWidth,
                imageHeight: ocr.imageHeight,
                displayWidth: displayW,
                displayHeight: displayH,
                visible: true,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Renders a very tall webtoon scan as native 2048 px tiles instead of one
/// texture. Flutter can decode a 20,000 px strip, but a single oversized
/// texture is exactly where low-end GPUs stutter or fail. The native slicer
/// already existed (ported from HikariManga); this is the missing reader hook.
class _WebtoonSliceImage extends ConsumerStatefulWidget {
  const _WebtoonSliceImage({
    super.key,
    this.bytes,
    this.filePath,
    required this.pageId,
    required this.fallback,
    required this.index,
    required this.total,
    required this.cacheWidth,
  }) : assert(bytes != null || filePath != null);

  /// Network/extension bytes, or a downloaded file. Downloaded webtoons need
  /// the same protection; reading the file only after its size passes the
  /// threshold avoids pulling every ordinary page into memory.
  final Uint8List? bytes;
  final String? filePath;
  final String pageId;
  final Widget fallback;
  final int index;
  final int total;
  final int? cacheWidth;

  @override
  ConsumerState<_WebtoonSliceImage> createState() => _WebtoonSliceImageState();
}

class _WebtoonSliceImageState extends ConsumerState<_WebtoonSliceImage> {
  /// Below this, the method-channel bounds check costs more than decoding the
  /// page normally. Real long-strip exports are several times this size.
  static const int _sliceThresholdBytes = 700000;

  Future<List<WebtoonSlice>>? _future;

  @override
  void initState() {
    super.initState();
    _future = _loadSlices();
  }

  @override
  void didUpdateWidget(_WebtoonSliceImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bytes != widget.bytes ||
        oldWidget.filePath != widget.filePath ||
        oldWidget.pageId != widget.pageId) {
      _future = _loadSlices();
    }
  }

  Future<List<WebtoonSlice>> _loadSlices() async {
    final Uint8List bytes;
    final source = widget.bytes;
    if (source != null) {
      bytes = source;
      if (bytes.length < _sliceThresholdBytes) return const <WebtoonSlice>[];
    } else {
      final path = widget.filePath;
      if (path == null) return const <WebtoonSlice>[];
      try {
        final file = File(path);
        if (await file.length() < _sliceThresholdBytes) {
          return const <WebtoonSlice>[];
        }
        bytes = await file.readAsBytes();
      } catch (_) {
        return const <WebtoonSlice>[];
      }
      if (bytes.length < _sliceThresholdBytes) return const <WebtoonSlice>[];
    }
    final client = ref.read(ocrClientProvider);
    if (!await client.shouldSliceWebtoon(bytes)) {
      return const <WebtoonSlice>[];
    }
    return client.sliceWebtoon(bytes: bytes, pageId: widget.pageId);
  }

  void _reload() {
    setState(() => _future = _loadSlices());
  }

  @override
  Widget build(BuildContext context) {
    final source = widget.bytes;
    if (source != null && source.length < _sliceThresholdBytes) {
      return widget.fallback;
    }
    return FutureBuilder<List<WebtoonSlice>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _PageLoading(
            index: widget.index,
            total: widget.total,
            fill: true,
          );
        }
        final slices = snapshot.data ?? const <WebtoonSlice>[];
        if (snapshot.hasError || slices.isEmpty) return widget.fallback;
        return Semantics(
          label: AppLocalizations.of(context).pageImage,
          image: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final slice in slices)
                SizedBox(
                  width: double.infinity,
                  child: AspectRatio(
                    aspectRatio: slice.aspectRatio,
                    child: RepaintBoundary(
                      child: Image.file(
                        File(slice.filePath),
                        width: double.infinity,
                        fit: BoxFit.fill,
                        cacheWidth: widget.cacheWidth,
                        filterQuality: FilterQuality.medium,
                        gaplessPlayback: true,
                        errorBuilder: (context, error, stack) {
                          return _PageError(
                            message: '$error',
                            onRetry: _reload,
                            index: widget.index,
                            total: widget.total,
                          );
                        },
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ResourcePage extends ConsumerStatefulWidget {
  const _ResourcePage({
    super.key,
    required this.unitId,
    required this.resource,
    required this.sourceId,
    required this.index,
    required this.total,
    this.continuous = false,
    this.fit = ReaderFit.screen,
    this.colorFilter = const ReaderColorFilter(),
    this.viewportScale = 1,
    this.inputLocked = false,
    this.zoomFocal = Offset.zero,
    this.manualScroll = 0,
    this.active = true,
  });

  final String unitId;
  final MediaResource resource;
  final String sourceId;
  final int index;
  final int total;
  final bool continuous;
  final ReaderFit fit;
  final ReaderColorFilter colorFilter;
  final double viewportScale;
  final bool inputLocked;
  final Offset zoomFocal;
  final double manualScroll;
  final bool active;

  @override
  ConsumerState<_ResourcePage> createState() => _ResourcePageState();
}

class _ResourcePageState extends ConsumerState<_ResourcePage> {
  final ScrollController _widthController = ScrollController();
  double _pendingWidthAdjustment = 0;
  bool _widthAdjustmentScheduled = false;

  /// Bytes for an image page: the extension host's signed response, or the
  /// shared disk cache for an ordinary source. Null for files and videos.
  Future<Uint8List?>? _bytes;

  /// Present when the shared page cache already holds this page in memory.
  /// Painting it synchronously removes the flash on a mode switch.
  Uint8List? _memoryBytes;

  /// Bumped by a retry so a failed network page is requested again instead of
  /// replaying the failed image from the flutter image cache.
  int _attempt = 0;

  /// A transient failure gets one quiet retry before the reader is asked to
  /// act. More than one would hammer a source that is genuinely down.
  bool _autoRetried = false;
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    _loadSignedImage();
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _widthController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_ResourcePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.continuous &&
        widget.fit == ReaderFit.width &&
        oldWidget.fit == ReaderFit.width &&
        widget.active &&
        oldWidget.active) {
      final focalAdjustment =
          widget.zoomFocal.dy *
          (1 / oldWidget.viewportScale - 1 / widget.viewportScale);
      _adjustWidthScroll(
        focalAdjustment + widget.manualScroll - oldWidget.manualScroll,
      );
    }
    if (oldWidget.resource != widget.resource ||
        oldWidget.sourceId != widget.sourceId) {
      _retryTimer?.cancel();
      _autoRetried = false;
      _attempt++;
      _bytes = null;
      _memoryBytes = null;
      _loadSignedImage();
    }
  }

  void _adjustWidthScroll(double adjustment) {
    if (adjustment.abs() < 0.001) return;
    _pendingWidthAdjustment += adjustment;
    if (_widthAdjustmentScheduled) return;
    _widthAdjustmentScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _widthAdjustmentScheduled = false;
      if (!mounted || !_widthController.hasClients) return;
      final offset = _widthController.offset + _pendingWidthAdjustment;
      _pendingWidthAdjustment = 0;
      _widthController.jumpTo(
        offset
            .clamp(
              _widthController.position.minScrollExtent,
              _widthController.position.maxScrollExtent,
            )
            .toDouble(),
      );
    });
  }

  void _handleImageError() {
    if (_autoRetried) return;
    _autoRetried = true;
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) _retry();
    });
  }

  void _loadSignedImage() {
    _memoryBytes = null;
    final resource = widget.resource;
    if (resource is FileResource) {
      // Keep FileImage's decoded scan alive when switching layouts. A repair
      // evicts it explicitly in _retry before reading the path again.
      return;
    }
    if (resource is! ImageResource) return;
    final cache = ref.read(pageImageCacheProvider);
    _memoryBytes = cache.memoryBytes(resource);
    final source = extensionSourceIdOf(widget.sourceId);
    if (source != null) {
      // Extension pages are signed by the host, so cache the bytes it returned
      // rather than issuing a second request with the wrong signature.
      final host = ref.read(extensionHostProvider);
      _bytes = cache.loadWith(
        resource,
        () => host.imageBytes(source, resource.url, headers: resource.headers),
      );
    } else {
      // Ordinary pages share a disk cache keyed by URL and headers, so a
      // reopened chapter paints from storage instead of the network.
      _bytes = cache.load(resource);
    }
  }

  Future<Uint8List?> _getImageBytes() async {
    final resource = widget.resource;
    if (resource is ImageResource) {
      if (_bytes != null) {
        final b = await _bytes;
        if (b != null && b.isNotEmpty) return b;
      }
      try {
        final res = await ref
            .read(httpClientProvider)
            .get(
              Uri.parse(resource.url),
              headers: resource.headers.isEmpty ? null : resource.headers,
            );
        if (res.statusCode == 200) return res.bodyBytes;
      } catch (_) {}
    } else if (resource is FileResource) {
      try {
        return await File(resource.path).readAsBytes();
      } catch (_) {}
    }
    return null;
  }

  bool get _fitsWidth => widget.continuous || widget.fit == ReaderFit.width;

  BoxFit get _imageFit {
    if (_fitsWidth) return BoxFit.fitWidth;
    if (widget.fit == ReaderFit.height) return BoxFit.fitHeight;
    if (widget.fit == ReaderFit.original) return BoxFit.none;
    return BoxFit.contain;
  }

  double? get _imageWidth => _fitsWidth ? double.infinity : null;

  void _retry() {
    _retryTimer?.cancel();
    final resource = widget.resource;
    unawaited(() async {
      // A retry after a decode failure must not read the same damaged file
      // again. Drop it before asking the source for a fresh copy, including
      // extension pages that now live in the shared cache.
      if (resource is ImageResource) {
        await ref.read(pageImageCacheProvider).evict(resource);
      } else if (resource is FileResource) {
        // The file was repaired in place; FileImage does not include bytes or
        // mtime in its key, so drop the decoded copy before reading it again.
        PaintingBinding.instance.imageCache.evict(
          FileImage(File(resource.path)),
        );
      }
      if (!mounted) return;
      setState(() {
        _attempt++;
        _bytes = null;
        _memoryBytes = null;
        _loadSignedImage();
      });
    }());
  }

  /// One decode width for the life of the page, independent of pinch scale.
  /// Two screen widths, capped at 1600 pixels, keep a 2× zoom reasonably sharp
  /// on a weak phone without swapping the provider (and flashing a loading
  /// card) mid-gesture.
  int? get _cacheWidth {
    if (widget.fit == ReaderFit.original && !widget.continuous) return null;
    final media = MediaQuery.maybeOf(context);
    if (media == null) return null;
    return (media.size.width * media.devicePixelRatio * 2)
        .round()
        .clamp(720, 1600)
        .toInt();
  }

  /// Pinch belongs to the viewport in every mode. At fit width the inner scroll
  /// view keeps native vertical dragging; original size retains its intrinsic
  /// pan surface, but cannot fight the viewport's pinch or zoomed panning.
  Widget _pageBody(Widget child) {
    final withOcr = _OcrPageOverlay(
      unitId: widget.unitId,
      index: widget.index,
      getBytes: _getImageBytes,
      continuous: _fitsWidth,
      child: child,
    );
    final withFilter = ReaderColorFilterOverlay(
      filter: widget.colorFilter,
      child: withOcr,
    );
    if (widget.continuous) return withFilter;
    return switch (widget.fit) {
      ReaderFit.width => LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            controller: _widthController,
            physics: widget.inputLocked
                ? const NeverScrollableScrollPhysics()
                : const ClampingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(child: withFilter),
            ),
          );
        },
      ),
      ReaderFit.height => SizedBox.expand(
        // The whole viewport height is used; a wider scan is cropped rather
        // than shrunk into a letterbox. PageView still owns horizontal swipes.
        child: FittedBox(fit: BoxFit.fitHeight, child: withFilter),
      ),
      ReaderFit.original => InteractiveViewer(
        constrained: false,
        scaleEnabled: false,
        panEnabled: !widget.inputLocked && widget.viewportScale <= 1.001,
        // Start at the top of the scan, not its middle: a page taller than
        // the screen must open where reading starts.
        alignment: Alignment.topCenter,
        boundaryMargin: const EdgeInsets.all(80),
        minScale: 1,
        maxScale: 1,
        child: withFilter,
      ),
      ReaderFit.screen => Center(child: withFilter),
    };
  }

  /// Stable, filename-safe cache key for the native tile files. FNV-1a keeps
  /// the key identical across launches without trusting `String.hashCode`.
  String get _slicePageId {
    var hash = 2166136261;
    for (final code in '${widget.unitId}:${widget.index}'.codeUnits) {
      hash ^= code;
      hash = (hash * 16777619) & 0xFFFFFFFF;
    }
    return '${widget.index}_${hash.toRadixString(16)}';
  }

  Widget _byteImage(Uint8List bytes, {required int? cacheWidth}) {
    final image = _plainByteImage(bytes, cacheWidth: cacheWidth);
    if (!widget.continuous) return image;
    return _WebtoonSliceImage(
      key: ValueKey('slices-${widget.unitId}-${widget.index}-$_attempt'),
      bytes: bytes,
      pageId: _slicePageId,
      fallback: image,
      index: widget.index,
      total: widget.total,
      cacheWidth: cacheWidth,
    );
  }

  Widget _fileImage(String path, {required int? cacheWidth}) {
    final image = RepaintBoundary(
      child: Image.file(
        File(path),
        key: ValueKey('file-$path-$_attempt'),
        width: _imageWidth,
        fit: _imageFit,
        cacheWidth: cacheWidth,
        filterQuality: FilterQuality.medium,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
            _pageFrame(
              context,
              child,
              frame,
              wasSynchronouslyLoaded,
              reserveHeight: _fitsWidth,
              index: widget.index,
              total: widget.total,
            ),
        errorBuilder: (BuildContext context, Object error, StackTrace? stack) {
          _handleImageError();
          return _PageError(
            message: '$error',
            onRetry: _retry,
            index: widget.index,
            total: widget.total,
          );
        },
      ),
    );
    if (!widget.continuous) return image;
    return _WebtoonSliceImage(
      key: ValueKey('file-slices-$path-$_attempt'),
      filePath: path,
      pageId: _slicePageId,
      fallback: image,
      index: widget.index,
      total: widget.total,
      cacheWidth: cacheWidth,
    );
  }

  Widget _plainByteImage(Uint8List bytes, {required int? cacheWidth}) {
    return RepaintBoundary(
      child: Image.memory(
        bytes,
        width: _imageWidth,
        fit: _imageFit,
        cacheWidth: cacheWidth,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
            _pageFrame(
              context,
              child,
              frame,
              wasSynchronouslyLoaded,
              reserveHeight: _fitsWidth,
              index: widget.index,
              total: widget.total,
            ),
        errorBuilder: (BuildContext context, Object error, StackTrace? stack) {
          _handleImageError();
          return _PageError(
            message: '$error',
            onRetry: _retry,
            index: widget.index,
            total: widget.total,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final resource = widget.resource;
    final retry = _retry;
    final cacheWidth = _cacheWidth;
    return switch (resource) {
      ImageResource(:final url, :final headers) => _pageBody(
        Center(
          child: _bytes == null
              ? _networkImage(
                  url,
                  headers,
                  fit: _imageFit,
                  width: _imageWidth,
                  cacheWidth: cacheWidth,
                  key: ValueKey('network-$url-$_attempt'),
                  onRetry: retry,
                  onError: _handleImageError,
                  reserveHeight: _fitsWidth,
                  index: widget.index,
                  total: widget.total,
                )
              : _memoryBytes != null
              ? _byteImage(_memoryBytes!, cacheWidth: cacheWidth)
              : FutureBuilder<Uint8List?>(
                  key: ValueKey('bytes-$_attempt'),
                  future: _bytes,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      _handleImageError();
                      return _PageError(
                        message: '${snapshot.error}',
                        onRetry: retry,
                        index: widget.index,
                        total: widget.total,
                      );
                    }
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return _PageLoading(
                        index: widget.index,
                        total: widget.total,
                        fill: !_fitsWidth,
                      );
                    }
                    final bytes = snapshot.data;
                    if (bytes == null || bytes.isEmpty) {
                      // The host is absent (tests, desktop) or declined.
                      return _networkImage(
                        url,
                        headers,
                        fit: _imageFit,
                        width: _imageWidth,
                        cacheWidth: cacheWidth,
                        key: ValueKey('fallback-$url-$_attempt'),
                        onRetry: retry,
                        onError: _handleImageError,
                        reserveHeight: _fitsWidth,
                        index: widget.index,
                        total: widget.total,
                      );
                    }
                    return _byteImage(bytes, cacheWidth: cacheWidth);
                  },
                ),
        ),
      ),
      FileResource(:final path) => _pageBody(
        Center(child: _fileImage(path, cacheWidth: cacheWidth)),
      ),
      SyntheticPage(index: final pageIndex, label: final label) =>
        widget.continuous
            ? AspectRatio(
                aspectRatio: 3 / 4,
                child: _SyntheticPageView(
                  page: pageIndex,
                  label: label,
                  position: widget.index,
                  total: widget.total,
                ),
              )
            : _SyntheticPageView(
                page: pageIndex,
                label: label,
                position: widget.index,
                total: widget.total,
              ),
      VideoResource() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.play_circle_outline,
                color: Colors.white54,
                size: 56,
              ),
              const SizedBox(height: 16),
              Text(
                AppLocalizations.of(context).videoInPlayer,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    };
  }
}

/// A generated guide page. It is drawn, not downloaded, so the reader is fully
/// usable offline and the app never pretends a placeholder is licensed art.
class _SyntheticPageView extends StatelessWidget {
  const _SyntheticPageView({
    required this.page,
    required this.label,
    required this.position,
    required this.total,
  });

  final int page;
  final String label;
  final int position;
  final int total;

  static const List<List<Color>> _palettes = [
    [Color(0xFF15121B), Color(0xFF3A2233)],
    [Color(0xFF101A18), Color(0xFF1F4038)],
    [Color(0xFF1B1610), Color(0xFF4A3320)],
    [Color(0xFF111823), Color(0xFF233A52)],
  ];

  @override
  Widget build(BuildContext context) {
    final palette = _palettes[page % _palettes.length];

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: palette,
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 30,
                height: 1.25,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
