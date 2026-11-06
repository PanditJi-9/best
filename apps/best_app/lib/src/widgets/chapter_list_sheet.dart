import 'dart:math' as math;

import 'package:best_domain/best_domain.dart';
import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';

import '../labels.dart';
import '../l10n/generated/app_localizations.dart';

/// A bottom sheet that lists all chapters/units of the current work, letting
/// the reader jump to any chapter without leaving the reader screen.
///
/// Long series need more than a scrollbar: the field narrows by title or
/// number, and the sort action flips between reading order and newest first.
class ChapterListSheet extends StatefulWidget {
  const ChapterListSheet({
    super.key,
    required this.units,
    required this.currentUnitId,
    required this.onSelected,
    this.workTitle,
    this.initialUnitId,
  });

  final List<MediaUnit> units;
  final String currentUnitId;
  final ValueChanged<MediaUnit> onSelected;
  final String? workTitle;
  final String? initialUnitId;

  @override
  State<ChapterListSheet> createState() => _ChapterListSheetState();
}

class _ChapterListSheetState extends State<ChapterListSheet> {
  final TextEditingController _search = TextEditingController();
  String _query = '';
  bool _descending = false;
  bool _pendingScroll = true;
  int _scrollRevision = 0;
  String? _scrollTarget;

  @override
  void initState() {
    super.initState();
    _scrollTarget = widget.initialUnitId ?? widget.currentUnitId;
  }

  void _searchFor(String query) {
    setState(() {
      _query = query;
      _scrollTarget = null;
      _pendingScroll = true;
      _scrollRevision++;
    });
  }

  void _revealCurrent() {
    FocusScope.of(context).unfocus();
    _search.clear();
    setState(() {
      _query = '';
      _scrollTarget = widget.currentUnitId;
      _pendingScroll = true;
      _scrollRevision++;
    });
  }

  void _scrollAfterLayout(
      ScrollController controller, List<MediaUnit> units, double rowExtent) {
    if (!_pendingScroll) return;
    _pendingScroll = false;
    final revision = _scrollRevision;
    final index = units.indexWhere((unit) => unit.id == _scrollTarget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || revision != _scrollRevision || !controller.hasClients) {
        return;
      }
      final offset = index < 0
          ? 0.0
          : index * rowExtent - controller.position.viewportDimension * 0.3;
      controller.jumpTo(offset.clamp(controller.position.minScrollExtent,
          controller.position.maxScrollExtent));
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<MediaUnit> get _visible {
    return UnitNavigation.visible(widget.units,
        query: _query, sort: _descending ? UnitSort.newest : UnitSort.oldest);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final visible = _visible;
    final units = UnitNavigation.readingOrder(widget.units);
    final episodes = units.isNotEmpty && units.first.kind == UnitKind.episode;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final availableHeight = MediaQuery.sizeOf(context).height - keyboard;
    final compact = availableHeight < 400;
    final rowExtent = math.max(
        72.0,
        MediaQuery.textScalerOf(context)
                    .scale(theme.textTheme.bodyMedium?.fontSize ?? 14) *
                3 +
            24);
    final hasCurrent = units.any((unit) => unit.id == widget.currentUnitId);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: DraggableScrollableSheet(
          initialChildSize: compact ? 0.95 : 0.72,
          minChildSize: compact ? 0.9 : 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (BuildContext context, ScrollController scrollController) {
            _scrollAfterLayout(scrollController, visible, rowExtent);
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: BestSpace.sm),
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                if (availableHeight >= 160)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      BestSpace.xl,
                      BestSpace.lg,
                      BestSpace.sm,
                      BestSpace.md,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                episodes ? l10n.episodes : l10n.chapters,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  fontFamily: BestFontFamily.heading,
                                ),
                              ),
                              if (widget.workTitle != null && !compact)
                                Text(
                                  widget.workTitle!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (hasCurrent)
                          IconButton(
                            key: const ValueKey('chapter-picker-current'),
                            tooltip: episodes
                                ? l10n.readerCurrentEpisode
                                : l10n.readerCurrentChapter,
                            onPressed: _revealCurrent,
                            icon:
                                const Icon(Icons.my_location_rounded, size: 20),
                          ),
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: BestPillBadge(
                            label: _query.isEmpty
                                ? '${units.length}'
                                : '${visible.length}/${units.length}',
                            tone: BestTone.neutral,
                            compact: true,
                            icon: Icons.list_rounded,
                          ),
                        ),
                        IconButton(
                          tooltip: _descending
                              ? l10n.readerSortOldest
                              : l10n.readerSortNewest,
                          onPressed: () {
                            setState(() {
                              _descending = !_descending;
                              _scrollTarget = widget.currentUnitId;
                              _pendingScroll = true;
                              _scrollRevision++;
                            });
                          },
                          icon: const Icon(Icons.swap_vert_rounded, size: 20),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    BestSpace.xl,
                    0,
                    BestSpace.xl,
                    availableHeight < 160 ? 0 : BestSpace.md,
                  ),
                  child: TextField(
                    key: const ValueKey('chapter-picker-search'),
                    controller: _search,
                    textInputAction: TextInputAction.search,
                    onChanged: _searchFor,
                    decoration: InputDecoration(
                      hintText: episodes
                          ? l10n.seriesEpisodeSearch
                          : l10n.seriesChapterSearch,
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: MaterialLocalizations.of(context)
                                  .closeButtonTooltip,
                              onPressed: () {
                                _search.clear();
                                _searchFor('');
                              },
                              icon: const Icon(Icons.close_rounded, size: 18),
                            ),
                      isDense: true,
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHigh,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(BestRadius.md),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const BestHairlineRule(),
                Expanded(
                  child: visible.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(BestSpace.xl),
                            child: Text(
                              l10n.seriesNoMatch,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                height: 1.5,
                              ),
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: scrollController,
                          itemExtent: rowExtent,
                          padding: const EdgeInsets.only(bottom: BestSpace.xl),
                          itemCount: visible.length,
                          itemBuilder: (BuildContext context, int index) {
                            final unit = visible[index];
                            final isCurrent = unit.id == widget.currentUnitId;

                            return Semantics(
                              key: ValueKey('chapter-picker-${unit.id}'),
                              selected: isCurrent,
                              child: Material(
                                color: isCurrent
                                    ? theme.colorScheme.primary.withValues(
                                        alpha: BestAlpha.toneContainer)
                                    : Colors.transparent,
                                child: InkWell(
                                  onTap: isCurrent
                                      ? null
                                      : () => widget.onSelected(unit),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: BestSpace.xl,
                                      vertical: BestSpace.md,
                                    ),
                                    child: Row(children: [
                                      Container(
                                        width: 48,
                                        height: 36,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: isCurrent
                                              ? theme.colorScheme.primary
                                                  .withValues(
                                                      alpha: BestAlpha
                                                          .toneContainer)
                                              : theme.colorScheme
                                                  .surfaceContainerHigh,
                                          borderRadius: BorderRadius.circular(
                                              BestRadius.sm),
                                        ),
                                        child: Text(
                                          unit.number.isFinite &&
                                                  unit.number >= 0
                                              ? shortNumber(unit.number)
                                              : '—',
                                          style: TextStyle(
                                            fontFamily: BestFontFamily.mono,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: isCurrent
                                                ? theme.colorScheme.primary
                                                : theme.colorScheme
                                                    .onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: BestSpace.md),
                                      Expanded(
                                          child: Text(
                                        unit.displayTitle,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                          height: 1.5,
                                          fontWeight: isCurrent
                                              ? FontWeight.w700
                                              : null,
                                          color: isCurrent
                                              ? theme.colorScheme.primary
                                              : null,
                                        ),
                                      )),
                                      if (isCurrent) ...[
                                        const SizedBox(width: BestSpace.sm),
                                        Icon(Icons.play_circle_filled_rounded,
                                            size: 18,
                                            color: theme.colorScheme.primary),
                                      ],
                                    ]),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
