import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:best_domain/best_domain.dart';
import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../extension_host.dart';
import '../l10n/generated/app_localizations.dart';
import '../ocr/bubble_overlay_widget.dart';
import '../providers.dart';
import '../widgets/chapter_list_sheet.dart';
import '../widgets/reader_color_filter.dart';
import '../widgets/reader_hud.dart';
import '../widgets/reader_page_grid.dart';
import '../widgets/reader_settings_sheet.dart';

class ReaderScreen extends ConsumerWidget {
  const ReaderScreen({
    super.key,
    required this.sourceId,
    required this.url,
    required this.unitUrl,
    this.startAtEnd = false,
  });

  final String sourceId;
  final String url;
  final String unitUrl;

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
            title: l10n.sourceError,
            body: '$error',
            action: FilledButton.icon(
              onPressed: () => ref.invalidate(readerProvider(key)),
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(l10n.retry),
            ),
          ),
        ),
      ),
      data: (reader) => _ReaderView(
        key: ValueKey(reader.unit.id),
        data: reader,
        startAtEnd: startAtEnd,
      ),
    );
  }
}

class _ReaderView extends ConsumerStatefulWidget {
  const _ReaderView({
    super.key,
    required this.data,
    this.startAtEnd = false,
  });

  final ReaderData data;
  final bool startAtEnd;

  @override
  ConsumerState<_ReaderView> createState() => _ReaderViewState();
}

class _ReaderViewState extends ConsumerState<_ReaderView> {
  /// Readers replace each other when a chapter ends, and the old one is
  /// disposed *after* the new one starts. Restoring the system UI or releasing
  /// the wakelock on every dispose would therefore undo the new chapter.
  static int _openReaders = 0;

  PageController? _pagedController;
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
  ReaderColorFilter _colorFilter = const ReaderColorFilter();
  Timer? _chromeTimer;
  bool _awake = false;

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
    final total = _resources.length;
    if (total > 0 && _index >= total - 1) return;
    _chromeTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showChrome = false);
    });
  }

  void _updateFilter(ReaderColorFilter filter) {
    setState(() => _colorFilter = filter);
    ref.read(settingsProvider.notifier).setReaderFilter(
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
    if (ref.read(settingsProvider).readerMode == ReaderMode.vertical) {
      if (_verticalController.isAttached) {
        _verticalController.jumpTo(index: target);
      }
    } else if (_pagedController?.hasClients ?? false) {
      _pagedController!.jumpToPage(target);
    }
    if (target != _index) {
      setState(() => _index = target);
      _markRead(target);
      _saveNow();
    }
    _precacheAround(target);
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
    final current = ref.read(settingsProvider).readerMode;
    ref.read(settingsProvider.notifier).setReaderMode(
          current == ReaderMode.paged ? ReaderMode.vertical : ReaderMode.paged,
        );
  }

  void _showChaptersSheet() {
    final units = widget.data.units;
    if (units.isEmpty) return;
    _chromeTimer?.cancel();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
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
    _saveNow();
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
    final next = _nextUnit;
    if (next == null) return;
    _openUnit(next);
  }

  /// The outer thirds turn a page; the middle third toggles the controls. In a
  /// right-to-left chapter the forward zone is the left side, matching the way
  /// the pages themselves move.
  void _handleTap(TapUpDetails details, double width) {
    final settings = ref.read(settingsProvider);
    if (settings.readerMode == ReaderMode.vertical ||
        !settings.readerTapZones) {
      _toggleChrome();
      return;
    }
    final dx = details.localPosition.dx;
    if (dx < width * 0.3) {
      _turnPage(settings.readerDirection.isRtl ? 1 : -1);
    } else if (dx > width * 0.7) {
      _turnPage(settings.readerDirection.isRtl ? -1 : 1);
    } else {
      _toggleChrome();
    }
  }

  void _turnPage(int delta) {
    final total = _resources.length;
    if (total == 0) return;
    final target = (_index + delta).clamp(0, total - 1);
    if (target == _index) {
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

  /// Warm the cache for the pages on either side of the current one.
  ///
  /// Extension pages are deliberately skipped: the host fetches those with the
  /// extension's own signing client, so a plain HTTP warm-up would issue a
  /// second, differently-signed request. Downloaded files and ordinary image
  /// URLs use the same image providers the page itself uses, so the warm-up
  /// lands in the same cache entry.
  void _precacheAround(int index) {
    if (!mounted) return;
    if (!ref.read(settingsProvider).readerPreload) return;
    final total = _resources.length;
    if (total == 0) return;
    final extension = extensionSourceIdOf(widget.data.media.ref.sourceId);
    for (final offset in const <int>[1, -1, 2]) {
      final target = index + offset;
      if (target < 0 || target >= total) continue;
      if (!_prefetched.add(target)) continue;
      final resource = _resources[target];
      try {
        if (resource is ImageResource && extension == null) {
          unawaited(
            precacheImage(
              NetworkImage(
                resource.url,
                headers: resource.headers.isEmpty ? null : resource.headers,
              ),
              context,
              onError: (error, stack) {},
            ),
          );
        } else if (resource is FileResource) {
          unawaited(
            precacheImage(
              FileImage(File(resource.path)),
              context,
              onError: (error, stack) {},
            ),
          );
        }
      } catch (_) {
        // A failed warm-up is never a reading failure; the page reports its own
        // error and offers a retry.
      }
    }
  }

  void _stepVertical(int delta) {
    final total = _resources.length;
    if (total <= 1) return;
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
    // A sheet, dialog or the next chapter route owns the keyboard while it is
    // on top; otherwise an arrow pressed in chapter search would also flip the
    // hidden page behind it.
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return KeyEventResult.ignored;
    final settings = ref.read(settingsProvider);
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
    final settings = ref.read(settingsProvider);
    _colorFilter = _filterFrom(settings);
    final total = _resources.length;
    final saved = widget.data.progress?.position;
    if (total == 0) {
      _index = 0;
    } else if (saved != null) {
      _index = saved.clamp(0, total - 1);
    } else {
      _index = widget.startAtEnd ? total - 1 : 0;
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

  void _onPageChanged(int index) {
    final total = _resources.length;
    final atEnd = total > 0 && index >= total - 1;
    setState(() {
      _index = index;
      if (atEnd) _showChrome = true;
    });
    _markRead(index);
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 320), _saveNow);
    _precacheAround(index);
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
    if (!mounted) return;
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
    unawaited(
      _repository.saveProgress(
        UnitProgress(
          unitId: widget.data.unit.id,
          position: _index,
          total: total,
          completed: _index >= total - 1,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      ),
    );
  }

  void _toggleOcr() {
    final l10n = AppLocalizations.of(context);
    final next = !ref.read(settingsProvider).ocrTranslationEnabled;
    ref.read(settingsProvider.notifier).setOcrTranslationEnabled(next);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          next ? l10n.readerTranslateOn : l10n.readerTranslateOff,
        ),
        duration: const Duration(seconds: 2),
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final unit = widget.data.unit;
    final total = _resources.length;
    final settings = ref.watch(settingsProvider);
    final mode = settings.readerMode;
    final direction = settings.readerDirection;
    final background = _backgroundFor(settings.readerBackground);
    final bookmarked =
        (ref.watch(readerBookmarksProvider)[unit.id] ?? const <int>[])
            .contains(_index);

    // The settings sheet changes the same provider the reader builds from. When
    // the axis or the paged/vertical layout changes, the scroll position is
    // carried over explicitly; a PageController keeps pixels, not page numbers.
    ref.listen(settingsProvider.select((s) => s.readerKeepAwake), (_, next) {
      unawaited(_setAwake(next));
    });
    ref.listen(settingsProvider.select((s) => s.readerMode), (previous, next) {
      if (previous == null || previous == next) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (next == ReaderMode.vertical) {
          if (_verticalController.isAttached) {
            _verticalController.jumpTo(index: _index);
          }
        } else if (_pagedController?.hasClients ?? false) {
          _pagedController!.jumpToPage(_index);
        }
      });
    });
    ref.listen(
      settingsProvider.select((s) => s.readerDirection),
      (previous, next) {
        if (previous == null || previous == next) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_pagedController?.hasClients ?? false) {
            _pagedController!.jumpToPage(_index);
          }
        });
      },
    );

    return Focus(
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: Scaffold(
        backgroundColor: background,
        extendBodyBehindAppBar: true,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: AnimatedOpacity(
            opacity: _showChrome ? 1.0 : 0.0,
            duration: BestMotion.normal,
            child: IgnorePointer(
              ignoring: !_showChrome,
              child: AppBar(
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.white,
                flexibleSpace: ClipRect(
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                ),
                title: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap:
                      widget.data.units.isNotEmpty ? _showChaptersSheet : null,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              unit.displayTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (widget.data.units.isNotEmpty) ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.keyboard_arrow_down_rounded,
                                size: 18, color: Colors.white70),
                          ],
                        ],
                      ),
                      Text(
                        widget.data.media.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                actions: [
                  IconButton(
                    tooltip: mode == ReaderMode.paged
                        ? l10n.readerModeVertical
                        : l10n.readerModePaged,
                    onPressed: _toggleMode,
                    icon: Icon(
                      mode == ReaderMode.paged
                          ? Icons.view_stream_outlined
                          : Icons.auto_stories_outlined,
                      size: 21,
                    ),
                  ),
                  IconButton(
                    tooltip: bookmarked
                        ? l10n.readerBookmarkRemove
                        : l10n.readerBookmarkAdd,
                    onPressed: _resources.isEmpty ? null : _toggleBookmark,
                    icon: Icon(
                      bookmarked
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                      color: bookmarked ? BestColors.jade : Colors.white70,
                      size: 21,
                    ),
                  ),
                  IconButton(
                    tooltip: settings.ocrTranslationEnabled
                        ? l10n.readerTranslateDisable
                        : l10n.readerTranslateEnable,
                    onPressed: _toggleOcr,
                    icon: Icon(
                      Icons.translate_rounded,
                      color: settings.ocrTranslationEnabled
                          ? BestColors.jade
                          : Colors.white70,
                      size: 21,
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.readerSettings,
                    onPressed: _showReaderSettings,
                    icon: Icon(
                      Icons.settings_outlined,
                      color: _colorFilter.mode != ReaderColorFilterMode.none ||
                              _colorFilter.customBrightnessOffset < 0
                          ? BestColors.jade
                          : null,
                      size: 21,
                    ),
                  ),
                  if (widget.data.offline)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 14),
                      child: Center(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: BestColors.jade.withValues(alpha: 0.18),
                            borderRadius:
                                BorderRadius.circular(BestRadius.pill),
                            border: Border.all(
                              color: BestColors.jade.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 4,
                            ),
                            child: Text(
                              l10n.offlineBadge,
                              style: const TextStyle(
                                color: BestColors.jade,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
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
                  ColoredBox(
                    color: background,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTapUp: (details) => _handleTap(
                        details,
                        MediaQuery.sizeOf(context).width,
                      ),
                      child: mode == ReaderMode.vertical
                          ? ScrollablePositionedList.builder(
                              itemScrollController: _verticalController,
                              itemPositionsListener: _verticalPositions,
                              initialScrollIndex: _index,
                              itemCount: total,
                              itemBuilder: (BuildContext context, int index) {
                                final page = _ResourcePage(
                                  unitId: widget.data.unit.id,
                                  resource: _resources[index],
                                  sourceId: widget.data.media.ref.sourceId,
                                  index: index,
                                  total: total,
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
                            )
                          : PageView.builder(
                              reverse: direction.isRtl,
                              // Original size is a pan surface: letting the
                              // PageView compete would steal every drag. Taps and
                              // the slider still change pages there.
                              physics: settings.readerFit == ReaderFit.original
                                  ? const NeverScrollableScrollPhysics()
                                  : const PageScrollPhysics(),
                              controller: _pagedController ??=
                                  PageController(initialPage: _index),
                              onPageChanged: _onPageChanged,
                              itemCount: total,
                              itemBuilder: (BuildContext context, int index) =>
                                  _ResourcePage(
                                unitId: widget.data.unit.id,
                                resource: _resources[index],
                                sourceId: widget.data.media.ref.sourceId,
                                index: index,
                                total: total,
                                fit: settings.readerFit,
                                colorFilter: _colorFilter,
                              ),
                            ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: ReaderHud(
                      chapterTitle: unit.displayTitle,
                      page: _index + 1,
                      total: total,
                      isVerticalMode: mode == ReaderMode.vertical,
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
                        child: Container(
                          padding: EdgeInsets.fromLTRB(
                            20,
                            34,
                            20,
                            12 + MediaQuery.paddingOf(context).bottom,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.85),
                              ],
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_index + 1 >= total) ...[
                                if (_nextUnit != null)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: SizedBox(
                                      width: double.infinity,
                                      child: FilledButton.icon(
                                        onPressed: _openNextUnit,
                                        style: FilledButton.styleFrom(
                                          backgroundColor: BestColors.jade,
                                          foregroundColor: Colors.black,
                                        ),
                                        icon: const Icon(
                                          Icons.skip_next_rounded,
                                          size: 18,
                                        ),
                                        label: Text(
                                          '${l10n.readerNextChapter} · '
                                          '${_nextUnit!.displayTitle}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  )
                                else
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: Text(
                                      l10n.readerLastChapter,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                              ],
                              Row(
                                children: [
                                  if (_index + 1 >= total) ...[
                                    const Icon(
                                      Icons.check_circle_rounded,
                                      size: 13,
                                      color: BestColors.jade,
                                    ),
                                    const SizedBox(width: 6),
                                  ],
                                  Expanded(
                                    child: Text(
                                      _index + 1 >= total
                                          ? l10n.readerFinished
                                          : l10n.pageOf(_index + 1, total),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: BestSpace.md),
                                  Flexible(
                                    child: Text(
                                      widget.data.media.displayTitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.end,
                                      style: const TextStyle(
                                        color: Colors.white38,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 3,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 6,
                                  ),
                                  overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 12,
                                  ),
                                ),
                                child: Slider(
                                  value: (_index + 1)
                                      .toDouble()
                                      .clamp(1.0, total.toDouble()),
                                  min: 1.0,
                                  max: total.toDouble(),
                                  divisions: total > 1 ? total - 1 : 1,
                                  activeColor: BestColors.jade,
                                  inactiveColor: Colors.white24,
                                  onChangeStart: (_) => _chromeTimer?.cancel(),
                                  onChangeEnd: (_) => _scheduleChromeHide(),
                                  onChanged: (val) {
                                    final target =
                                        (val.round() - 1).clamp(0, total - 1);
                                    if (target != _index) {
                                      if (mode == ReaderMode.vertical) {
                                        _verticalController.jumpTo(
                                            index: target);
                                      } else {
                                        _pagedController?.jumpToPage(target);
                                      }
                                    }
                                  },
                                ),
                              ),
                              Row(
                                children: [
                                  IconButton(
                                    tooltip: l10n.readerPageGrid,
                                    onPressed: () => _showPageGrid(),
                                    color: Colors.white70,
                                    icon: const Icon(
                                      Icons.grid_view_rounded,
                                      size: 21,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: l10n.readerPreviousChapter,
                                    onPressed: _previousUnit == null
                                        ? null
                                        : _openPreviousUnit,
                                    color: Colors.white70,
                                    disabledColor: Colors.white24,
                                    icon: Icon(
                                      direction.isRtl
                                          ? Icons.chevron_right_rounded
                                          : Icons.chevron_left_rounded,
                                      size: 22,
                                    ),
                                  ),
                                  Expanded(
                                    child: TextButton.icon(
                                      onPressed: _showChaptersSheet,
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.white70,
                                      ),
                                      icon: const Icon(Icons.list_rounded,
                                          size: 16),
                                      label: Text(
                                        l10n.chapters,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: l10n.readerNextChapter,
                                    onPressed: _nextUnit == null
                                        ? null
                                        : _openNextUnit,
                                    color: Colors.white70,
                                    disabledColor: Colors.white24,
                                    icon: Icon(
                                      direction.isRtl
                                          ? Icons.chevron_left_rounded
                                          : Icons.chevron_right_rounded,
                                      size: 22,
                                    ),
                                  ),
                                ],
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
  bool wasSynchronouslyLoaded,
) {
  if (frame == null && !wasSynchronouslyLoaded) {
    return const Center(
      child: CircularProgressIndicator(color: BestColors.jade),
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

Widget _networkImage(
  String url,
  Map<String, String> headers, {
  BoxFit fit = BoxFit.contain,
  double? width,
  Key? key,
  VoidCallback? onRetry,
}) {
  return Image.network(
    url,
    key: key,
    headers: headers.isEmpty ? null : headers,
    width: width,
    fit: fit,
    frameBuilder: _pageFrame,
    loadingBuilder: (
      BuildContext context,
      Widget child,
      ImageChunkEvent? progress,
    ) {
      if (progress == null) return child;
      if (width == double.infinity) {
        // A page that has not decoded yet has no intrinsic height. Reserving
        // a page-shaped box keeps the strip scrollable while the first images
        // arrive instead of collapsing to zero height.
        return SizedBox(
          width: double.infinity,
          height: MediaQuery.sizeOf(context).width * 1.4,
          child: const Center(
            child: CircularProgressIndicator(color: BestColors.jade),
          ),
        );
      }
      return const Center(
        child: CircularProgressIndicator(color: BestColors.jade),
      );
    },
    errorBuilder: (
      BuildContext context,
      Object error,
      StackTrace? stack,
    ) =>
        _PageError(message: '$error', onRetry: onRetry),
  );
}

class _PageError extends StatelessWidget {
  const _PageError({this.message, this.onRetry});

  final String? message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final text = message;
    return Semantics(
      label: AppLocalizations.of(context).pageImageError,
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
              if (text != null && text.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
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
                  label: Text(AppLocalizations.of(context).retry),
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
  /// Non-null only for an extension page: the host fetches it with the
  /// extension's own client, cookies and signing interceptors included.
  Future<Uint8List?>? _bytes;

  /// Bumped by a retry so a failed network page is requested again instead of
  /// replaying the failed image from the flutter image cache.
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    final resource = widget.resource;
    final source = extensionSourceIdOf(widget.sourceId);
    if (resource is ImageResource && source != null) {
      _bytes = ref
          .read(extensionHostProvider)
          .imageBytes(source, resource.url, headers: resource.headers);
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
    if (widget.fit == ReaderFit.original) return BoxFit.none;
    return BoxFit.contain;
  }

  double? get _imageWidth => _fitsWidth ? double.infinity : null;

  void _retry() {
    setState(() {
      _attempt++;
      _bytes = null;
      final resource = widget.resource;
      final source = extensionSourceIdOf(widget.sourceId);
      if (resource is ImageResource && source != null) {
        _bytes = ref
            .read(extensionHostProvider)
            .imageBytes(source, resource.url, headers: resource.headers);
      }
    });
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
    return switch (resource) {
      ImageResource(:final url, :final headers) => _pageBody(
          Center(
            child: _bytes == null
                ? _networkImage(
                    url,
                    headers,
                    fit: _imageFit,
                    width: _imageWidth,
                    key: ValueKey('network-$url-$_attempt'),
                    onRetry: retry,
                  )
                : FutureBuilder<Uint8List?>(
                    key: ValueKey('bytes-$_attempt'),
                    future: _bytes,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return _PageError(
                          message: '${snapshot.error}',
                          onRetry: retry,
                        );
                      }
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(
                            color: BestColors.jade,
                          ),
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
                          key: ValueKey('fallback-$url-$_attempt'),
                          onRetry: retry,
                        );
                      }
                      return Image.memory(
                        bytes,
                        width: _imageWidth,
                        fit: _imageFit,
                        gaplessPlayback: true,
                        frameBuilder: _pageFrame,
                        errorBuilder: (
                          BuildContext context,
                          Object error,
                          StackTrace? stack,
                        ) =>
                            _PageError(onRetry: retry),
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
              errorBuilder: (
                BuildContext context,
                Object error,
                StackTrace? stack,
              ) =>
                  _PageError(onRetry: retry),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'BEST · ${(page + 1).toString().padLeft(2, '0')}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 11,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  height: 1.25,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '${position + 1} / $total',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 13,
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
