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
  });

  final List<MediaUnit> units;
  final String currentUnitId;
  final ValueChanged<MediaUnit> onSelected;
  final String? workTitle;

  @override
  State<ChapterListSheet> createState() => _ChapterListSheetState();
}

class _ChapterListSheetState extends State<ChapterListSheet> {
  final TextEditingController _search = TextEditingController();
  String _query = '';
  bool _descending = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<MediaUnit> get _visible {
    final query = _query.trim().toLowerCase();
    final filtered = widget.units.where((unit) {
      if (query.isEmpty) return true;
      return unit.displayTitle.toLowerCase().contains(query) ||
          shortNumber(unit.number).contains(query);
    }).toList();
    if (_descending) return filtered.reversed.toList();
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final visible = _visible;

    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (BuildContext context, ScrollController scrollController) {
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
                          l10n.chapters,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontFamily: BestFontFamily.heading,
                          ),
                        ),
                        if (widget.workTitle != null)
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
                  BestPillBadge(
                    label: _query.isEmpty
                        ? '${widget.units.length}'
                        : '${visible.length}/${widget.units.length}',
                    tone: BestTone.neutral,
                    compact: true,
                    icon: Icons.list_rounded,
                  ),
                  IconButton(
                    tooltip: _descending
                        ? l10n.readerSortOldest
                        : l10n.readerSortNewest,
                    onPressed: () {
                      setState(() => _descending = !_descending);
                    },
                    icon: const Icon(Icons.swap_vert_rounded, size: 20),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                BestSpace.xl,
                0,
                BestSpace.xl,
                BestSpace.md,
              ),
              child: TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: l10n.readerChapterSearch,
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: MaterialLocalizations.of(context)
                              .closeButtonTooltip,
                          onPressed: () {
                            _search.clear();
                            setState(() => _query = '');
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
                          l10n.readerNoChapterMatch,
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
                      padding: const EdgeInsets.only(bottom: BestSpace.xl),
                      itemCount: visible.length,
                      itemBuilder: (BuildContext context, int index) {
                        final unit = visible[index];
                        final isCurrent = unit.id == widget.currentUnitId;

                        return Material(
                          color: isCurrent
                              ? theme.colorScheme.primary.withValues(
                                  alpha: BestAlpha.toneContainer,
                                )
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
                              child: Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: isCurrent
                                          ? theme.colorScheme.primary
                                              .withValues(
                                              alpha: 0.16,
                                            )
                                          : theme
                                              .colorScheme.surfaceContainerHigh,
                                      borderRadius:
                                          BorderRadius.circular(BestRadius.sm),
                                    ),
                                    child: Text(
                                      shortNumber(unit.number),
                                      style: TextStyle(
                                        fontFamily: BestFontFamily.mono,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: isCurrent
                                            ? theme.colorScheme.primary
                                            : theme
                                                .colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: BestSpace.md),
                                  Expanded(
                                    child: Text(
                                      unit.displayTitle,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          theme.textTheme.bodyMedium?.copyWith(
                                        fontWeight:
                                            isCurrent ? FontWeight.w700 : null,
                                        color: isCurrent
                                            ? theme.colorScheme.primary
                                            : null,
                                      ),
                                    ),
                                  ),
                                  if (isCurrent) ...[
                                    const SizedBox(width: BestSpace.sm),
                                    Icon(
                                      Icons.play_circle_filled_rounded,
                                      size: 18,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ],
                                ],
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
    );
  }
}
