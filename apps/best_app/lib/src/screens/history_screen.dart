import 'package:best_domain/best_domain.dart';
import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../actions.dart';
import '../l10n/generated/app_localizations.dart';
import '../labels.dart';
import '../navigation.dart';
import '../providers.dart';

/// Everything you have read, newest first, in one place.
///
/// Two lists answer two questions: the works you opened and left, and the
/// chapters you are partway through. Both are grouped by day, and each row says
/// what matters for coming back to it: the chapter, the page and the time.
///
/// History also carries the controls Komikku keeps here: filters for unfinished
/// works, works outside the library and favourites, plus multi/range selection
/// and a confirmed batch reset of reading progress.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

enum _HistoryTab { recent, continueReading }

enum _HistoryAction { favorite, addToLibrary, reset, remove }

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  _HistoryTab _tab = _HistoryTab.recent;
  bool _searching = false;
  String _query = '';
  final Set<String> _selected = <String>{};
  int? _anchor;
  bool _busy = false;

  bool get _selecting => _selected.isNotEmpty;

  Future<void> _refresh() async {
    ref.invalidate(historyContinueProvider);
    ref.invalidate(recentProvider);
    ref.invalidate(allLibraryProvider);
    try {
      await Future.wait([
        ref.read(historyContinueProvider.future),
        ref.read(recentProvider.future),
        ref.read(allLibraryProvider.future),
      ]);
    } catch (_) {
      // Rendered inline.
    }
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) _query = '';
    });
  }

  void _clearSelection() {
    if (_selected.isEmpty) return;
    setState(() {
      _selected.clear();
      _anchor = null;
    });
  }

  void _selectAll(List<String> ids) {
    setState(() {
      _selected
        ..clear()
        ..addAll(ids);
      _anchor = ids.isEmpty ? null : ids.length - 1;
    });
  }

  void _invertSelection(List<String> ids) {
    setState(() {
      final visible = ids.toSet();
      final current = Set<String>.from(_selected);
      _selected
        ..clear()
        ..addAll(current.where((id) => !visible.contains(id)))
        ..addAll(visible.where((id) => !current.contains(id)));
      _anchor = null;
    });
  }

  /// Tap toggles one row. A long press selects a row, and a second long press
  /// selects every visible row between the anchor and the pressed row, matching
  /// Komikku's range selection.
  void _toggleRow(String mediaId, int index, List<String> visibleIds,
      {required bool range}) {
    setState(() {
      if (!range) {
        if (!_selected.remove(mediaId)) _selected.add(mediaId);
        _anchor = index;
        if (_selected.isEmpty) _anchor = null;
        return;
      }
      if (_selected.contains(mediaId)) {
        _selected.remove(mediaId);
        _anchor = index;
        if (_selected.isEmpty) _anchor = null;
        return;
      }
      final anchor = _anchor;
      if (anchor == null || anchor >= visibleIds.length) {
        _selected.add(mediaId);
        _anchor = index;
        return;
      }
      final start = anchor < index ? anchor : index;
      final end = anchor < index ? index : anchor;
      for (var i = start; i <= end && i < visibleIds.length; i++) {
        _selected.add(visibleIds[i]);
      }
      _anchor = index;
    });
  }

  Future<bool> _confirm(
    String title,
    String body,
    String actionLabel,
  ) async {
    final l10n = AppLocalizations.of(context);
    final answer = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
    return answer ?? false;
  }

  Future<void> _removeWorks(List<Media> works) async {
    if (works.isEmpty || _busy) return;
    final l10n = AppLocalizations.of(context);
    final count = works.length;
    final confirmed = await _confirm(
      l10n.historyRemoveSelectedTitle(count),
      l10n.historyRemoveSelectedBody,
      l10n.historyRemoveSelected,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    final repository = ref.read(repositoryProvider);
    for (final media in works) {
      await repository.forgetOpened(media.id);
    }
    if (!mounted) return;
    ref.invalidate(recentProvider);
    ref.invalidate(historyContinueProvider);
    _clearSelection();
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.historyRemovedCount(count))),
    );
  }

  Future<void> _resetWorks(List<Media> works) async {
    if (works.isEmpty || _busy) return;
    final l10n = AppLocalizations.of(context);
    final count = works.length;
    final confirmed = await _confirm(
      count == 1 ? l10n.historyResetSingleTitle : l10n.historyResetTitle,
      count == 1 ? l10n.historyResetSingleBody : l10n.historyResetBody(count),
      l10n.historyResetProgress,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    final repository = ref.read(repositoryProvider);
    for (final media in works) {
      await repository.resetProgress(media.id);
    }
    if (!mounted) return;
    ref.invalidate(recentProvider);
    ref.invalidate(historyContinueProvider);
    ref.invalidate(allLibraryProvider);
    _clearSelection();
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.historyResetDone(count))),
    );
  }

  Future<void> _runMenuAction(Media media, _HistoryAction action) async {
    final repository = ref.read(repositoryProvider);
    switch (action) {
      case _HistoryAction.favorite:
        if (!media.favorite && !media.inLibrary) {
          await repository.setInLibrary(media.id, true);
        }
        await repository.setFavorite(media.id, !media.favorite);
        break;
      case _HistoryAction.addToLibrary:
        final added = await addMediaToLibrary(context, ref, media);
        if (!added) return;
        break;
      case _HistoryAction.reset:
        await _resetWorks([media]);
        return;
      case _HistoryAction.remove:
        await _removeWorks([media]);
        return;
    }
    if (!mounted) return;
    ref.invalidate(recentProvider);
    ref.invalidate(historyContinueProvider);
    ref.invalidate(allLibraryProvider);
  }

  Future<void> _showFilters() async {
    final l10n = AppLocalizations.of(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => Consumer(
        builder: (context, ref, _) {
          final filter = ref.watch(historyFilterProvider);
          final controller = ref.read(historyFilterProvider.notifier);
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.historyFilter,
                    style: BestType.sectionTitle(context),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.historyFilterKind,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final option in <(HistoryKindFilter, String)>[
                        (HistoryKindFilter.all, l10n.historyFilterAllKinds),
                        (HistoryKindFilter.reading, l10n.historyFilterReading),
                        (HistoryKindFilter.watching, l10n.historyFilterWatching),
                      ])
                        ChoiceChip(
                          key: ValueKey('history-filter-kind-${option.$1.name}'),
                          label: Text(option.$2),
                          selected: filter.kind == option.$1,
                          onSelected: (_) => controller.setKind(option.$1),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    key: const ValueKey('history-filter-unread'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.historyFilterUnread),
                    value: filter.onlyUnread,
                    onChanged: controller.setOnlyUnread,
                  ),
                  SwitchListTile(
                    key: const ValueKey('history-filter-not-on-shelf'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.historyFilterNotOnShelf),
                    value: filter.onlyNotOnShelf,
                    onChanged: controller.setOnlyNotOnShelf,
                  ),
                  SwitchListTile(
                    key: const ValueKey('history-filter-favorites'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.historyFilterFavorites),
                    value: filter.onlyFavorites,
                    onChanged: controller.setOnlyFavorites,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: filter.isActive ? controller.clear : null,
                        icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
                        label: Text(l10n.historyFilterClear),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        child: Text(l10n.done),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final query = _query.trim();
    final filter = ref.watch(historyFilterProvider);
    final shelf = <String, LibraryEntry>{
      for (final entry
          in ref.watch(allLibraryProvider).value ?? const <LibraryEntry>[])
        entry.media.id: entry,
    };
    final works = (ref.watch(recentProvider).value ?? const <Media>[])
        .where((media) => _matches(media.displayTitle, query))
        .where((media) => _passes(media, filter, shelf))
        .toList(growable: false);
    final entries = (ref.watch(historyContinueProvider).value ??
            const <ContinueEntry>[])
        .where((entry) => _matches(entry.media.displayTitle, query))
        .where((entry) => _passes(entry.media, filter, shelf))
        .toList(growable: false);
    final visibleIds = _tab == _HistoryTab.recent
        ? [for (final media in works) media.id]
        : [for (final entry in entries) entry.media.id];

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 8, 0),
            child: _selecting
                ? Row(
                    children: [
                      IconButton(
                        tooltip: l10n.cancel,
                        onPressed: _clearSelection,
                        icon: const Icon(Icons.close_rounded),
                      ),
                      Expanded(
                        child: Text(
                          l10n.historySelectedCount(_selected.length),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: BestType.sectionTitle(context),
                        ),
                      ),
                      IconButton(
                        tooltip: l10n.historySelectAll,
                        onPressed: () => _selectAll(visibleIds),
                        icon: const Icon(Icons.select_all_rounded),
                      ),
                      IconButton(
                        tooltip: l10n.historyInvertSelection,
                        onPressed: () => _invertSelection(visibleIds),
                        icon: const Icon(Icons.flip_to_back_rounded),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.historyTitle,
                              style: BestType.pageTitle(context),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              l10n.historySubtitle,
                              style: BestType.body(context),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: l10n.historySearch,
                        onPressed: _toggleSearch,
                        icon: Icon(
                          _searching
                              ? Icons.close_rounded
                              : Icons.search_rounded,
                        ),
                      ),
                      IconButton(
                        tooltip: filter.isActive
                            ? l10n.historyFilterActive(filter.activeCount)
                            : l10n.historyFilter,
                        onPressed: _showFilters,
                        icon: Badge(
                          isLabelVisible: filter.isActive,
                          label: Text('${filter.activeCount}'),
                          child: Icon(
                            filter.isActive
                                ? Icons.filter_alt_rounded
                                : Icons.filter_alt_outlined,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: l10n.historySelectAll,
                        onPressed: visibleIds.isEmpty
                            ? null
                            : () => _selectAll(visibleIds),
                        icon: const Icon(Icons.checklist_rounded),
                      ),
                    ],
                  ),
          ),
          AnimatedSize(
            duration: BestMotion.fast,
            alignment: Alignment.topCenter,
            child: _searching && !_selecting
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: TextField(
                      autofocus: true,
                      onChanged: (value) {
                        setState(() {
                          _query = value;
                          _selected.clear();
                          _anchor = null;
                        });
                      },
                      decoration: InputDecoration(
                        hintText: l10n.historySearch,
                        prefixIcon: const Icon(Icons.search_rounded),
                        isDense: true,
                        filled: true,
                        fillColor: theme.colorScheme.surfaceContainerLow,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(BestRadius.pill),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
          if (!_selecting)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: _Segments(
                selected: _tab,
                onSelected: (tab) => setState(() {
                  _tab = tab;
                  _selected.clear();
                  _anchor = null;
                }),
              ),
            ),
          if (filter.isActive && !_selecting)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 2),
              child: Row(
                children: [
                  Icon(
                    Icons.filter_alt_rounded,
                    size: 14,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l10n.historyFilterActive(filter.activeCount),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: ref.read(historyFilterProvider.notifier).clear,
                    child: Text(l10n.historyFilterClear),
                  ),
                ],
              ),
            ),
          Expanded(
            child: switch (_tab) {
              _HistoryTab.continueReading => _ContinueList(
                  entries: entries,
                  query: query,
                  filterActive: filter.isActive,
                  onClearFilters:
                      ref.read(historyFilterProvider.notifier).clear,
                  onRefresh: _refresh,
                  shelf: shelf,
                  selected: _selected,
                  visibleIds: visibleIds,
                  onTap: (media, index) => _toggleRow(
                    media.id,
                    index,
                    visibleIds,
                    range: false,
                  ),
                  onLongPress: (media, index) => _toggleRow(
                    media.id,
                    index,
                    visibleIds,
                    range: true,
                  ),
                  onAction: _runMenuAction,
                ),
              _HistoryTab.recent => _RecentList(
                  works: works,
                  query: query,
                  filterActive: filter.isActive,
                  onClearFilters:
                      ref.read(historyFilterProvider.notifier).clear,
                  onRefresh: _refresh,
                  shelf: shelf,
                  selected: _selected,
                  visibleIds: visibleIds,
                  onTap: (media, index) => _toggleRow(
                    media.id,
                    index,
                    visibleIds,
                    range: false,
                  ),
                  onLongPress: (media, index) => _toggleRow(
                    media.id,
                    index,
                    visibleIds,
                    range: true,
                  ),
                  onAction: _runMenuAction,
                ),
            },
          ),
          if (_selecting)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    if (_tab == _HistoryTab.recent) ...[
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _removeWorks(
                                    works
                                        .where((media) =>
                                            _selected.contains(media.id))
                                        .toList(growable: false),
                                  ),
                          icon: const Icon(Icons.delete_sweep_outlined),
                          label: Text(l10n.historyRemoveSelected),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _resetWorks(_selectedMedia(works, entries)),
                        icon: const Icon(Icons.restart_alt_rounded),
                        label: Text(l10n.historyResetProgress),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Media> _selectedMedia(
    List<Media> works,
    List<ContinueEntry> entries,
  ) {
    final byId = <String, Media>{
      for (final media in works) media.id: media,
      for (final entry in entries) entry.media.id: entry.media,
    };
    return [
      for (final id in _selected)
        if (byId[id] != null) byId[id]!,
    ];
  }
}

bool _matches(String title, String query) =>
    query.isEmpty ||
    SearchText.normalize(title).contains(SearchText.normalize(query));

bool _passes(
  Media media,
  HistoryFilter filter,
  Map<String, LibraryEntry> shelf,
) {
  final entry = shelf[media.id];
  final inLibrary = entry?.media.inLibrary ?? media.inLibrary;
  if (filter.kind == HistoryKindFilter.reading && !media.kind.isReading) {
    return false;
  }
  if (filter.kind == HistoryKindFilter.watching && !media.kind.isWatching) {
    return false;
  }
  if (filter.onlyNotOnShelf && inLibrary) return false;
  if (filter.onlyFavorites && !(entry?.media.favorite ?? media.favorite)) {
    return false;
  }
  if (filter.onlyUnread && (entry == null || entry.unreadUnits <= 0)) {
    return false;
  }
  return true;
}

/// Whole calendar days between [epochMillis] and [now]. UTC midnights keep the
/// count exact across daylight-saving changes.
int _daysAgo(int epochMillis, DateTime now) {
  final date = DateTime.fromMillisecondsSinceEpoch(epochMillis);
  return DateTime.utc(now.year, now.month, now.day)
      .difference(DateTime.utc(date.year, date.month, date.day))
      .inDays;
}

String _dayLabel(AppLocalizations l10n, int daysAgo, int epochMillis) {
  if (daysAgo <= 0) return l10n.historyToday;
  if (daysAgo == 1) return l10n.historyYesterday;
  if (daysAgo < 30) return l10n.historyDaysAgo(daysAgo);
  return shortDate(epochMillis);
}

/// Rows under one header per calendar day. The input is already newest first,
/// so every day is a single run of rows.
List<Widget> _dayRows<T>({
  required AppLocalizations l10n,
  required List<T> items,
  required int Function(T item) millisOf,
  required Widget Function(T item) rowOf,
}) {
  final now = DateTime.now();
  final children = <Widget>[];
  String? shown;
  for (final item in items) {
    final millis = millisOf(item);
    final label = _dayLabel(l10n, _daysAgo(millis, now), millis);
    if (label.isNotEmpty && label != shown) {
      shown = label;
      children.add(_DayHeader(label: label));
    }
    children.add(rowOf(item));
  }
  return children;
}

Widget _searchEmpty(AppLocalizations l10n, String query) => EmptyState(
      icon: Icons.search_off_rounded,
      title: l10n.searchNoMatch(query),
      body: l10n.searchNoMatchBody,
    );

Widget _filterEmpty(
  AppLocalizations l10n,
  VoidCallback onClearFilters,
) =>
    EmptyState(
      icon: Icons.filter_alt_off_rounded,
      title: l10n.historyFilterEmptyTitle,
      body: l10n.historyFilterEmptyBody,
      action: OutlinedButton.icon(
        onPressed: onClearFilters,
        icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
        label: Text(l10n.historyFilterClear),
      ),
    );

class _Segments extends StatelessWidget {
  const _Segments({required this.selected, required this.onSelected});

  final _HistoryTab selected;
  final ValueChanged<_HistoryTab> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final options = <(_HistoryTab, String)>[
      (_HistoryTab.recent, l10n.historyRecent),
      (_HistoryTab.continueReading, l10n.historyContinue),
    ];
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final option = options[index];
          return _SegmentChip(
            label: option.$2,
            selected: option.$1 == selected,
            onTap: () => onSelected(option.$1),
          );
        },
      ),
    );
  }
}

class _SegmentChip extends StatelessWidget {
  const _SegmentChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(BestRadius.pill),
      child: AnimatedContainer(
        duration: BestMotion.fast,
        padding: const EdgeInsets.symmetric(horizontal: 15),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(BestRadius.pill),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          style: theme.textTheme.labelMedium?.copyWith(
            color: selected
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 11.5,
          ),
        ),
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// One work on one line of the list: cover, title, a detail line, an optional
/// progress bar, and a single action at the end.
class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    super.key,
    required this.media,
    required this.detail,
    required this.onTap,
    required this.onLongPress,
    required this.trailing,
    required this.selected,
    this.progress,
  });

  final Media media;
  final String detail;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final Widget trailing;
  final bool selected;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = progress;
    return Material(
      color: selected
          ? theme.colorScheme.primary.withValues(alpha: 0.10)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 4, 8),
          child: Row(
            children: [
              SizedBox(
                width: 52,
                height: 76,
                child: BestCover(
                  title: media.displayTitle,
                  url: media.coverUrl,
                  radius: BestRadius.sm,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      media.displayTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textDirection: autoTextDirection(
                        media.displayTitle,
                        Directionality.of(context),
                      ),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (fraction != null) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(BestRadius.pill),
                        child: BestProgressRule(
                          value: fraction,
                          track: theme.colorScheme.outlineVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyList extends StatelessWidget {
  const _EmptyList({required this.onRefresh, required this.empty});

  final Future<void> Function() onRefresh;
  final Widget empty;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.sizeOf(context).height * 0.12),
          empty,
        ],
      ),
    );
  }
}

Widget _rowTrailing(
  BuildContext context,
  Media media,
  bool inLibrary,
  bool selected,
  ValueChanged<_HistoryAction> onAction,
) {
  final l10n = AppLocalizations.of(context);
  final theme = Theme.of(context);
  if (selected) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Icon(
        Icons.check_circle_rounded,
        color: theme.colorScheme.primary,
      ),
    );
  }
  return PopupMenuButton<_HistoryAction>(
    key: ValueKey('history-menu-${media.id}'),
    tooltip: l10n.historyMoreActions,
    icon: const Icon(Icons.more_vert_rounded),
    onSelected: onAction,
    itemBuilder: (context) => [
      if (inLibrary)
        PopupMenuItem(
          value: _HistoryAction.favorite,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              media.favorite
                  ? Icons.favorite_border_rounded
                  : Icons.favorite_rounded,
            ),
            title: Text(media.favorite ? l10n.unfavorite : l10n.favorite),
          ),
        )
      else
        PopupMenuItem(
          value: _HistoryAction.addToLibrary,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.library_add_outlined),
            title: Text(l10n.addToLibrary),
          ),
        ),
      PopupMenuItem(
        value: _HistoryAction.reset,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.restart_alt_rounded),
          title: Text(l10n.historyResetProgress),
        ),
      ),
      PopupMenuItem(
        value: _HistoryAction.remove,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.delete_outline_rounded),
          title: Text(l10n.historyRemove),
        ),
      ),
    ],
  );
}

class _RecentList extends ConsumerWidget {
  const _RecentList({
    required this.works,
    required this.query,
    required this.filterActive,
    required this.onClearFilters,
    required this.onRefresh,
    required this.shelf,
    required this.selected,
    required this.visibleIds,
    required this.onTap,
    required this.onLongPress,
    required this.onAction,
  });

  final List<Media> works;
  final String query;
  final bool filterActive;
  final VoidCallback onClearFilters;
  final Future<void> Function() onRefresh;
  final Map<String, LibraryEntry> shelf;
  final Set<String> selected;
  final List<String> visibleIds;
  final void Function(Media media, int index) onTap;
  final void Function(Media media, int index) onLongPress;
  final void Function(Media media, _HistoryAction action) onAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    if (works.isEmpty) {
      return _EmptyList(
        onRefresh: onRefresh,
        empty: query.isNotEmpty
            ? _searchEmpty(l10n, query)
            : filterActive
                ? _filterEmpty(l10n, onClearFilters)
                : EmptyState(
                    icon: Icons.history_toggle_off_rounded,
                    title: l10n.historyEmptyTitle,
                    body: l10n.historyRecentEmpty,
                  ),
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        children: _dayRows<Media>(
          l10n: l10n,
          items: works,
          millisOf: (media) => media.lastOpenedAt,
          rowOf: (media) {
            final index = visibleIds.indexOf(media.id);
            final entry = shelf[media.id];
            final unread = entry?.unreadUnits ?? 0;
            final inLibrary = entry?.media.inLibrary ?? media.inLibrary;
            final favorite = entry?.media.favorite ?? media.favorite;
            final current = media.copyWith(
              inLibrary: inLibrary,
              favorite: favorite,
            );
            return _HistoryRow(
              key: ValueKey('history-${media.id}'),
              media: current,
              selected: selected.contains(media.id),
              detail: [
                kindLabel(l10n, media.kind),
                shortTime(media.lastOpenedAt),
                if (unread > 0)
                  l10n.historyUnreadLeft(unread)
                else if (!inLibrary)
                  l10n.historyNotOnShelf,
              ].where((part) => part.isNotEmpty).join(' · '),
              onTap: () {
                if (selected.isEmpty) {
                  openSeries(context, ref, media);
                } else {
                  onTap(media, index);
                }
              },
              onLongPress: () => onLongPress(media, index),
              trailing: _rowTrailing(
                context,
                current,
                inLibrary,
                selected.contains(media.id),
                (action) => onAction(current, action),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ContinueList extends ConsumerWidget {
  const _ContinueList({
    required this.entries,
    required this.query,
    required this.filterActive,
    required this.onClearFilters,
    required this.onRefresh,
    required this.shelf,
    required this.selected,
    required this.visibleIds,
    required this.onTap,
    required this.onLongPress,
    required this.onAction,
  });

  final List<ContinueEntry> entries;
  final String query;
  final bool filterActive;
  final VoidCallback onClearFilters;
  final Future<void> Function() onRefresh;
  final Map<String, LibraryEntry> shelf;
  final Set<String> selected;
  final List<String> visibleIds;
  final void Function(Media media, int index) onTap;
  final void Function(Media media, int index) onLongPress;
  final void Function(Media media, _HistoryAction action) onAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    if (entries.isEmpty) {
      return _EmptyList(
        onRefresh: onRefresh,
        empty: query.isNotEmpty
            ? _searchEmpty(l10n, query)
            : filterActive
                ? _filterEmpty(l10n, onClearFilters)
                : EmptyState(
                    icon: Icons.history_rounded,
                    title: l10n.historyEmptyTitle,
                    body: l10n.historyEmptyBody,
                    action: FilledButton.icon(
                      onPressed: () => context.push(Routes.sources),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: Text(l10n.homeAddSources),
                    ),
                  ),
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        children: _dayRows<ContinueEntry>(
          l10n: l10n,
          items: entries,
          millisOf: (entry) => entry.progress.updatedAt,
          rowOf: (entry) {
            final media = entry.media;
            final index = visibleIds.indexOf(media.id);
            final shelfEntry = shelf[media.id];
            final unread = shelfEntry?.unreadUnits ?? 0;
            final inLibrary = shelfEntry?.media.inLibrary ?? media.inLibrary;
            final favorite = shelfEntry?.media.favorite ?? media.favorite;
            final current = media.copyWith(
              inLibrary: inLibrary,
              favorite: favorite,
            );
            final total = entry.progress.total;
            final fraction = total <= 0
                ? (entry.progress.completed ? 1.0 : 0.0)
                : (entry.progress.position / total).clamp(0.0, 1.0).toDouble();
            return _HistoryRow(
              key: ValueKey('history-continue-${media.id}'),
              media: current,
              selected: selected.contains(media.id),
              detail: [
                '${l10n.menuChaptersShort} ${shortNumber(entry.unit.number)}',
                if (total > 0)
                  l10n.pageOf(
                    (entry.progress.position + 1).clamp(1, total).toInt(),
                    total,
                  ),
                shortTime(entry.progress.updatedAt),
                if (unread > 0) l10n.historyUnreadLeft(unread),
              ].where((part) => part.isNotEmpty).join(' · '),
              progress: fraction,
              onTap: () {
                if (selected.isEmpty) {
                  openUnit(context, ref, media, entry.unit);
                } else {
                  onTap(media, index);
                }
              },
              onLongPress: () => onLongPress(media, index),
              trailing: selected.contains(media.id)
                  ? _rowTrailing(context, current, inLibrary, true, (_) {})
                  : PopupMenuButton<_HistoryAction>(
                      key: ValueKey('history-menu-${media.id}'),
                      tooltip: l10n.historyMoreActions,
                      icon: const Icon(Icons.more_vert_rounded),
                      onSelected: (action) => onAction(current, action),
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: _HistoryAction.reset,
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.restart_alt_rounded),
                            title: Text(l10n.historyResetProgress),
                          ),
                        ),
                      ],
                    ),
            );
          },
        ),
      ),
    );
  }
}
