import 'dart:async';

import 'package:best_domain/best_domain.dart';
import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../actions.dart';
import '../l10n/generated/app_localizations.dart';
import '../labels.dart';
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

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Row(children: [
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(l10n.navLibrary, style: BestType.pageTitle(context)),
                    const SizedBox(height: 6),
                    Text(
                        shelfCount == null
                            ? l10n.tagline
                            : l10n.librarySummary(shelfCount),
                        style: BestType.body(context)),
                  ])),
              IconButton(
                tooltip: _grid ? l10n.libraryListView : l10n.libraryGridView,
                onPressed: () {
                  setState(() => _grid = !_grid);
                  ref.read(preferencesProvider)?.setBool('library.grid', _grid);
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
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: LibraryFilter.values.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final filter = LibraryFilter.values[index];
                return ChoiceChip(
                  label: Text(filterLabel(l10n, filter)),
                  selected: query.filter == filter,
                  onSelected: (_) =>
                      ref.read(libraryQueryProvider.notifier).setFilter(filter),
                );
              },
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  if (continueEntries.isNotEmpty &&
                      query.search.isEmpty &&
                      query.filter == LibraryFilter.all)
                    SliverToBoxAdapter(
                      child: _ContinueRail(
                        entries: continueEntries,
                        onOpen: (entry) =>
                            openUnit(context, ref, entry.media, entry.unit),
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

  List<Widget> _shelfSlivers(
    BuildContext context,
    AppLocalizations l10n,
    AsyncValue<List<LibraryEntry>> shelf,
    LibraryQuery query,
  ) {
    return shelf.when<List<Widget>>(
      loading: () => const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
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
          final filtered =
              query.search.isNotEmpty || query.filter != LibraryFilter.all;
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
                        onPressed: () => openGuide(context, ref),
                        icon: const Icon(Icons.menu_book_outlined, size: 18),
                        label: Text(l10n.openGuide),
                      )
                    : OutlinedButton(
                        onPressed: () {
                          _debounce?.cancel();
                          _search.clear();
                          ref.read(libraryQueryProvider.notifier)
                            ..setSearch('')
                            ..setFilter(LibraryFilter.all);
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
                              coverUrl: entry.media.coverUrl,
                              progress: entry.fraction,
                              onTap: () =>
                                  openSeries(context, ref, entry.media)));
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
                    mainAxisExtent: tileWidth * 1.5 + 82,
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final entry = entries[index];
                    return WorkCard(
                      title: entry.media.displayTitle,
                      subtitle: _subtitle(l10n, entry),
                      coverUrl: entry.media.coverUrl,
                      badge: kindLabel(l10n, entry.media.kind),
                      progress: entry.fraction,
                      onTap: () => openSeries(context, ref, entry.media),
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
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ),
            for (final sort in LibrarySort.values)
              ListTile(
                title: Text(sortLabel(l10n, sort)),
                trailing: query.sort == sort
                    ? const Icon(Icons.check, size: 20)
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
