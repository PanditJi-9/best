import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';

/// The reader's one-tap shelf: the things a reader reaches for while their
/// hands are already on the page. It floats above the progress rule so the
/// scan keeps the full viewport, and it never grows into a second toolbar.
class ReaderQuickDock extends StatelessWidget {
  const ReaderQuickDock({
    super.key,
    required this.bookmarked,
    required this.vertical,
    required this.onBookmark,
    required this.onPages,
    required this.onChapters,
    required this.onToggleMode,
    required this.onDisplay,
    this.chaptersEnabled = true,
  });

  final bool bookmarked;
  final bool vertical;
  final VoidCallback onBookmark;
  final VoidCallback onPages;
  final VoidCallback onChapters;
  final VoidCallback onToggleMode;
  final VoidCallback onDisplay;
  final bool chaptersEnabled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(
        BestSpace.md,
        0,
        BestSpace.md,
        BestSpace.xs,
      ),
      padding: const EdgeInsets.all(BestSpace.xs),
      decoration: BoxDecoration(
        color: BestColors.inkDeep.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(BestRadius.lg + 4),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.30),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _DockAction(
            actionKey: const ValueKey('reader-quick-bookmark'),
            icon: bookmarked
                ? Icons.bookmark_rounded
                : Icons.bookmark_border_rounded,
            label: bookmarked
                ? l10n.readerBookmarkRemove
                : l10n.readerBookmarkAdd,
            active: bookmarked,
            onTap: onBookmark,
          ),
          _DockAction(
            actionKey: const ValueKey('reader-quick-pages'),
            icon: Icons.grid_view_rounded,
            label: l10n.readerPageGrid,
            onTap: onPages,
          ),
          _DockAction(
            actionKey: const ValueKey('reader-quick-chapters'),
            icon: Icons.format_list_numbered_rounded,
            label: l10n.chapters,
            onTap: chaptersEnabled ? onChapters : null,
          ),
          _DockAction(
            actionKey: const ValueKey('reader-quick-mode'),
            icon: vertical
                ? Icons.view_carousel_rounded
                : Icons.menu_book_rounded,
            label: vertical ? l10n.readerModePaged : l10n.readerModeVertical,
            onTap: onToggleMode,
          ),
          _DockAction(
            actionKey: const ValueKey('reader-quick-display'),
            icon: Icons.tonality_rounded,
            label: l10n.readerColorFilter,
            onTap: onDisplay,
          ),
        ],
      ),
    );
  }
}

class _DockAction extends StatelessWidget {
  const _DockAction({
    required this.actionKey,
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final Key actionKey;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final foreground = !enabled
        ? Colors.white.withValues(alpha: 0.26)
        : active
        ? BestColors.emberSoft
        : Colors.white.withValues(alpha: 0.84);
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        enabled: enabled,
        selected: active,
        label: label,
        child: Material(
          color: active
              ? BestColors.ember.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(BestRadius.md),
          child: InkWell(
            key: actionKey,
            onTap: onTap,
            borderRadius: BorderRadius.circular(BestRadius.md),
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(icon, size: 20, color: foreground),
            ),
          ),
        ),
      ),
    );
  }
}
