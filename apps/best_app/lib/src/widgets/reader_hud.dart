import 'dart:async';

import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';

/// A floating HUD overlay for vertical/webtoon reading mode.
///
/// Shows the chapter title and current page position (e.g. "12 / 48") in a
/// translucent pill that appears briefly after each page change and then fades
/// away. Ported from the Yokai design language's `YokaiReaderHud`.
///
/// The HUD is:
/// - Invisible in paged mode (paged mode has its own bottom bar).
/// - Non-interactive: [IgnorePointer] so it never steals a tap.
/// - Accessible: hidden from screen readers (purely informational duplicate).
class ReaderHud extends StatefulWidget {
  const ReaderHud({
    super.key,
    required this.chapterTitle,
    required this.page,
    required this.total,
    this.isVerticalMode = true,
  });

  final String chapterTitle;
  final int page;
  final int total;
  final bool isVerticalMode;

  @override
  State<ReaderHud> createState() => _ReaderHudState();
}

class _ReaderHudState extends State<ReaderHud> {
  bool _visible = false;
  Timer? _hideTimer;

  /// How long the HUD stays visible after a page change.
  static const _lingerDuration = Duration(milliseconds: 2400);

  @override
  void didUpdateWidget(ReaderHud old) {
    super.didUpdateWidget(old);
    // Show the HUD whenever the page changes in vertical mode.
    if (widget.isVerticalMode &&
        widget.total > 0 &&
        (widget.page != old.page || widget.total != old.total)) {
      _show();
    }
    // Hide immediately if we left vertical mode.
    if (!widget.isVerticalMode && _visible) {
      _hideTimer?.cancel();
      setState(() => _visible = false);
    }
  }

  void _show() {
    _hideTimer?.cancel();
    if (!_visible) setState(() => _visible = true);
    _hideTimer = Timer(_lingerDuration, () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isVerticalMode || widget.total <= 0) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    return IgnorePointer(
      child: ExcludeSemantics(
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: BestSpace.md,
              vertical: BestSpace.sm,
            ),
            child: AnimatedOpacity(
              opacity: _visible ? 1.0 : 0.0,
              duration: _visible
                  ? BestMotion.fast
                  : const Duration(milliseconds: 360),
              curve: BestMotion.curve,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface.withValues(alpha: 0.88),
                  borderRadius: BorderRadius.circular(BestRadius.md),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: BestAlpha.border,
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: BestSpace.md,
                    vertical: BestSpace.sm,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.chapterTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: BestSpace.sm),
                      Text(
                        '${widget.page} / ${widget.total}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontFamily: BestFontFamily.mono,
                          fontWeight: FontWeight.w500,
                          color: theme.colorScheme.onSurface,
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
    );
  }
}
