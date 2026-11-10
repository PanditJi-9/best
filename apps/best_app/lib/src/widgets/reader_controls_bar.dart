import 'dart:async';

import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/generated/app_localizations.dart';

/// A single-line progress overlay, not a panel that takes space from the scan.
/// The 48 dp hit area stays generous while the visible track is only 2 dp.
///
/// The rule reads as one object: the page label, how far through the chapter
/// the reader is, then the scrubber. Auto-scroll lives here because it is a
/// property of moving through the strip — but it is an [InkResponse], not a
/// second action button crowding the next-chapter step.
class ReaderControlsBar extends StatefulWidget {
  const ReaderControlsBar({
    super.key,
    required this.chapterId,
    required this.pageIndex,
    required this.pageCount,
    required this.pageLabel,
    required this.rightToLeft,
    required this.finished,
    required this.partialEnd,
    required this.onSeek,
    required this.onScrubStart,
    required this.onScrubEnd,
    this.nextChapterTitle,
    this.onNextChapter,
    this.autoScrollAvailable = false,
    this.autoScrolling = false,
    this.onToggleAutoScroll,
  }) : assert(pageCount > 0);

  final String chapterId;
  final int pageIndex;
  final int pageCount;
  final String Function(int) pageLabel;
  final bool rightToLeft;
  final bool finished;
  final bool partialEnd;
  final String? nextChapterTitle;
  final ValueChanged<int> onSeek;
  final VoidCallback onScrubStart;
  final VoidCallback onScrubEnd;
  final VoidCallback? onNextChapter;
  final bool autoScrollAvailable;
  final bool autoScrolling;
  final VoidCallback? onToggleAutoScroll;

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
    final preview = _pageFor(value);
    final label = widget.pageLabel(preview);
    final percent = ((preview + 1) / widget.pageCount * 100).round();
    final showAutoScroll =
        widget.autoScrollAvailable && widget.onToggleAutoScroll != null;
    return SafeArea(
      top: false,
      child: SizedBox(
        key: const ValueKey('reader-progress-strip'),
        height: BestLayout.minTouch,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: BestSpace.sm),
          child: Row(
            children: [
              Tooltip(
                message: widget.finished
                    ? l10n.readerFinished
                    : widget.partialEnd
                    ? l10n.readerPartialOffline
                    : label,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 132),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: BestColors.inkDeep.withValues(alpha: 0.82),
                      borderRadius: BorderRadius.circular(BestRadius.sm),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.10),
                        width: 0.8,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 5,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.finished || widget.partialEnd) ...[
                            Icon(
                              widget.finished
                                  ? Icons.check_rounded
                                  : Icons.info_outline_rounded,
                              size: 13,
                              color: widget.finished
                                  ? BestColors.jade
                                  : Colors.white70,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Flexible(
                            child: Text(
                              label,
                              key: const ValueKey('reader-progress-label'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: _scrubValue == null
                                    ? Colors.white
                                    : BestColors.emberSoft,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 7),
              SizedBox(
                width: 34,
                child: Text(
                  '$percent%',
                  key: const ValueKey('reader-progress-percent'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: BestFontFamily.mono,
                    color: Colors.white.withValues(alpha: 0.64),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: Directionality(
                  textDirection: widget.rightToLeft
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      trackShape: const RectangularSliderTrackShape(),
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 5,
                        elevation: 0,
                        pressedElevation: 0,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 16,
                      ),
                      activeTrackColor: BestColors.ember,
                      inactiveTrackColor: Colors.white.withValues(alpha: 0.22),
                      thumbColor: BestColors.emberSoft,
                      overlayColor: BestColors.ember.withValues(alpha: 0.14),
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
                      onChanged: widget.pageCount > 1 ? _previewScrub : null,
                    ),
                  ),
                ),
              ),
              if (showAutoScroll)
                _AutoScrollAction(
                  active: widget.autoScrolling,
                  onTap: widget.onToggleAutoScroll!,
                ),
              if (widget.finished && widget.onNextChapter != null)
                IconButton(
                  key: const ValueKey('reader-next-chapter'),
                  tooltip: widget.nextChapterTitle == null
                      ? l10n.readerNextChapter
                      : '${l10n.readerNextChapter} · ${widget.nextChapterTitle}',
                  onPressed: widget.onNextChapter,
                  style: IconButton.styleFrom(
                    foregroundColor: BestColors.emberSoft,
                    backgroundColor: BestColors.ember.withValues(alpha: 0.16),
                    minimumSize: const Size(40, 40),
                    padding: EdgeInsets.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: Icon(
                    widget.rightToLeft
                        ? Icons.chevron_left_rounded
                        : Icons.chevron_right_rounded,
                    size: 21,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AutoScrollAction extends StatelessWidget {
  const _AutoScrollAction({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = active ? l10n.readerAutoScrollPause : l10n.readerAutoScroll;
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 2),
      child: Semantics(
        button: true,
        toggled: active,
        label: label,
        child: Tooltip(
          message: label,
          child: Material(
            color: active
                ? BestColors.ember.withValues(alpha: 0.16)
                : Colors.transparent,
            shape: const CircleBorder(),
            child: InkResponse(
              key: const ValueKey('reader-auto-scroll'),
              onTap: onTap,
              radius: 18,
              containedInkWell: true,
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: 32,
                height: 32,
                child: Icon(
                  active
                      ? Icons.pause_rounded
                      : Icons.slow_motion_video_rounded,
                  size: 18,
                  color: active
                      ? BestColors.emberSoft
                      : Colors.white.withValues(alpha: 0.66),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
