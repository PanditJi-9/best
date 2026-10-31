import 'dart:async';

import 'package:best_domain/best_domain.dart';
import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../actions.dart';
import '../l10n/generated/app_localizations.dart';
import '../labels.dart';
import '../providers.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;

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

  Future<void> _refresh() async {
    ref.invalidate(libraryProvider);
    ref.invalidate(continueProvider);
    try {
      await ref.read(libraryProvider.future);
    } catch (_) {
      // The error state is already rendered by the list below.
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final query = ref.watch(libraryQueryProvider);
    final shelf = ref.watch(libraryProvider);
    final continuing = ref.watch(continueProvider);
    final continueEntries = continuing.value ?? const <ContinueEntry>[];
    final shelfCount = shelf.value?.length;
    final theme = Theme.of(context);

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 12, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.appName,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.2,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l10n.tagline,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: l10n.sort,
                  onPressed: () => _showSort(context, query),
                  icon: const Icon(Icons.swap_vert),
                ),
              ],
            ),
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
                  if (continueEntries.isNotEmpty)
                    SliverToBoxAdapter(
                      child: _ContinueRail(
                        entries: continueEntries,
                        onOpen: (entry) =>
                            openUnit(context, ref, entry.media, entry.unit),
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: SectionHeader(
                        title: l10n.navLibrary,
                        trailing: shelfCount == null
                            ? null
                            : Text(
                                '$shelfCount',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                      ),
                    ),
                  ),
                  ..._shelfSlivers(context, l10n, shelf, query),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
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
          return [
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.auto_stories_outlined,
                title: query.search.isEmpty
                    ? l10n.shelfEmptyTitle
                    : l10n.nothingHere,
                body: query.search.isEmpty
                    ? l10n.shelfEmptyBody
                    : l10n.nothingHereBody,
                action: query.search.isEmpty
                    ? FilledButton.icon(
                        onPressed: () => openGuide(context, ref),
                        icon: const Icon(Icons.menu_book_outlined, size: 18),
                        label: Text(l10n.openGuide),
                      )
                    : null,
              ),
            ),
          ];
        }

        final width = MediaQuery.sizeOf(context).width;
        final columns = (width / 170).floor().clamp(2, 6);
        final tileWidth = (width - 40 - (columns - 1) * 14) / columns;

        return [
          SliverPadding(
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
                return MediaCard(
                  title: entry.media.displayTitle,
                  subtitle: _subtitle(l10n, entry),
                  coverUrl: entry.media.coverUrl,
                  badge: kindLabel(l10n, entry.media.kind),
                  progress: entry.fraction,
                  onTap: () => openSeries(context, ref, entry.media),
                );
              }, childCount: entries.length),
            ),
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

String _progressLabel(AppLocalizations l10n, ContinueEntry entry) {
  if (entry.media.kind.isWatching) {
    if (entry.progress.total <= 0) return l10n.continueWatching;
    return l10n.watchProgress(
      formatClock(entry.progress.position),
      formatClock(entry.progress.total),
    );
  }
  if (entry.progress.total <= 0) return l10n.continueReading;
  return l10n.pageOf(
    (entry.progress.position + 1).clamp(1, entry.progress.total),
    entry.progress.total,
  );
}

class _ContinueRail extends StatelessWidget {
  const _ContinueRail({required this.entries, required this.onOpen});

  final List<ContinueEntry> entries;
  final void Function(ContinueEntry entry) onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SectionHeader(title: l10n.continueTitle),
        ),
        SizedBox(
          height: 132,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: entries.length,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final entry = entries[index];
              return SizedBox(
                width: 286,
                child: Material(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => onOpen(entry),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 76,
                            height: 112,
                            child: BestCover(
                              title: entry.media.displayTitle,
                              url: entry.media.coverUrl,
                              radius: 12,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  entry.media.displayTitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    height: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  entry.unit.displayTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(99),
                                  child: LinearProgressIndicator(
                                    value: entry.progress.fraction,
                                    minHeight: 4,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _progressLabel(l10n, entry),
                                  style: theme.textTheme.labelSmall?.copyWith(
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
