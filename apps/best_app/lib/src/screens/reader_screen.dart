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
import '../providers.dart';
import '../widgets/chapter_list_sheet.dart';
import '../widgets/reader_color_filter.dart';
import '../widgets/reader_controls_bar.dart';
import '../widgets/reader_page_grid.dart';
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
                  size: 18),
              label: Text(error is SourceNotInstalled
                  ? l10n.directoryTitle
                  : l10n.retry),
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

class _ReaderViewState extends ConsumerState<_ReaderView> {
  /// Readers replace each other when a chapter ends, and the old one is
  /// disposed *after* the new one starts. Restoring the system UI or releasing
  /// the wakelock on every dispose would therefore undo the new chapter.
  static int _openReaders = 0;

  PageController? _pagedController;
  ReaderPageLayout? _pagedLayout;
  ReaderDirection? _pagedDirection;
  late final LibraryRepository _repository;
  final ItemScrollController _verticalController = ItemScrollController();
  final ItemPositionsListener _verticalPositions =
      ItemPositionsListener.create();
  late int _index;
  Timer? _saveTimer;

  /// The furthest page reached in this session. Activity counts new ground
  /// only: flipping back and forth is one page read, not twenty.
  late int _furthest;

  List<MediaResource> get _resources => widget.data.resources;

  bool _showChrome = true;
  Timer? _chromeTimer;
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

  /// Decode scans at screen resolution instead of their full source size.
  ///
  /// A 1600 px scan displayed on a 390 px phone costs four times the memory
  /// and decode time for detail the screen cannot show. Original-size mode is
  /// the exception: it exists to inspect the whole scan, so it keeps the full
  /// resolution. Returns null when the full image should be decoded.
  int? get _decodeWidth {
    final settings = _readerSettings;
    if (settings.readerMode == ReaderMode.paged &&
        settings.readerFit == ReaderFit.original) {
      return null;
    }
    final media = MediaQuery.maybeOf(context);
    if (media == null) return null;
    return (media.size.width * media.devicePixelRatio)
        .round()
        .clamp(320, 2048)
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

  void _toggleChrome() {
    setState(() => _showChrome = !_showChrome);
    if (_showChrome) {
      _scheduleChromeHide();
    } else {
      _chromeTimer?.cancel();
    }
  }

  /// Controls fade out of the way after a few seconds, the way a paper page has
  /// no toolbar over it. A centre tap brings them back. At the end of a chapter
  /// they stay: the next-chapter button must not disappear before it is seen.
  void _scheduleChromeHide() {
    _chromeTimer?.cancel();
    if (!_showChrome) return;
    if (ModalRoute.of(context)?.isCurrent == false) return;
    if (_atEnd || (widget.data.partial && _atAvailableEnd)) return;
    _chromeTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showChrome = false);
    });
  }

  void _updateFilter(ReaderColorFilter filter) {
    _readerController.setReaderFilter(
      mode: filter.mode.name,
      brightness: filter.customBrightnessOffset,
    );
  }

  void _showColorFilterSheet() {
    _chromeTimer?.cancel();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(BestRadius.sheet)),
      ),
      builder: (context) => ReaderColorFilterSheet(
        filter: _colorFilter,
        onChanged: _updateFilter,
      ),
    ).whenComplete(() {
      if (mounted) _scheduleChromeHide();
    });
  }

  void _showReaderSettings() {
    _chromeTimer?.cancel();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(BestRadius.sheet)),
      ),
      builder: (context) => ReaderSettingsSheet(
        media: widget.data.media,
        unit: widget.data.unit,
        onOpenChapters: _showChaptersSheet,
        onOpenColorFilter: _showColorFilterSheet,
        onOpenPageGrid: () => _showPageGrid(),
        onOpenBookmarks: _showBookmarks,
      ),
    ).whenComplete(() {
      if (mounted) _scheduleChromeHide();
    });
  }

  void _showPageGrid({bool bookmarksOnly = false}) {
    if (_resources.isEmpty) return;
    _chromeTimer?.cancel();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(BestRadius.sheet)),
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
    ).whenComplete(() {
      if (mounted) _scheduleChromeHide();
    });
  }

  void _showBookmarks() => _showPageGrid(bookmarksOnly: true);

  void _jumpToPage(int index) {
    final total = _resources.length;
    if (total == 0) return;
    final target = index.clamp(0, total - 1);
    final atEnd =
        (_pagedLayout?.lastVisiblePage(target) ?? target) >= total - 1;
    if (target != _index || (atEnd && !_showChrome)) {
      setState(() {
        _index = target;
        if (atEnd) _showChrome = true;
      });
    }
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
    if (_atEnd) {
      _chromeTimer?.cancel();
    } else {
      _scheduleChromeHide();
    }
  }

  void _toggleBookmark() {
    if (_resources.isEmpty) return;
    final l10n = AppLocalizations.of(context);
    final bookmarks = ref.read(readerBookmarksProvider);
    final wasMarked =
        (bookmarks[widget.data.unit.id] ?? const <int>[]).contains(_index);
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
    final current = _readerSettings.readerMode;
    _readerController.setReaderMode(
      current == ReaderMode.paged ? ReaderMode.vertical : ReaderMode.paged,
    );
    unawaited(HapticFeedback.selectionClick());
  }

  void _showChaptersSheet() {
    final units = widget.data.units;
    if (units.isEmpty) return;
    _chromeTimer?.cancel();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(BestRadius.sheet)),
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
    ).whenComplete(() {
      if (mounted) _scheduleChromeHide();
    });
  }

  /// Replaces the route so a chapter does not stack dozens of readers on the
  /// back stack, and saves the current page before the old state is disposed.
  void _openUnit(MediaUnit unit, {bool startAtEnd = false}) {
    if (!mounted || _openingUnit) return;
    if (ModalRoute.of(context)?.isCurrent == false) return;
    _openingUnit = true;
    _saveNow();
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      router.pushReplacement(Routes.reader(
        sourceId: widget.data.media.ref.sourceId,
        url: widget.data.media.ref.url,
        unitUrl: unit.url,
        atEnd: startAtEnd,
      ));
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

  int get _unitIndex => widget.data.units.indexWhere(
        (unit) => unit.id == widget.data.unit.id,
      );

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
    _chromeTimer?.cancel();
    if (!_showChrome) setState(() => _showChrome = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(AppLocalizations.of(context).readerPartialOffline)),
    );
  }

  /// The outer thirds turn a page; the middle third toggles the controls. In a
  /// right-to-left chapter the forward zone is the left side, matching the way
  /// the pages themselves move.
  void _handleTap(TapUpDetails details, double width) {
    final settings = _readerSettings;
    if (settings.readerMode == ReaderMode.vertical ||
        !settings.readerTapZones) {
      _toggleChrome();
      return;
    }
    final dx = details.localPosition.dx;
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
    _chromeTimer?.cancel();
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
  /// Extension pages are deliberately skipped: the host fetches those with the
  /// extension's own signing client, so a plain HTTP warm-up would issue a
  /// second, differently-signed request. Ordinary image URLs are written to
  /// [PageImageCache] and then decoded with the same width the page will use,
  /// so the next swipe can paint immediately instead of showing a spinner.
  void _precacheAround(int index) {
    if (!mounted) return;
    if (!_readerSettings.readerPreload) return;
    final total = _resources.length;
    if (total == 0) return;
    final extension = extensionSourceIdOf(widget.data.media.ref.sourceId);
    final cache = ref.read(pageImageCacheProvider);
    final cacheWidth = _decodeWidth;
    for (final offset in const <int>[1, 2, 3, -1, -2]) {
      final target = index + offset;
      if (target < 0 || target >= total) continue;
      if (!_prefetched.add(target)) continue;
      final resource = _resources[target];
      try {
        if (resource is ImageResource && extension == null) {
          unawaited(() async {
            try {
              final bytes = await cache.load(resource);
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
    _openReaders++;
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
    if (settings.readerKeepAwake) {
      unawaited(_setAwake(true));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _scheduleChromeHide();
        _precacheAround(_index);
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
            _scheduleChromeHide();
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
  void dispose() {
    _chromeTimer?.cancel();
    _saveTimer?.cancel();
    _saveNow();
    _verticalPositions.itemPositions.removeListener(_onVerticalPositions);
    _pagedController?.dispose();
    _openReaders = _openReaders > 0 ? _openReaders - 1 : 0;
    if (_openReaders == 0) {
      unawaited(_setAwake(false));
      unawaited(
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge),
      );
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
    final total = _resources.length;
    final atEnd = total > 0 && pages.last >= total - 1;
    setState(() {
      _index = index;
      if (atEnd) _showChrome = true;
    });
    _markRead(pages.last);
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 320), _saveNow);
    _precacheAround(pages.last);
    if (atEnd) {
      _chromeTimer?.cancel();
    } else if (_showChrome) {
      _scheduleChromeHide();
    }
  }

  /// Continuous mode has no page callback, so the item under the top of the
  /// viewport is the current page. Its top half is the threshold: a page is
  /// reached when the reader can actually see it, not when its first pixel
  /// enters from below.
  void _onVerticalPositions() {
    if (!mounted ||
        _restoringVerticalPosition ||
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
    final index = current.index.clamp(0, total - 1);
    if (index == _index) return;
    final atEnd = index >= total - 1;
    setState(() => _index = index);
    _markRead(index);
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 320), _saveNow);
    _precacheAround(index);
    // Do not pop chrome over a webtoon page the person is still reading. If it
    // is already visible at the end it stays; otherwise a centre tap shows it.
    if (atEnd) {
      _chromeTimer?.cancel();
    } else if (_showChrome) {
      _scheduleChromeHide();
    }
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
            initialPage: next.viewForPage(_index), keepPage: false);
    _edgeDrag = 0;
    _dragStartedAtStart = false;
    _dragStartedAtEnd = false;

    // A controller's pixels refer to viewports, not source scans. Recreate it
    // when the grouping changes and detach the old view before disposing it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      oldController?.dispose();
      if (!mounted || next == null || !identical(next, _pagedLayout)) return;
      if (_atEnd && !_showChrome) setState(() => _showChrome = true);
      _markRead(_lastVisiblePage);
      _precacheAround(_lastVisiblePage);
      _scheduleChromeHide();
    });
  }

  /// Vertical mode has no page boundaries, so "continue to the next chapter"
  /// is a deliberate pull past the end of the last page. At that point — and
  /// only when auto-advance is on — the next chapter opens by itself.
  bool _handleVerticalScroll(ScrollNotification notification) {
    final metrics = notification.metrics;
    if (notification is ScrollStartNotification) {
      _verticalOverscroll = 0;
    } else if (notification is OverscrollNotification &&
        notification.overscroll > 0 &&
        metrics.extentAfter <= 0.5) {
      _verticalOverscroll += notification.overscroll;
    } else if (notification is ScrollEndNotification) {
      final go = _verticalOverscroll >= 72;
      _verticalOverscroll = 0;
      if (go &&
          _readerSettings.readerAutoAdvance &&
          !widget.data.partial &&
          _nextUnit != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_openingUnit) _openNextUnit();
        });
      }
    }
    return false;
  }

  bool _handlePagedScroll(ScrollNotification notification) {
    if (notification.depth != 0 ||
        notification.metrics.axis != Axis.horizontal) {
      return false;
    }
    final metrics = notification.metrics;
    if (notification is ScrollStartNotification) {
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
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _openingUnit || !identical(layout, _pagedLayout)) {
            return;
          }
          delta > 0 ? _openNextUnit() : _openPreviousUnit();
        });
      }
    }
    return false;
  }

  Widget _buildPagedView(AppSettings settings) {
    final layout = _pagedLayout!;
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) => identical(layout, _pagedLayout)
          ? _handlePagedScroll(notification)
          : false,
      child: PageView.builder(
        key: ValueKey((layout, settings.readerDirection)),
        reverse: settings.readerDirection.isRtl,
        physics: settings.readerFit == ReaderFit.original
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
          Widget scan(int page) => _ResourcePage(
                key: ValueKey(page),
                unitId: widget.data.unit.id,
                resource: _resources[page],
                sourceId: widget.data.media.ref.sourceId,
                index: page,
                total: _chapterTotal,
                fit: settings.readerFit,
                colorFilter: _colorFilter,
              );
          if (pages.length == 1) return scan(pages.single);
          return Row(
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
        },
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final unit = widget.data.unit;
    final total = _resources.length;
    final settings = ref.watch(readerSettingsForProvider(widget.data.media.id));
    final mode = settings.readerMode;
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
        ref.invalidate(readerProvider((
          sourceId: widget.data.media.ref.sourceId,
          url: widget.data.media.ref.url,
          unitUrl: unit.url,
        )));
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
                foregroundColor: BestColors.blue,
                title: Tooltip(
                  message: l10n.chapters,
                  child: InkWell(
                    key: const ValueKey('reader-chapter-picker'),
                    onTap: widget.data.units.isNotEmpty
                        ? _showChaptersSheet
                        : null,
                    child: SizedBox(
                      height: BestLayout.minTouch,
                      child: Center(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(BestRadius.xs),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    unitTitle(l10n, unit),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textDirection: autoTextDirection(
                                      unitTitle(l10n, unit),
                                      Directionality.of(context),
                                    ),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 4),
                                  child: Text('·',
                                      style: TextStyle(color: Colors.white54)),
                                ),
                                Flexible(
                                  child: Text(
                                    widget.data.media.displayTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textDirection: autoTextDirection(
                                      widget.data.media.displayTitle,
                                      Directionality.of(context),
                                    ),
                                    style: const TextStyle(
                                        fontSize: 10, color: Colors.white70),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // One toolkit entry, not a row of competing shortcuts. Mode,
                // page scale, colour filters and OCR stay in the sheet.
                actions: [
                  IconButton(
                    key: const ValueKey('reader-tools'),
                    tooltip: l10n.readerSettings,
                    onPressed: _showReaderSettings,
                    icon: const Icon(Icons.tune_rounded, size: 22),
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
                  ColoredBox(
                    color: background,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTapUp: (details) => _handleTap(
                        details,
                        MediaQuery.sizeOf(context).width,
                      ),
                      child: mode == ReaderMode.vertical
                          ? NotificationListener<ScrollNotification>(
                              onNotification: _handleVerticalScroll,
                              child: ScrollablePositionedList.builder(
                                itemScrollController: _verticalController,
                                itemPositionsListener: _verticalPositions,
                                initialScrollIndex: _index,
                                // Keep a screen-and-a-bit of pages alive on
                                // each side so a fast webtoon scroll does not
                                // outrun decoding and paint blank slots.
                                minCacheExtent: 1600,
                                itemCount: total,
                                itemBuilder: (BuildContext context, int index) {
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
                                  );
                                  final gap = settings.readerWebtoonGap;
                                  return gap <= 0
                                      ? page
                                      : Padding(
                                          padding: EdgeInsets.only(
                                            bottom: gap.toDouble(),
                                          ),
                                          child: page,
                                        );
                                },
                              ),
                            )
                          : _buildPagedView(settings),
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
                        child: ReaderControlsBar(
                          key: const ValueKey('reader-controls'),
                          chapterId: unit.id,
                          pageIndex: _index,
                          pageCount: total,
                          pageLabel: (page) => _pagePositionLabel(l10n, page),
                          rightToLeft: direction.isRtl,
                          finished: _atEnd,
                          partialEnd: widget.data.partial && _atAvailableEnd,
                          nextChapterTitle: _nextUnit == null
                              ? null
                              : unitTitle(l10n, _nextUnit!),
                          onSeek: _jumpToPage,
                          onScrubStart: () => _chromeTimer?.cancel(),
                          onScrubEnd: _scheduleChromeHide,
                          onNextChapter:
                              _nextUnit == null || widget.data.partial
                                  ? null
                                  : _openNextUnit,
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
    return _PageLoading(
      index: index,
      total: total,
      fill: !reserveHeight,
    );
  }
  // Announced by screen readers, and the smoke gate waits for it so a page
  // count alone can never be mistaken for a decoded image again.
  return Semantics(
    label: AppLocalizations.of(context).pageImage,
    image: true,
    child: child,
  );
}

/// The page slot while its image is still arriving.
///
/// Continuous mode reserves a page-shaped box so the strip keeps its scroll
/// extent; a spinner per page turned the reader into a column of tiny rings.
/// The page number tells the reader where they are without pretending the
/// page has loaded.
class _PageLoading extends StatelessWidget {
  const _PageLoading({
    this.index,
    this.total,
    required this.fill,
  });

  final int? index;
  final int? total;
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final content = ColoredBox(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (index != null && total != null && total! > 0)
              Text(
                l10n.pageOf(index! + 1, total!),
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            const SizedBox(height: 10),
            SizedBox(
              width: 44,
              child: LinearProgressIndicator(
                minHeight: 2,
                color: BestColors.jade,
                backgroundColor: Colors.white12,
              ),
            ),
          ],
        ),
      ),
    );
    if (fill) return SizedBox.expand(child: content);
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
    frameBuilder: (
      BuildContext context,
      Widget child,
      int? frame,
      bool wasSynchronouslyLoaded,
    ) =>
        _pageFrame(
      context,
      child,
      frame,
      wasSynchronouslyLoaded,
      reserveHeight: reserveHeight,
      index: index,
      total: total,
    ),
    loadingBuilder: (
      BuildContext context,
      Widget child,
      ImageChunkEvent? progress,
    ) {
      if (progress == null) return child;
      return _PageLoading(
        index: index,
        total: total,
        fill: !reserveHeight,
      );
    },
    errorBuilder: (
      BuildContext context,
      Object error,
      StackTrace? stack,
    ) {
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
  const _PageError({
    this.message,
    this.onRetry,
    this.index,
    this.total,
  });

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
      final page when total != null && total! > 0 =>
        l10n.pageOf(page + 1, total!),
      final page => l10n.pageImageErrorPage(page + 1),
    };
    return Semantics(
      label: '$pageLabel. ${l10n.pageImageErrorBody}',
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(BestRadius.md),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.broken_image_outlined,
                color: Colors.white38,
                size: 40,
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
                    foregroundColor: BestColors.jade,
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
    ref.listen(settingsProvider.select((s) => s.ocrTranslationEnabled),
        (prev, next) {
      if (next) {
        _checkOcr();
      } else {
        setState(() => _ocrResult = null);
      }
    });

    final ocr = _ocrResult;
    final enabled =
        ref.watch(settingsProvider.select((s) => s.ocrTranslationEnabled));

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
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: BestColors.jade.withValues(alpha: 0.5)),
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
        final ch =
            constraints.maxHeight.isFinite ? constraints.maxHeight : cw * 1.4;

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
  });

  final String unitId;
  final MediaResource resource;
  final String sourceId;
  final int index;
  final int total;
  final bool continuous;
  final ReaderFit fit;
  final ReaderColorFilter colorFilter;

  @override
  ConsumerState<_ResourcePage> createState() => _ResourcePageState();
}

class _ResourcePageState extends ConsumerState<_ResourcePage> {
  /// Bytes for an image page: the extension host's signed response, or the
  /// shared disk cache for an ordinary source. Null for files and videos.
  Future<Uint8List?>? _bytes;

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
    super.dispose();
  }

  @override
  void didUpdateWidget(_ResourcePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resource != widget.resource ||
        oldWidget.sourceId != widget.sourceId) {
      _retryTimer?.cancel();
      _autoRetried = false;
      _attempt++;
      _bytes = null;
      _loadSignedImage();
    }
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
    final resource = widget.resource;
    if (resource is FileResource) {
      // A repair replaces bytes at the same path. FileImage's cache key does
      // not include modification time or contents; reopen the actual scan.
      PaintingBinding.instance.imageCache.evict(FileImage(File(resource.path)));
      return;
    }
    if (resource is! ImageResource) return;
    final source = extensionSourceIdOf(widget.sourceId);
    if (source != null) {
      _bytes = ref
          .read(extensionHostProvider)
          .imageBytes(source, resource.url, headers: resource.headers);
    } else {
      // Ordinary pages share a disk cache keyed by URL and headers, so a
      // reopened chapter paints from storage instead of the network.
      _bytes = ref.read(pageImageCacheProvider).load(resource);
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
        final res = await ref.read(httpClientProvider).get(
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
    final extension = extensionSourceIdOf(widget.sourceId);
    unawaited(() async {
      // A retry after a decode failure must not read the same damaged file
      // again. Drop it before asking the source for a fresh copy.
      if (resource is ImageResource && extension == null) {
        await ref.read(pageImageCacheProvider).evict(resource);
      }
      if (!mounted) return;
      setState(() {
        _attempt++;
        _bytes = null;
        _loadSignedImage();
      });
    }());
  }

  /// The width a page should be decoded at. Original-size mode keeps the full
  /// scan because the person may pan into the details; every other mode only
  /// needs the pixels the screen can actually show.
  int? get _cacheWidth {
    if (widget.fit == ReaderFit.original && !widget.continuous) return null;
    final media = MediaQuery.maybeOf(context);
    if (media == null) return null;
    return (media.size.width * media.devicePixelRatio)
        .round()
        .clamp(320, 2048)
        .toInt();
  }

  /// Continuous mode leaves the vertical drag to the list. Fit-width pages
  /// scroll vertically, while original-size pages are panned inside the zoom
  /// surface instead of being silently cropped. Fit-screen pages stay plain so
  /// a horizontal swipe always reaches the PageView; zooming is an explicit
  /// choice in reader settings rather than an accidental gesture conflict.
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
          // Start at the top of the scan, not its middle: a page taller than
          // the screen must open where reading starts.
          alignment: Alignment.topCenter,
          boundaryMargin: const EdgeInsets.all(80),
          minScale: 0.5,
          maxScale: 5,
          child: withFilter,
        ),
      ReaderFit.screen => Center(child: withFilter),
    };
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
                      return Image.memory(
                        bytes,
                        width: _imageWidth,
                        fit: _imageFit,
                        cacheWidth: cacheWidth,
                        filterQuality: FilterQuality.medium,
                        gaplessPlayback: true,
                        frameBuilder: (
                          context,
                          child,
                          frame,
                          wasSynchronouslyLoaded,
                        ) =>
                            _pageFrame(
                          context,
                          child,
                          frame,
                          wasSynchronouslyLoaded,
                          reserveHeight: _fitsWidth,
                          index: widget.index,
                          total: widget.total,
                        ),
                        errorBuilder: (
                          BuildContext context,
                          Object error,
                          StackTrace? stack,
                        ) {
                          _handleImageError();
                          return _PageError(
                            message: '$error',
                            onRetry: retry,
                            index: widget.index,
                            total: widget.total,
                          );
                        },
                      );
                    },
                  ),
          ),
        ),
      FileResource(:final path) => _pageBody(
          Center(
            child: Image.file(
              File(path),
              key: ValueKey('file-$path-$_attempt'),
              width: _imageWidth,
              fit: _imageFit,
              cacheWidth: cacheWidth,
              filterQuality: FilterQuality.medium,
              frameBuilder: (
                context,
                child,
                frame,
                wasSynchronouslyLoaded,
              ) =>
                  _pageFrame(
                context,
                child,
                frame,
                wasSynchronouslyLoaded,
                reserveHeight: _fitsWidth,
                index: widget.index,
                total: widget.total,
              ),
              errorBuilder: (
                BuildContext context,
                Object error,
                StackTrace? stack,
              ) {
                _handleImageError();
                return _PageError(
                  message: '$error',
                  onRetry: retry,
                  index: widget.index,
                  total: widget.total,
                );
              },
            ),
          ),
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
