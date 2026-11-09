import 'dart:async';
import 'dart:ui' as ui;

import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/generated/app_localizations.dart';

/// The reader's quiet navigation dock. Tools belong in the settings sheet;
/// this surface only handles page progress, bookmarks and chapter navigation.
class ReaderControlsBar extends StatefulWidget {
  const ReaderControlsBar({
    super.key,
    required this.chapterId,
    required this.chapterTitle,
    required this.pageIndex,
    required this.pageCount,
    required this.pageLabel,
    required this.bookmarked,
    required this.rightToLeft,
    required this.finished,
    required this.partialEnd,
    required this.onSeek,
    required this.onScrubStart,
    required this.onScrubEnd,
    required this.onBookmark,
    required this.onPageGrid,
    required this.onChapters,
    this.nextChapterTitle,
    this.onPreviousChapter,
    this.onNextChapter,
  }) : assert(pageCount > 0);

  final String chapterId;
  final String chapterTitle;
  final int pageIndex;
  final int pageCount;
  final String Function(int) pageLabel;
  final bool bookmarked;
  final bool rightToLeft;
  final bool finished;
  final bool partialEnd;
  final String? nextChapterTitle;
  final ValueChanged<int> onSeek;
  final VoidCallback onScrubStart;
  final VoidCallback onScrubEnd;
  final VoidCallback onBookmark;
  final VoidCallback onPageGrid;
  final VoidCallback onChapters;
  final VoidCallback? onPreviousChapter;
  final VoidCallback? onNextChapter;

  @override
  State<ReaderControlsBar> createState() => _ReaderControlsBarState();
}

class _ReaderControlsBarState extends State<ReaderControlsBar> {
  double? _scrubValue;

  int _pageFor(double value) =>
      (value.round() - 1).clamp(0, widget.pageCount - 1).toInt();

  @override
  void didUpdateWidget(ReaderControlsBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chapterId != widget.chapterId ||
        oldWidget.pageCount != widget.pageCount) {
      final wasScrubbing = _scrubValue != null;
      _scrubValue = null;
      if (wasScrubbing) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onScrubEnd();
        });
      }
    }
  }

  void _startScrub(double value) {
    widget.onScrubStart();
    setState(() => _scrubValue = value);
  }

  void _previewScrub(double value) {
    if (_scrubValue == null) {
      // Accessibility and keyboard adjustments can arrive without a pointer
      // drag. Those are deliberate single-page seeks, not a preview.
      widget.onSeek(_pageFor(value));
      return;
    }
    setState(() => _scrubValue = value);
  }

  void _endScrub(double value) {
    final target = _pageFor(value);
    setState(() => _scrubValue = null);
    if (target != widget.pageIndex) {
      widget.onSeek(target);
      unawaited(HapticFeedback.selectionClick());
    }
    widget.onScrubEnd();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final value = (_scrubValue ?? (widget.pageIndex + 1).toDouble())
        .clamp(1.0, widget.pageCount.toDouble())
        .toDouble();
    final label = widget.pageLabel(_pageFor(value));
    final navigationStyle = IconButton.styleFrom(
      minimumSize: const Size.square(BestLayout.minTouch),
      foregroundColor: Colors.white70,
      disabledForegroundColor: Colors.white24,
      backgroundColor: Colors.white.withValues(alpha: 0.045),
      side: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BestRadius.md),
      ),
    );

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: Align(
          alignment: Alignment.bottomCenter,
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(BestRadius.xl),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(BestRadius.xl),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Material(
                    color: BestColors.inkRaised.withValues(alpha: 0.94),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(BestRadius.xl),
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.09),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.partialEnd)
                            Padding(
                              padding: const EdgeInsets.only(top: 8, bottom: 4),
                              child: Text(
                                l10n.readerPartialOffline,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          if (widget.finished) _finishedNotice(l10n),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  label,
                                  key: const ValueKey('reader-progress-label'),
                                  maxLines: 2,
                                  style: TextStyle(
                                    color: _scrubValue == null
                                        ? Colors.white
                                        : BestColors.blueSoft,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: widget.bookmarked
                                    ? l10n.readerBookmarkRemove
                                    : l10n.readerBookmarkAdd,
                                onPressed: widget.onBookmark,
                                color: widget.bookmarked
                                    ? BestColors.blueSoft
                                    : Colors.white54,
                                icon: Icon(
                                  widget.bookmarked
                                      ? Icons.bookmark_rounded
                                      : Icons.bookmark_border_rounded,
                                  size: 20,
                                ),
                              ),
                              IconButton(
                                tooltip: l10n.readerPageGrid,
                                onPressed: widget.onPageGrid,
                                color: Colors.white54,
                                icon: const Icon(
                                  Icons.grid_view_rounded,
                                  size: 20,
                                ),
                              ),
                            ],
                          ),
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 6,
                              trackShape: const RoundedRectSliderTrackShape(),
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 8,
                                elevation: 0,
                                pressedElevation: 0,
                              ),
                              overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 22,
                              ),
                              activeTrackColor: BestColors.blue,
                              inactiveTrackColor:
                                  Colors.white.withValues(alpha: 0.12),
                              thumbColor: BestColors.blueSoft,
                              overlayColor:
                                  BestColors.blue.withValues(alpha: 0.12),
                              activeTickMarkColor: Colors.transparent,
                              inactiveTickMarkColor: Colors.transparent,
                              showValueIndicator: ShowValueIndicator.never,
                            ),
                            child: Slider(
                              key: const ValueKey('reader-progress-slider'),
                              value: value,
                              min: 1,
                              max: widget.pageCount.toDouble(),
                              divisions: widget.pageCount > 1
                                  ? widget.pageCount - 1
                                  : null,
                              semanticFormatterCallback: (value) =>
                                  widget.pageLabel(_pageFor(value)),
                              onChangeStart: _startScrub,
                              onChangeEnd: _endScrub,
                              onChanged:
                                  widget.pageCount > 1 ? _previewScrub : null,
                            ),
                          ),
                          Row(
                            textDirection: widget.rightToLeft
                                ? TextDirection.rtl
                                : TextDirection.ltr,
                            children: [
                              IconButton(
                                key: const ValueKey('reader-previous-navigation'),
                                tooltip: l10n.readerPreviousChapter,
                                onPressed: widget.onPreviousChapter,
                                style: navigationStyle,
                                icon: Icon(
                                  widget.rightToLeft
                                      ? Icons.chevron_right_rounded
                                      : Icons.chevron_left_rounded,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: BestSpace.sm),
                              Expanded(
                                child: Tooltip(
                                  message: l10n.chapters,
                                  child: TextButton(
                                    key: const ValueKey('reader-chapter-navigation'),
                                    onPressed: widget.onChapters,
                                    style: TextButton.styleFrom(
                                      minimumSize:
                                          const Size(0, BestLayout.minTouch),
                                      foregroundColor: Colors.white,
                                      backgroundColor:
                                          Colors.white.withValues(alpha: 0.045),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: BestSpace.sm,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(BestRadius.md),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.list_rounded, size: 18),
                                        const SizedBox(width: BestSpace.sm),
                                        Expanded(
                                          child: Text(
                                            widget.chapterTitle,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        const Icon(
                                          Icons.keyboard_arrow_down_rounded,
                                          color: Colors.white54,
                                          size: 18,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: BestSpace.sm),
                              IconButton(
                                key: const ValueKey('reader-next-navigation'),
                                tooltip: l10n.readerNextChapter,
                                onPressed: widget.onNextChapter,
                                style: navigationStyle,
                                icon: Icon(
                                  widget.rightToLeft
                                      ? Icons.chevron_left_rounded
                                      : Icons.chevron_right_rounded,
                                  size: 24,
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
            ),
          ),
        ),
      ),
    );
  }

  Widget _finishedNotice(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  size: 16, color: BestColors.jade),
              const SizedBox(width: BestSpace.sm),
              Expanded(
                child: Text(
                  l10n.readerFinished,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ],
          ),
          if (widget.nextChapterTitle != null)
            TextButton.icon(
              key: const ValueKey('reader-next-chapter'),
              onPressed: widget.onNextChapter,
              style: TextButton.styleFrom(
                foregroundColor: BestColors.blueSoft,
                minimumSize: const Size(0, BestLayout.minTouch),
              ),
              icon: const Icon(Icons.skip_next_rounded, size: 18),
              label: Text(
                '${l10n.readerNextChapter} · ${widget.nextChapterTitle}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l10n.readerLastChapter,
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}
