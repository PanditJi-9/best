import 'dart:async';

import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/generated/app_localizations.dart';

/// A single-line progress overlay, not a panel that takes space from the scan.
/// The 48 dp hit area stays generous while the visible track is only 2 dp.
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
                  constraints: const BoxConstraints(maxWidth: 128),
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
                                    : BestColors.blueSoft,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
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
                      activeTrackColor: BestColors.blue,
                      inactiveTrackColor: const Color(0xFF777777),
                      thumbColor: BestColors.blue,
                      overlayColor: BestColors.blue.withValues(alpha: 0.1),
                      activeTickMarkColor: Colors.transparent,
                      inactiveTickMarkColor: Colors.transparent,
                      showValueIndicator: ShowValueIndicator.never,
                    ),
                    child: Slider(
                      key: const ValueKey('reader-progress-slider'),
                      value: value,
                      min: 1,
                      max: widget.pageCount.toDouble(),
                      divisions:
                          widget.pageCount > 1 ? widget.pageCount - 1 : null,
                      semanticFormatterCallback: (value) =>
                          widget.pageLabel(_pageFor(value)),
                      onChangeStart: _startScrub,
                      onChangeEnd: _endScrub,
                      onChanged: widget.pageCount > 1 ? _previewScrub : null,
                    ),
                  ),
                ),
              ),
              if (widget.finished && widget.onNextChapter != null)
                IconButton(
                  key: const ValueKey('reader-next-chapter'),
                  tooltip: widget.nextChapterTitle == null
                      ? l10n.readerNextChapter
                      : '${l10n.readerNextChapter} · ${widget.nextChapterTitle}',
                  onPressed: widget.onNextChapter,
                  color: BestColors.blue,
                  icon: Icon(
                    widget.rightToLeft
                        ? Icons.chevron_left_rounded
                        : Icons.chevron_right_rounded,
                    size: 22,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
