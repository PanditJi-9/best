import 'dart:io';

import 'package:best_domain/best_domain.dart';
import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';
import '../providers.dart';

/// A visual page navigator: every page as a thumbnail, with the current page
/// outlined and bookmarks marked.
///
/// Long-press is the quiet bookmark gesture. It keeps the toolbar to one row
/// and lets a person mark a page while jumping around, without opening a
/// second sheet.
class ReaderPageGridSheet extends ConsumerStatefulWidget {
  const ReaderPageGridSheet({
    super.key,
    required this.resources,
    required this.unitId,
    required this.current,
    required this.onSelected,
    this.initialBookmarksOnly = false,
    this.totalPages,
  });

  final List<MediaResource> resources;
  final String unitId;
  final int current;
  final ValueChanged<int> onSelected;

  /// Opened from the "bookmarks" tool, so start filtered instead of asking the
  /// person to find the filter chip.
  final bool initialBookmarksOnly;

  /// Zero explicitly means unknown. Null uses the available resource count for
  /// callers displaying a complete chapter.
  final int? totalPages;

  @override
  ConsumerState<ReaderPageGridSheet> createState() =>
      _ReaderPageGridSheetState();
}

class _ReaderPageGridSheetState extends ConsumerState<ReaderPageGridSheet> {
  late bool _bookmarksOnly;
  bool _scrolledToCurrent = false;

  @override
  void initState() {
    super.initState();
    _bookmarksOnly = widget.initialBookmarksOnly;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final total = widget.resources.length;
    final displayTotal = widget.totalPages ?? (total == 0 ? 1 : total);
    final bookmarks =
        ref.watch(readerBookmarksProvider)[widget.unitId] ?? const <int>[];
    final bookmarkSet = bookmarks.toSet();
    final visible = <int>[
      for (var index = 0; index < total; index++)
        if (!_bookmarksOnly || bookmarkSet.contains(index)) index,
    ];

    return DraggableScrollableSheet(
      initialChildSize: 0.86,
      minChildSize: 0.4,
      maxChildSize: 0.96,
      expand: false,
      builder: (BuildContext context, ScrollController scrollController) {
        _revealCurrent(context, scrollController);
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: BestSpace.sm),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color:
                      theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                BestSpace.xl,
                BestSpace.md,
                BestSpace.sm,
                BestSpace.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.readerPageGrid,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontFamily: BestFontFamily.heading,
                          ),
                        ),
                        Text(
                          displayTotal > 0
                              ? l10n.pageOf(
                                  (widget.current + 1).clamp(1, displayTotal),
                                  displayTotal,
                                )
                              : l10n.readerSavedPage(widget.current + 1),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip:
                        MaterialLocalizations.of(context).closeButtonTooltip,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                BestSpace.xl,
                0,
                BestSpace.xl,
                BestSpace.sm,
              ),
              child: Row(
                children: [
                  ChoiceChip(
                    avatar: Icon(
                      _bookmarksOnly
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                      size: 16,
                    ),
                    label: Text(
                      bookmarks.isEmpty
                          ? l10n.readerBookmarks
                          : '${l10n.readerBookmarks} · ${bookmarks.length}',
                    ),
                    selected: _bookmarksOnly,
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    onSelected: (selected) {
                      setState(() => _bookmarksOnly = selected);
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                BestSpace.xl,
                0,
                BestSpace.xl,
                BestSpace.sm,
              ),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  l10n.readerPageGridHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
              ),
            ),
            const BestHairlineRule(),
            Expanded(
              child: visible.isEmpty
                  ? _EmptyBookmarks(
                      message: bookmarks.isEmpty
                          ? l10n.readerBookmarksEmpty
                          : l10n.readerBookmarksUnavailable)
                  : GridView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(
                        BestSpace.xl,
                        BestSpace.md,
                        BestSpace.xl,
                        BestSpace.xl,
                      ),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: _columns(context),
                        crossAxisSpacing: BestSpace.sm,
                        mainAxisSpacing: BestSpace.md,
                        childAspectRatio: 0.68,
                      ),
                      itemCount: visible.length,
                      itemBuilder: (BuildContext context, int position) {
                        final index = visible[position];
                        return _PageTile(
                          index: index,
                          total: displayTotal,
                          resource: widget.resources[index],
                          current: index == widget.current,
                          bookmarked: bookmarkSet.contains(index),
                          onTap: () => widget.onSelected(index),
                          onLongPress: () => ref
                              .read(readerBookmarksProvider.notifier)
                              .toggle(widget.unitId, index),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  static int _columns(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 900) return 6;
    if (width >= 700) return 5;
    if (width >= 480) return 4;
    return 3;
  }

  /// A long series can put the current page hundreds of rows down. Open the
  /// grid on that page instead of at page one; the offset is estimated from the
  /// same grid geometry used to build the tiles.
  void _revealCurrent(BuildContext context, ScrollController controller) {
    if (_scrolledToCurrent || _bookmarksOnly || widget.current <= 0) return;
    _scrolledToCurrent = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !controller.hasClients) return;
      final width = MediaQuery.sizeOf(context).width;
      final columns = _columns(context);
      final available =
          width - (BestSpace.xl * 2) - (BestSpace.sm * (columns - 1));
      final tileWidth = available / columns;
      final tileHeight = tileWidth / 0.68;
      final row = widget.current ~/ columns;
      final offset = row * (tileHeight + BestSpace.md);
      final max = controller.position.maxScrollExtent;
      if (!max.isFinite) return;
      controller.jumpTo(offset.clamp(0, max).toDouble());
    });
  }
}

class _PageTile extends StatelessWidget {
  const _PageTile({
    required this.index,
    required this.total,
    required this.resource,
    required this.current,
    required this.bookmarked,
    required this.onTap,
    required this.onLongPress,
  });

  final int index;
  final int total;
  final MediaResource resource;
  final bool current;
  final bool bookmarked;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final border =
        current ? theme.colorScheme.primary : theme.colorScheme.outlineVariant;

    return Semantics(
      button: true,
      selected: current,
      label: total > 0
          ? l10n.pageOf(index + 1, total)
          : l10n.readerSavedPage(index + 1),
      child: Material(
        color: theme.colorScheme.surfaceContainerHigh,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BestRadius.md),
          side: BorderSide(
            color: border,
            width: current ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _preview(context),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.78),
                      ],
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(6, 18, 6, 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (bookmarked)
                          const Icon(
                            Icons.bookmark_rounded,
                            color: BestColors.jade,
                            size: 14,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              if (current)
                Positioned(
                  top: 6,
                  left: 6,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(BestRadius.pill),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Icon(
                        Icons.visibility_rounded,
                        size: 11,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _preview(BuildContext context) {
    final fallback = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.image_outlined,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          size: 24,
        ),
      ),
    );

    return switch (resource) {
      ImageResource(:final url, :final headers) => Image.network(
          url,
          headers: headers.isEmpty ? null : headers,
          fit: BoxFit.cover,
          cacheWidth: 320,
          filterQuality: FilterQuality.low,
          errorBuilder: (_, __, ___) => fallback,
        ),
      FileResource(:final path) => Image.file(
          File(path),
          fit: BoxFit.cover,
          cacheWidth: 320,
          filterQuality: FilterQuality.low,
          errorBuilder: (_, __, ___) => fallback,
        ),
      SyntheticPage(:final index) => ColoredBox(
          color: const Color(0xFF1C1C1E),
          child: Center(
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                color: Colors.white38,
                fontFamily: BestFontFamily.mono,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      VideoResource() => ColoredBox(
          color: const Color(0xFF1C1C1E),
          child: Center(
            child: Icon(
              Icons.play_circle_outline_rounded,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              size: 28,
            ),
          ),
        ),
    };
  }
}

class _EmptyBookmarks extends StatelessWidget {
  const _EmptyBookmarks({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(BestSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bookmark_border_rounded,
              size: 40,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: BestSpace.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
