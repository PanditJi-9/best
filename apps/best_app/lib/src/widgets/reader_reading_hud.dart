import 'dart:async';

import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';

/// A brief reading HUD for the continuous strip.
///
/// In vertical mode the chrome is hidden while reading, so the only way to
/// learn where you are used to be to open the menu and cover the page. This
/// reports the chapter and position for a moment after the page changes, then
/// leaves the artwork alone. It never takes a tap or a screen-reader stop:
/// the same information is available in the controls when the reader asks.
///
/// Ported in spirit from Yokai's `YokaiReaderHud`, rebuilt with Best's tokens.
class ReaderReadingHud extends StatefulWidget {
  const ReaderReadingHud({
    super.key,
    required this.chapterTitle,
    required this.pageLabel,
    required this.visible,
    this.linger = const Duration(milliseconds: 2400),
  });

  final String chapterTitle;
  final String pageLabel;

  /// The caller owns the mode and chrome rules. False while the controls are
  /// open or in paged mode, where a second page counter would be noise.
  final bool visible;

  /// How long the HUD stays after a page change. Kept short enough that it is
  /// gone before the next panel is read.
  final Duration linger;

  @override
  State<ReaderReadingHud> createState() => _ReaderReadingHudState();
}

class _ReaderReadingHudState extends State<ReaderReadingHud> {
  Timer? _hideTimer;
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    if (widget.visible) _reveal();
  }

  @override
  void didUpdateWidget(ReaderReadingHud oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.visible) {
      _hideTimer?.cancel();
      if (_shown) setState(() => _shown = false);
      return;
    }
    final changed =
        oldWidget.visible != widget.visible ||
        oldWidget.chapterTitle != widget.chapterTitle ||
        oldWidget.pageLabel != widget.pageLabel;
    if (changed) _reveal();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _reveal() {
    _hideTimer?.cancel();
    if (!_shown) setState(() => _shown = true);
    _hideTimer = Timer(widget.linger, () {
      if (mounted) setState(() => _shown = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final duration = BestMotionPolicy.of(
      context,
      _shown ? BestMotion.fast : BestMotion.slow,
    );
    return IgnorePointer(
      child: ExcludeSemantics(
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              BestSpace.md,
              BestSpace.sm,
              BestSpace.md,
              0,
            ),
            child: AnimatedOpacity(
              key: const ValueKey('reader-reading-hud'),
              opacity: _shown ? 1 : 0,
              duration: duration,
              curve: BestMotion.curve,
              child: Align(
                alignment: AlignmentDirectional.topStart,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: BestColors.inkDeep.withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(BestRadius.md),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                      width: 0.8,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: BestSpace.md,
                      vertical: BestSpace.sm,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            widget.chapterTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.78),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: BestSpace.sm),
                        Text(
                          widget.pageLabel,
                          maxLines: 1,
                          textDirection: TextDirection.ltr,
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: BestFontFamily.mono,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
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
      ),
    );
  }
}
