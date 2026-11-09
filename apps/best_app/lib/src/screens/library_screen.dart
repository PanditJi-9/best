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

/// The category registry of the shelf on screen. Manga and anime keep separate
/// lists, so a name made on one shelf never shows up on the other.
ShelfCategoriesController shelfRegistry(WidgetRef ref) {
  final shelf = ref.read(libraryQueryProvider).shelf ?? LibraryShelf.reading;
  return shelf == LibraryShelf.watching
      ? ref.read(watchingCategoriesProvider.notifier)
      : ref.read(categoriesProvider.notifier);
}

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;
  late bool _grid;
  late bool _searchOpen;

  /// Selection is keyed by stored id and keeps the row it selected, so a bulk
  /// action never needs to re-read the shelf (and cannot act on a stale list).
  final Map<String, Media> _selected = {};
  bool _selecting = false;

  @override
  void initState() {
    super.initState();
    _grid = ref.read(preferencesProvider)?.getBool('library.grid') ?? true;
    _search.text = ref.read(libraryQueryProvider).search;
    _searchOpen = _search.text.isNotEmpty;
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

  void _toggleSearch() {
    if (_searchOpen) {
      _debounce?.cancel();
      _search.clear();
      ref.read(libraryQueryProvider.notifier).setSearch('');
    }
    setState(() => _searchOpen = !_searchOpen);
  }

  void _toggleGrid() {
    setState(() => _grid = !_grid);
    ref.read(preferencesProvider)?.setBool('library.grid', _grid);
  }

  void _resetNarrowing() {
    _debounce?.cancel();
    _search.clear();
    ref.read(libraryQueryProvider.notifier)
      ..setSearch('')
      ..setFilter(LibraryFilter.all);
    setState(() {});
  }

  void _switchShelf(LibraryShelf shelf) {
    _clearSelection();
    ref.read(libraryQueryProvider.notifier).setShelf(shelf);
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
    ref.invalidate(libraryTabsProvider);
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
    final tabs = ref.watch(libraryVisibleTabsProvider).value;
    final shelfKind = query.shelf ?? LibraryShelf.reading;
    final filtering = query.filter != LibraryFilter.all;
    final currentTag = query.tag;
    final total = tabs?.total;
    final categories = tabs?.categories ?? const <CategorySummary>[];
    final defaultCount = tabs?.uncategorized ?? 0;

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 8, 0),
            child: _selecting
                ? _selectionHeader(l10n, shelf)
                : _header(context, l10n, query, total),
          ),
          if (_selecting)
            _BulkBar(
              onFavorite: _favoriteAll,
              onCategory: _addCategoryToSelection,
              onRemove: _removeAll,
              onRemoveFromCategory: currentTag == null
                  ? null
                  : () => _removeFromCategory(currentTag),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: SegmentedButton<LibraryShelf>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: LibraryShelf.reading,
                    label: Text(l10n.kindManga),
                    icon: const Icon(Icons.menu_book_outlined, size: 18),
                  ),
                  ButtonSegment(
                    value: LibraryShelf.watching,
                    label: Text(l10n.kindAnime),
                    icon: const Icon(Icons.movie_outlined, size: 18),
                  ),
                ],
                selected: {shelfKind},
                onSelectionChanged: (value) => _switchShelf(value.first),
              ),
            ),
            const SizedBox(height: 8),
            _ShelfTabs(
              defaultLabel: l10n.categoryDefault,
              defaultCount: defaultCount,
              defaultSelected: query.uncategorized && currentTag == null,
              categories: categories,
              selectedTag: currentTag,
              onDefault: () =>
                  ref.read(libraryQueryProvider.notifier).setUncategorized(),
              onCategory: (name) =>
                  ref.read(libraryQueryProvider.notifier).setTag(name),
              onCategoryLongPress: _showTabActions,
              onManage: () => _showCategories(context),
              manageLabel: l10n.categoryManage,
            ),
            if (_searchOpen)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: TextField(
                  controller: _search,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onChanged: _onSearch,
                  decoration: InputDecoration(
                    hintText: l10n.searchLibrary,
                    helperText: l10n.librarySearchHint,
                    helperMaxLines: 2,
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
            if (filtering)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: Wrap(
                  children: [
                    InputChip(
                      label: Text(filterLabel(l10n, query.filter)),
                      visualDensity: VisualDensity.compact,
                      onDeleted: () => ref
                          .read(libraryQueryProvider.notifier)
                          .setFilter(LibraryFilter.all),
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
                  ..._shelfSlivers(
                      context, l10n, shelf, query, total, shelfKind),
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

  Widget _header(
    BuildContext context,
    AppLocalizations l10n,
    LibraryQuery query,
    int? total,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final filtering = query.filter != LibraryFilter.all;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.navLibrary, style: BestType.pageTitle(context)),
              const SizedBox(height: 4),
              Text(
                total == null ? l10n.tagline : l10n.librarySummary(total),
                style: BestType.body(context),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: l10n.searchLibrary,
          onPressed: _toggleSearch,
          icon: Icon(
            _searchOpen ? Icons.search_off_rounded : Icons.search_rounded,
            color: _searchOpen ? scheme.primary : null,
          ),
        ),
        IconButton(
          tooltip: l10n.libraryFilter,
          onPressed: () => _showFilters(context, query),
          icon: Icon(
            Icons.tune_rounded,
            color: filtering ? scheme.primary : null,
          ),
        ),
        IconButton(
          tooltip: _grid ? l10n.libraryListView : l10n.libraryGridView,
          onPressed: _toggleGrid,
          icon: Icon(
            _grid ? Icons.view_agenda_outlined : Icons.grid_view_rounded,
          ),
        ),
        IconButton(
          tooltip: l10n.sort,
          onPressed: () => _showSort(context, query),
          icon: const Icon(Icons.swap_vert),
        ),
      ],
    );
  }

  Widget _selectionHeader(
    AppLocalizations l10n,
    AsyncValue<List<LibraryEntry>> shelf,
  ) {
    return Row(
      children: [
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
          onPressed: () => _selectAll(shelf.value ?? const <LibraryEntry>[]),
          child: Text(l10n.bulkSelectAll),
        ),
      ],
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

  Future<void> _removeFromCategory(String tag) async {
    final l10n = AppLocalizations.of(context);
    await removeTagFromWorks(ref, _selected.values, tag);
    if (!mounted) return;
    _clearSelection();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.bulkRemovedFromCategory)));
  }

  /// Long press on a category tab: the same actions as the manager, one tap
  /// away from the tab itself.
  Future<void> _showTabActions(CategorySummary category) async {
    final l10n = AppLocalizations.of(context);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
              child: Text(
                category.name,
                style: BestType.sectionTitle(context),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined, size: 20),
              title: Text(l10n.categoryRename),
              onTap: () => Navigator.of(sheetContext).pop('rename'),
            ),
            ListTile(
              leading: Icon(
                category.hidden
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 20,
              ),
              title: Text(
                category.hidden ? l10n.categoryShow : l10n.categoryHide,
              ),
              onTap: () => Navigator.of(sheetContext)
                  .pop(category.hidden ? 'show' : 'hide'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, size: 20),
              title: Text(l10n.categoryDeleteTitle),
              onTap: () => Navigator.of(sheetContext).pop('delete'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    await runCategoryAction(context, ref, category.name, action);
  }

  Future<void> _showFilters(BuildContext context, LibraryQuery query) async {
    final l10n = AppLocalizations.of(context);
    final result = await showModalBottomSheet<LibraryFilter>(
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
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (!mounted || result == null) return;
    ref.read(libraryQueryProvider.notifier).setFilter(result);
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
    int? total,
    LibraryShelf shelfKind,
  ) {
    final registry = ref.watch(sourceRegistryProvider);
    return shelf.when<List<Widget>>(
      // Switching tabs keeps the cards on screen until the new ones arrive,
      // instead of flashing the skeleton on every tap.
      skipLoadingOnReload: true,
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
          return [
            SliverFillRemaining(
              hasScrollBody: false,
              child: _emptyState(context, l10n, query, total, shelfKind),
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
                      onTap: () => _onOpen(entry.media),
                    ),
                  );
                },
              ),
            ),
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
                      // Unread chapters, the way a reader counts what is left.
                      badge: entry.unreadUnits > 0
                          ? '${entry.unreadUnits}'
                          : null,
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

  /// One empty state per situation: nothing at all, a search or filter that
  /// hides everything, the Default tab once every work has a category, or a
  /// category tab with no works yet.
  Widget _emptyState(
    BuildContext context,
    AppLocalizations l10n,
    LibraryQuery query,
    int? total,
    LibraryShelf shelfKind,
  ) {
    final narrowed =
        query.search.isNotEmpty || query.filter != LibraryFilter.all;
    if (narrowed) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: l10n.libraryFilterEmpty,
        body: l10n.libraryFilterEmptyBody,
        action: OutlinedButton(
          onPressed: _resetNarrowing,
          child: Text(l10n.filterAll),
        ),
      );
    }
    if ((total ?? 0) == 0) {
      return EmptyState(
        icon: shelfKind == LibraryShelf.watching
            ? Icons.movie_outlined
            : Icons.menu_book_outlined,
        title: l10n.shelfEmptyTitle,
        body: l10n.shelfEmptyBody,
        action: FilledButton.icon(
          onPressed: () => context.push(Routes.sources),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text(l10n.homeAddSources),
        ),
      );
    }
    if (query.uncategorized && query.tag == null) {
      return EmptyState(
        icon: Icons.done_all_rounded,
        title: l10n.libraryAllCategorized,
        body: l10n.libraryAllCategorizedBody,
      );
    }
    return EmptyState(
      icon: Icons.folder_open_outlined,
      title: l10n.libraryTabEmpty,
      body: l10n.libraryTabEmptyBody,
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

/// Every action a category can take, shared by the manager and the tab's long
/// press menu. Hiding or deleting the category on screen moves the person to
/// Default, never to a list of every work.
Future<void> runCategoryAction(
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
      await shelfRegistry(ref).rename(name, next);
      if (ref.read(libraryQueryProvider).tag == name) {
        ref.read(libraryQueryProvider.notifier).setTag(next);
      }
    case 'hide':
      await ref.read(hiddenCategoriesProvider.notifier).setHidden(name, true);
      if (ref.read(libraryQueryProvider).tag == name) {
        ref.read(libraryQueryProvider.notifier).setUncategorized();
      }
    case 'show':
      await ref.read(hiddenCategoriesProvider.notifier).setHidden(name, false);
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
      await shelfRegistry(ref).remove(name);
      if (ref.read(libraryQueryProvider).tag == name) {
        ref.read(libraryQueryProvider.notifier).setUncategorized();
      }
  }
}

class _BulkBar extends StatelessWidget {
  const _BulkBar({
    required this.onFavorite,
    required this.onCategory,
    required this.onRemove,
    this.onRemoveFromCategory,
  });

  final VoidCallback onFavorite;
  final VoidCallback onCategory;
  final VoidCallback onRemove;

  /// Only offered while a category tab is open: takes the selection out of it
  /// and leaves the works in every other category they belong to.
  final VoidCallback? onRemoveFromCategory;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final removeFromCategory = onRemoveFromCategory;
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
            if (removeFromCategory != null) ...[
              ActionChip(
                avatar: const Icon(Icons.folder_off_outlined, size: 17),
                label: Text(l10n.bulkRemoveFromCategory),
                onPressed: removeFromCategory,
              ),
              const SizedBox(width: 8),
            ],
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
                              onSelected: (value) => runCategoryAction(
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

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final name = await _askName(
      context,
      title: l10n.categoryNew,
      submitLabel: l10n.add,
    );
    if (name == null || name.trim().isEmpty) return;
    await shelfRegistry(ref).add(name);
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
/// requires leaving the shelf. Hidden categories are offered only once revealed.
Future<String?> _pickCategoryName(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final controller = TextEditingController();
  final reveal = ref.read(revealHiddenProvider);
  final categories = [
    for (final category
        in ref.read(libraryCategoriesProvider).value ?? const <CategorySummary>[])
      if (reveal || !category.hidden) category,
  ];
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

/// The shelf's tab strip: Default first, then each category with its count.
/// The selected tab is scrolled into view whenever the selection changes.
class _ShelfTabs extends StatefulWidget {
  const _ShelfTabs({
    required this.defaultLabel,
    required this.defaultCount,
    required this.defaultSelected,
    required this.categories,
    required this.selectedTag,
    required this.onDefault,
    required this.onCategory,
    required this.onCategoryLongPress,
    required this.onManage,
    required this.manageLabel,
  });

  final String defaultLabel;
  final int defaultCount;
  final bool defaultSelected;
  final List<CategorySummary> categories;
  final String? selectedTag;
  final VoidCallback onDefault;
  final ValueChanged<String> onCategory;
  final ValueChanged<CategorySummary> onCategoryLongPress;
  final VoidCallback onManage;
  final String manageLabel;

  @override
  State<_ShelfTabs> createState() => _ShelfTabsState();
}

class _ShelfTabsState extends State<_ShelfTabs> {
  static const String _defaultId = 'default';

  /// One key per tab, so the strip can find the selected tab's position.
  final Map<String, GlobalKey> _keys = {};

  GlobalKey _keyFor(String id) => _keys.putIfAbsent(id, () => GlobalKey());

  String? get _selectedId {
    if (widget.defaultSelected) return _defaultId;
    final tag = widget.selectedTag;
    return tag == null ? null : 'category:$tag';
  }

  @override
  void initState() {
    super.initState();
    _revealSelected();
  }

  @override
  void didUpdateWidget(covariant _ShelfTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.defaultSelected != widget.defaultSelected ||
        oldWidget.selectedTag != widget.selectedTag) {
      _revealSelected();
    }
  }

  /// Only when the selection changes, so a person scrolling the strip by hand
  /// is never pulled back while the counts refresh.
  void _revealSelected() {
    final id = _selectedId;
    if (id == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final tabContext = _keys[id]?.currentContext;
      if (tabContext == null || !tabContext.mounted) return;
      Scrollable.ensureVisible(
        tabContext,
        alignment: 0.5,
        duration: BestMotion.fast,
        curve: BestMotion.curve,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                _ShelfTab(
                  key: _keyFor(_defaultId),
                  label: widget.defaultLabel,
                  count: widget.defaultCount,
                  selected: widget.defaultSelected,
                  onTap: widget.onDefault,
                ),
                for (final category in widget.categories)
                  _ShelfTab(
                    key: _keyFor('category:${category.name}'),
                    label: category.name,
                    count: category.count,
                    selected: widget.selectedTag == category.name,
                    dimmed: category.hidden,
                    onTap: () => widget.onCategory(category.name),
                    onLongPress: () => widget.onCategoryLongPress(category),
                  ),
              ],
            ),
          ),
        ),
        IconButton(
          tooltip: widget.manageLabel,
          onPressed: widget.onManage,
          icon: const Icon(Icons.folder_outlined),
        ),
      ],
    );
  }
}

class _ShelfTab extends StatelessWidget {
  const _ShelfTab({
    super.key,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.onLongPress,
    this.dimmed = false,
  });

  final String label;
  final int count;
  final bool selected;
  final bool dimmed;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      label: '$label, $count',
      child: Padding(
        padding: const EdgeInsetsDirectional.only(end: 20),
        child: Opacity(
          opacity: dimmed ? 0.5 : 1,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
              child: IntrinsicWidth(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: color,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 6),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: selected
                                ? scheme.primaryContainer
                                : scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 1,
                            ),
                            child: Text(
                              '$count',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: selected
                                    ? scheme.onPrimaryContainer
                                    : scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    AnimatedContainer(
                      duration: BestMotion.fast,
                      curve: BestMotion.curve,
                      height: 3,
                      decoration: BoxDecoration(
                        color: selected ? scheme.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
