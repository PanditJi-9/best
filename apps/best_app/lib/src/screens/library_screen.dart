import 'dart:async';

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
import '../reading_card.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;
  late bool _grid;

  /// Selection is keyed by stored id and keeps the row it selected, so a bulk
  /// action never needs to re-read the shelf (and cannot act on a stale list).
  final Map<String, Media> _selected = {};
  bool _selecting = false;

  @override
  void initState() {
    super.initState();
    _grid = ref.read(preferencesProvider)?.getBool('library.grid') ?? true;
    _search.text = ref.read(libraryQueryProvider).search;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    setState(() {});
    _debounce = Timer(const Duration(milliseconds: 240), () {
      ref.read(libraryQueryProvider.notifier).setSearch(value);
    });
  }

  void _startSelection(Media media) {
    setState(() {
      _selecting = true;
      _selected[media.id] = media;
    });
  }

  void _toggleSelection(Media media) {
    setState(() {
      if (_selected.containsKey(media.id)) {
        _selected.remove(media.id);
      } else {
        _selected[media.id] = media;
      }
      if (_selected.isEmpty) _selecting = false;
    });
  }

  void _clearSelection() {
    setState(() {
      _selected.clear();
      _selecting = false;
    });
  }

  void _selectAll(List<LibraryEntry> entries) {
    setState(() {
      _selecting = true;
      _selected
        ..clear()
        ..addEntries(
          entries.map((entry) => MapEntry(entry.media.id, entry.media)),
        );
    });
  }

  void _onOpen(Media media) {
    if (_selecting) {
      _toggleSelection(media);
      return;
    }
    openSeries(context, ref, media);
  }

  /// Pull to refresh means "ask the sources what changed", not "re-run the
  /// query": the shelf is a local database, so a repaint alone would be a lie.
  Future<void> _refresh() async {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(libraryRefreshProvider.notifier);
    await controller.refreshAll();
    ref.invalidate(libraryProvider);
    ref.invalidate(continueProvider);
    ref.invalidate(resumeProvider);
    try {
      await ref.read(libraryProvider.future);
    } catch (_) {
      // The error state is already rendered by the list below.
    }
    if (!mounted) return;
    final progress = ref.read(libraryRefreshProvider);
    controller.clear();
    if (progress.total == 0) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
            content: Text(l10n.refreshDone(progress.done, progress.failed))),
      );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final query = ref.watch(libraryQueryProvider);
    final shelf = ref.watch(libraryProvider);
    final continuing = ref.watch(resumeProvider);
    final continueEntries = continuing.value ?? const <ResumeSlot>[];
    final shelfCount = shelf.value?.length;
    final downloads =
        ref.watch(downloadsProvider).value ?? const <DownloadTask>[];
    final finishedDownloads =
        downloads.where((task) => task.isFinished).toList(growable: false);
    final liveDownloads = downloads
        .where((task) => task.isActive || task.isFailed)
        .toList(growable: false);
    final shelfWorks = <String, Media>{
      for (final entry in shelf.value ?? const <LibraryEntry>[])
        entry.media.id: entry.media,
    };

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: _selecting
                ? Row(children: [
                    IconButton(
                      tooltip: l10n.bulkClear,
                      onPressed: _clearSelection,
                      icon: const Icon(Icons.close_rounded),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${_selected.length} ${l10n.bulkSelected}',
                        style: BestType.sectionTitle(context),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _selectAll(
                        shelf.value ?? const <LibraryEntry>[],
                      ),
                      child: Text(l10n.bulkSelectAll),
                    ),
                  ])
                : Row(children: [
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(l10n.navLibrary,
                              style: BestType.pageTitle(context)),
                          const SizedBox(height: 6),
                          Text(
                              shelfCount == null
                                  ? l10n.tagline
                                  : l10n.librarySummary(shelfCount),
                              style: BestType.body(context)),
                        ])),
                    IconButton(
                      tooltip:
                          _grid ? l10n.libraryListView : l10n.libraryGridView,
                      onPressed: () {
                        setState(() => _grid = !_grid);
                        ref
                            .read(preferencesProvider)
                            ?.setBool('library.grid', _grid);
                      },
                      icon: Icon(_grid
                          ? Icons.view_agenda_outlined
                          : Icons.grid_view_rounded),
                    ),
                    IconButton(
                      tooltip: l10n.sort,
                      onPressed: () => _showSort(context, query),
                      icon: const Icon(Icons.swap_vert),
                    ),
                  ]),
          ),
          if (_selecting)
            _BulkBar(
              onFavorite: _favoriteAll,
              onCategory: _addCategoryToSelection,
              onRemove: _removeAll,
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                onChanged: _onSearch,
                decoration: InputDecoration(
                  hintText: l10n.searchLibrary,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            _search.clear();
                            _onSearch('');
                            setState(() {});
                          },
                        ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 46,
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  // The complete filter list, including categories, lives in
                  // this sheet; the chips are only the four common views.
                  IconButton(
                    tooltip: l10n.libraryFilter,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _showFilters(context, query),
                    icon: Icon(
                      Icons.tune_rounded,
                      size: 20,
                      color: query.filter == LibraryFilter.all
                          ? null
                          : Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsetsDirectional.only(end: 20),
                      children: [
                        for (final filter in const [
                          LibraryFilter.all,
                          LibraryFilter.unread,
                          LibraryFilter.inProgress,
                          LibraryFilter.offline,
                        ]) ...[
                          ChoiceChip(
                            label: Text(filterLabel(l10n, filter)),
                            selected: query.filter == filter,
                            visualDensity: VisualDensity.compact,
                            onSelected: (_) => ref
                                .read(libraryQueryProvider.notifier)
                                .setFilter(filter),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (query.tag != null)
                          InputChip(
                            label: Text(query.tag!),
                            visualDensity: VisualDensity.compact,
                            onDeleted: () => ref
                                .read(libraryQueryProvider.notifier)
                                .setTag(null),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 4),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  if (!_selecting &&
                      continueEntries.isNotEmpty &&
                      query.search.isEmpty &&
                      query.filter == LibraryFilter.all &&
                      query.tag == null)
                    SliverToBoxAdapter(
                      child: _ContinueRail(
                        entries: continueEntries,
                        onOpen: (entry) =>
                            openUnit(context, ref, entry.media, entry.unit),
                      ),
                    ),
                  if (!_selecting && liveDownloads.isNotEmpty)
                    SliverToBoxAdapter(
                      child: _DownloadsBanner(
                        tasks: liveDownloads,
                        onOpen: () => context.push(Routes.downloads),
                      ),
                    ),
                  if (!_selecting &&
                      query.search.isEmpty &&
                      query.filter == LibraryFilter.all &&
                      query.tag == null &&
                      finishedDownloads.isNotEmpty)
                    SliverToBoxAdapter(
                      child: _DownloadedRail(
                        tasks: finishedDownloads,
                        works: shelfWorks,
                        onOpen: (task) => context.push(
                          Routes.reader(
                            sourceId: task.sourceId,
                            url: task.mediaUrl,
                            unitUrl: task.unitUrl,
                          ),
                        ),
                        onManage: () => context.push(Routes.downloads),
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 12)),
                  ..._shelfSlivers(context, l10n, shelf, query),
                  // Breathing room after the last work, above the navigation dock.
                  const SliverToBoxAdapter(child: SizedBox(height: 28)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _favoriteAll() async {
    final l10n = AppLocalizations.of(context);
    final repository = ref.read(repositoryProvider);
    for (final media in _selected.values) {
      if (media.favorite) continue;
      await repository.setFavorite(media.id, true);
    }
    if (!mounted) return;
    _clearSelection();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.bulkFavorited)));
  }

  Future<void> _removeAll() async {
    final l10n = AppLocalizations.of(context);
    final repository = ref.read(repositoryProvider);
    for (final media in _selected.values) {
      await repository.setInLibrary(media.id, false);
    }
    if (!mounted) return;
    _clearSelection();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.bulkRemoved)));
  }

  Future<void> _addCategoryToSelection() async {
    final l10n = AppLocalizations.of(context);
    final name = await _pickCategoryName(context, ref);
    if (name == null || !mounted) return;
    await addTagToWorks(ref, _selected.values, name);
    if (!mounted) return;
    _clearSelection();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.bulkAdded)));
  }

  Future<void> _showFilters(BuildContext context, LibraryQuery query) async {
    final l10n = AppLocalizations.of(context);
    final result = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    l10n.libraryFilter,
                    style: BestType.sectionTitle(context),
                  ),
                ),
              ),
              for (final filter in LibraryFilter.values)
                ListTile(
                  selected: query.filter == filter,
                  title: Text(filterLabel(l10n, filter)),
                  trailing: query.filter == filter
                      ? const Icon(Icons.check_rounded, size: 20)
                      : null,
                  onTap: () => Navigator.of(context).pop(filter),
                ),
              const Divider(height: 12),
              ListTile(
                leading: const Icon(Icons.folder_outlined, size: 20),
                title: Text(l10n.categoryManage),
                onTap: () => Navigator.of(context).pop('categories'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (!mounted || result == null) return;
    if (result == 'categories') {
      if (!context.mounted) return;
      await _showCategories(context);
      return;
    }
    ref.read(libraryQueryProvider.notifier).setFilter(result as LibraryFilter);
  }

  Future<void> _showCategories(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => const _CategoriesSheet(),
    );
  }

  List<Widget> _shelfSlivers(
    BuildContext context,
    AppLocalizations l10n,
    AsyncValue<List<LibraryEntry>> shelf,
    LibraryQuery query,
  ) {
    final registry = ref.watch(sourceRegistryProvider);
    return shelf.when<List<Widget>>(
      loading: () => [
        if (_grid)
          const SliverPosterGridSkeleton()
        else
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: BestLayout.gutter),
              child: RowListSkeleton(),
            ),
          ),
      ],
      error: (error, stack) => [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icon: Icons.error_outline,
            title: l10n.sourceError,
            body: '$error',
            action: FilledButton(
              onPressed: () => ref.invalidate(libraryProvider),
              child: Text(l10n.retry),
            ),
          ),
        ),
      ],
      data: (entries) {
        if (entries.isEmpty) {
          final filtered = query.search.isNotEmpty ||
              query.filter != LibraryFilter.all ||
              query.tag != null;
          return [
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.auto_stories_outlined,
                title:
                    filtered ? l10n.libraryFilterEmpty : l10n.shelfEmptyTitle,
                body: filtered
                    ? l10n.libraryFilterEmptyBody
                    : l10n.shelfEmptyBody,
                action: !filtered
                    ? FilledButton.icon(
                        onPressed: () => context.push(Routes.sources),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: Text(l10n.homeAddSources),
                      )
                    : OutlinedButton(
                        onPressed: () {
                          _debounce?.cancel();
                          _search.clear();
                          ref.read(libraryQueryProvider.notifier)
                            ..setSearch('')
                            ..setFilter(LibraryFilter.all)
                            ..setTag(null);
                          setState(() {});
                        },
                        child: Text(l10n.filterAll),
                      ),
              ),
            ),
          ];
        }

        if (!_grid) {
          return [
            SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList.builder(
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: WorkCard(
                              density: WorkCardDensity.row,
                              title: entry.media.displayTitle,
                              subtitle: _subtitle(l10n, entry),
                              footnote: _footnote(registry, entry.media),
                              coverUrl: entry.media.coverUrl,
                              progress: entry.fraction,
                              selected: _selected.containsKey(entry.media.id),
                              onLongPress: () => _startSelection(entry.media),
                              onTap: () => _onOpen(entry.media)));
                    }))
          ];
        }
        return [
          SliverLayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.crossAxisExtent;
              final columns = (width / 170).floor().clamp(2, 6).toInt();
              final tileWidth = (width - 40 - (columns - 1) * 14) / columns;
              return SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: 22,
                    crossAxisSpacing: 14,
                    mainAxisExtent: tileWidth * 1.5 + 104,
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final entry = entries[index];
                    return WorkCard(
                      title: entry.media.displayTitle,
                      subtitle: _subtitle(l10n, entry),
                      footnote: _footnote(registry, entry.media),
                      coverUrl: entry.media.coverUrl,
                      badge: kindLabel(l10n, entry.media.kind),
                      progress: entry.fraction,
                      selected: _selected.containsKey(entry.media.id),
                      onLongPress: () => _startSelection(entry.media),
                      onTap: () => _onOpen(entry.media),
                    );
                  }, childCount: entries.length),
                ),
              );
            },
          ),
        ];
      },
    );
  }

  String _subtitle(AppLocalizations l10n, LibraryEntry entry) {
    if (entry.totalUnits == 0) {
      return kindLabel(l10n, entry.media.kind);
    }
    return '${entry.completedUnits}/${entry.totalUnits} · ${kindLabel(l10n, entry.media.kind)}';
  }

  /// Where a work lives, as a quiet card line. A source id is a machine name,
  /// so an uninstalled adapter falls back to the id rather than inventing one.
  String _footnote(SourceRegistry registry, Media media) {
    final source = registry.byId(media.ref.sourceId);
    final name = source?.name ?? media.ref.sourceId;
    final language = source?.language ?? '';
    if (language.isEmpty || language == 'all') return name;
    return '$name · ${language.toUpperCase()}';
  }

  Future<void> _showSort(BuildContext context, LibraryQuery query) async {
    final l10n = AppLocalizations.of(context);
    final selected = await showModalBottomSheet<LibrarySort>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  l10n.sort,
                  style: BestType.sectionTitle(context),
                ),
              ),
            ),
            for (final sort in LibrarySort.values)
              ListTile(
                selected: query.sort == sort,
                title: Text(sortLabel(l10n, sort)),
                trailing: query.sort == sort
                    ? const Icon(Icons.check_rounded, size: 20)
                    : null,
                onTap: () => Navigator.of(context).pop(sort),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || selected == null) return;
    ref.read(libraryQueryProvider.notifier).setSort(selected);
  }
}

class _BulkBar extends StatelessWidget {
  const _BulkBar({
    required this.onFavorite,
    required this.onCategory,
    required this.onRemove,
  });

  final VoidCallback onFavorite;
  final VoidCallback onCategory;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 0, 0),
      child: SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            ActionChip(
              avatar: const Icon(Icons.favorite_rounded, size: 17),
              label: Text(l10n.bulkFavorite),
              onPressed: onFavorite,
            ),
            const SizedBox(width: 8),
            ActionChip(
              avatar: const Icon(Icons.create_new_folder_outlined, size: 17),
              label: Text(l10n.categoryAddTo),
              onPressed: onCategory,
            ),
            const SizedBox(width: 8),
            ActionChip(
              avatar: const Icon(Icons.library_add_outlined, size: 17),
              label: Text(l10n.bulkRemove),
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}

/// The category manager: create, rename, hide and delete in one list.
class _CategoriesSheet extends ConsumerWidget {
  const _CategoriesSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final categories =
        ref.watch(libraryCategoriesProvider).value ?? const <CategorySummary>[];
    final hidden = ref.watch(hiddenCategoriesProvider);
    final reveal = ref.watch(revealHiddenProvider);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.categoryManage,
                      style: BestType.sectionTitle(context),
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.categoryNew,
                    onPressed: () => _create(context, ref),
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                l10n.categoryHideNote,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ),
            if (hidden.isNotEmpty)
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                title: Text(l10n.categoryReveal),
                value: reveal,
                onChanged: (value) =>
                    ref.read(revealHiddenProvider.notifier).set(value),
              ),
            Flexible(
              child: categories.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                      child: Text(
                        l10n.categoryNone,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        for (final category in categories)
                          ListTile(
                            contentPadding:
                                const EdgeInsetsDirectional.only(start: 24),
                            leading: Icon(
                              category.hidden
                                  ? Icons.folder_off_outlined
                                  : Icons.folder_outlined,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            title: Text(category.name),
                            subtitle: Text(
                              category.hidden
                                  ? '${l10n.categoryHidden} · '
                                      '${l10n.librarySummary(category.count)}'
                                  : l10n.librarySummary(category.count),
                            ),
                            onTap: () {
                              if (category.hidden) {
                                ref
                                    .read(hiddenCategoriesProvider.notifier)
                                    .setHidden(category.name, false);
                                return;
                              }
                              ref
                                  .read(libraryQueryProvider.notifier)
                                  .setTag(category.name);
                              Navigator.of(context).pop();
                            },
                            trailing: PopupMenuButton<String>(
                              onSelected: (value) => _onAction(
                                context,
                                ref,
                                category.name,
                                value,
                              ),
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: 'rename',
                                  child: Text(l10n.categoryRename),
                                ),
                                PopupMenuItem(
                                  value: category.hidden ? 'show' : 'hide',
                                  child: Text(
                                    category.hidden
                                        ? l10n.categoryShow
                                        : l10n.categoryHide,
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text(l10n.categoryDeleteTitle),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _onAction(
    BuildContext context,
    WidgetRef ref,
    String name,
    String action,
  ) async {
    final l10n = AppLocalizations.of(context);
    switch (action) {
      case 'rename':
        final next = await _askName(
          context,
          title: l10n.categoryRename,
          initial: name,
          submitLabel: l10n.save,
        );
        if (next == null || next == name) return;
        await ref.read(categoriesProvider.notifier).rename(name, next);
        if (ref.read(libraryQueryProvider).tag == name) {
          ref.read(libraryQueryProvider.notifier).setTag(next);
        }
      case 'hide':
        await ref.read(hiddenCategoriesProvider.notifier).setHidden(name, true);
        if (ref.read(libraryQueryProvider).tag == name) {
          ref.read(libraryQueryProvider.notifier).setTag(null);
        }
      case 'show':
        await ref
            .read(hiddenCategoriesProvider.notifier)
            .setHidden(name, false);
      case 'delete':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n.categoryDeleteTitle),
            content: Text(l10n.categoryDeleteBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(l10n.delete),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        await ref.read(categoriesProvider.notifier).remove(name);
        if (ref.read(libraryQueryProvider).tag == name) {
          ref.read(libraryQueryProvider.notifier).setTag(null);
        }
    }
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final name = await _askName(
      context,
      title: l10n.categoryNew,
      submitLabel: l10n.add,
    );
    if (name == null || name.trim().isEmpty) return;
    await ref.read(categoriesProvider.notifier).add(name);
  }
}

/// A name prompt shared by "new category" and "rename".
Future<String?> _askName(
  BuildContext context, {
  required String title,
  String? initial,
  String? submitLabel,
}) async {
  final l10n = AppLocalizations.of(context);
  final controller = TextEditingController(text: initial ?? '');
  controller.selection =
      TextSelection(baseOffset: 0, extentOffset: controller.text.length);
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(hintText: l10n.categoryName),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: Text(submitLabel ?? l10n.add),
        ),
      ],
    ),
  );
  controller.dispose();
  if (name == null) return null;
  final clean = name.trim();
  return clean.isEmpty ? null : clean;
}

/// Existing categories plus a free-text field, so adding to a category never
/// requires leaving the shelf.
Future<String?> _pickCategoryName(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final controller = TextEditingController();
  final categories =
      ref.read(libraryCategoriesProvider).value ?? const <CategorySummary>[];
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.categoryAddTo),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            autofocus: categories.isEmpty,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(hintText: l10n.categoryName),
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
          if (categories.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final category in categories)
                  ActionChip(
                    label: Text(category.name),
                    onPressed: () => Navigator.of(context).pop(category.name),
                  ),
              ],
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: Text(l10n.add),
        ),
      ],
    ),
  );
  controller.dispose();
  if (result == null) return null;
  final clean = result.trim();
  return clean.isEmpty ? null : clean;
}

class _ContinueRail extends StatelessWidget {
  const _ContinueRail({required this.entries, required this.onOpen});

  final List<ResumeSlot> entries;
  final void Function(ResumeSlot entry) onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SectionHeader(title: l10n.continueTitle),
        ),
        for (final entry in entries)
          Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: ReadingCard(slot: entry, onOpen: () => onOpen(entry))),
      ],
    );
  }
}

/// Finished downloads belong to the shelf, not to a second screen. This rail
/// shows what is already readable offline and opens the reader directly.
class _DownloadedRail extends StatelessWidget {
  const _DownloadedRail({
    required this.tasks,
    required this.works,
    required this.onOpen,
    required this.onManage,
  });

  final List<DownloadTask> tasks;
  final Map<String, Media> works;
  final ValueChanged<DownloadTask> onOpen;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final byMedia = <String, DownloadTask>{};
    for (final task in tasks) {
      byMedia.putIfAbsent(task.mediaId, () => task);
    }
    final entries = byMedia.values.toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SectionHeader(
            title: l10n.downloadsFinished,
            actionLabel: l10n.downloadsTitle,
            onAction: onManage,
          ),
        ),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: entries.length,
            separatorBuilder: (context, index) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final task = entries[index];
              final work = works[task.mediaId];
              return SizedBox(
                width: 230,
                child: Material(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(BestRadius.md),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => onOpen(task),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: 54,
                              height: 74,
                              child: work == null
                                  ? ColoredBox(
                                      color: theme.colorScheme.primaryContainer,
                                      child: Icon(
                                        Icons.offline_pin_rounded,
                                        color: theme
                                            .colorScheme.onPrimaryContainer,
                                      ),
                                    )
                                  : BestCover(
                                      title: work.displayTitle,
                                      url: work.coverUrl,
                                    ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  task.mediaTitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  task.unitTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// A quiet strip for downloads that are still moving or failed. It replaces the
/// old second "Downloads" tab: the manager is one tap from the shelf.
class _DownloadsBanner extends StatelessWidget {
  const _DownloadsBanner({required this.tasks, required this.onOpen});

  final List<DownloadTask> tasks;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final done = tasks.fold<int>(0, (sum, task) => sum + task.completed);
    final total = tasks.fold<int>(0, (sum, task) => sum + task.total);
    final failed = tasks.where((task) => task.isFailed).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Material(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(BestRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(BestRadius.md),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            child: Row(
              children: [
                Icon(
                  failed > 0
                      ? Icons.error_outline_rounded
                      : Icons.downloading_rounded,
                  size: 20,
                  color: failed > 0
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        failed > 0
                            ? l10n.downloadFailed
                            : l10n.downloadsInProgress,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (total > 0) ...[
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: (done / total).clamp(0.0, 1.0),
                            minHeight: 5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
