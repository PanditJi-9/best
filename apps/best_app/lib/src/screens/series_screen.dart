import 'package:best_domain/best_domain.dart';
import 'package:best_ui/best_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../actions.dart';
import '../l10n/generated/app_localizations.dart';
import '../labels.dart';
import '../navigation.dart';
import '../providers.dart';
import '../progress_label.dart';
import '../widgets/chapter_list_sheet.dart';

class SeriesScreen extends ConsumerWidget {
  const SeriesScreen({super.key, required this.sourceId, required this.url});

  final String sourceId;
  final String url;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final key = (sourceId: sourceId, url: url);
    final data = ref.watch(seriesProvider(key));
    final stored = ref.watch(localWorkProvider(mediaIdOf(sourceId, url))).value;

    Widget body(SeriesData series,
            {bool refreshing = false,
            bool cached = false,
            bool sourceMissing = false}) =>
        _SeriesBody(
          key: ValueKey(series.media.id),
          data: SeriesData(
            media: stored?.media ?? series.media,
            units: series.units,
            progress: stored?.progress ?? series.progress,
          ),
          seriesKey: key,
          refreshing: refreshing,
          cached: cached,
          sourceMissing: sourceMissing,
        );

    return data.when(
      loading: () => stored == null
          ? const _SeriesSkeleton()
          : body(stored, refreshing: true, cached: true),
      error: (error, stack) => stored != null
          ? body(stored,
              cached: true, sourceMissing: error is SourceNotInstalled)
          : Scaffold(
              appBar: AppBar(),
              body: EmptyState(
                icon: Icons.cloud_off_outlined,
                title: l10n.sourceError,
                body: '$error',
                action: FilledButton.icon(
                  onPressed: () => ref.invalidate(seriesProvider(key)),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(l10n.retry),
                ),
              ),
            ),
      data: (series) =>
          series.units.isEmpty && stored != null && stored.units.isNotEmpty
              ? body(stored, cached: true, refreshing: data.isLoading)
              : body(series, refreshing: data.isLoading),
    );
  }
}

/// The series page while its details load: the same silhouette as the loaded
/// page (cover, title, primary action, a few chapter rows), so the layout does
/// not jump when the real content arrives.
class _SeriesSkeleton extends StatelessWidget {
  const _SeriesSkeleton();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: const SingleChildScrollView(
        physics: NeverScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          BestLayout.gutter,
          BestSpace.sm,
          BestLayout.gutter,
          BestSpace.xl,
        ),
        child: BestPulse(
          child: Column(
            children: [
              BestSkeletonBox(width: 124, height: 186, radius: BestRadius.md),
              SizedBox(height: BestSpace.xl),
              BestSkeletonBox(width: 220, height: 22, radius: 6),
              SizedBox(height: BestSpace.md),
              BestSkeletonBox(width: 140, height: 14, radius: 6),
              SizedBox(height: BestSpace.xl),
              BestSkeletonBox(height: 52, radius: BestRadius.md),
              SizedBox(height: BestSpace.xl),
              RowSkeleton(),
              SizedBox(height: 10),
              RowSkeleton(),
              SizedBox(height: 10),
              RowSkeleton(),
            ],
          ),
        ),
      ),
    );
  }
}

class _SeriesBody extends ConsumerStatefulWidget {
  const _SeriesBody(
      {super.key,
      required this.data,
      required this.seriesKey,
      this.refreshing = false,
      this.cached = false,
      this.sourceMissing = false});

  final SeriesData data;
  final SeriesKey seriesKey;
  final bool refreshing;
  final bool cached;
  final bool sourceMissing;

  @override
  ConsumerState<_SeriesBody> createState() => _SeriesBodyState();
}

enum _SeriesAction { refresh, migrate, source }

class _SeriesBodyState extends ConsumerState<_SeriesBody> {
  final _search = TextEditingController();
  final _chapterHeader = GlobalKey();
  String _query = '';
  UnitFilter _filter = UnitFilter.all;
  UnitSort _sort = UnitSort.oldest;
  bool _bulkBusy = false;

  /// The page's scroll position. The app bar follows it: clear over the
  /// backdrop at the top, filled in as the hero title slides under it.
  late final ScrollController _scroll = ScrollController()
    ..addListener(_onScroll);
  final ValueNotifier<double> _bar = ValueNotifier<double>(0);
  final GlobalKey _heroTitle = GlobalKey();

  SeriesData get data => widget.data;
  SeriesKey get seriesKey => widget.seriesKey;

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    _bar.dispose();
    super.dispose();
  }

  /// 0 while the hero title is fully visible, 1 once it has slid completely
  /// under the app bar. Measured from the title itself, so it holds for any
  /// font size or title length.
  void _onScroll() {
    if (!mounted) return;
    final title = _heroTitle.currentContext?.findRenderObject();
    if (title is! RenderBox || !title.attached || !title.hasSize) return;
    final barBottom = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final titleTop = title.localToGlobal(Offset.zero).dy;
    final next = ((barBottom - titleTop) / title.size.height)
        .clamp(0.0, 1.0)
        .toDouble();
    // Only repaint the bar when the change is visible, not on every pixel.
    if ((next - _bar.value).abs() > 0.02 || next == 0 || next == 1) {
      _bar.value = next;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final media = data.media;
    final units = UnitNavigation.readingOrder(data.units);
    // The body runs behind the status bar and the app bar, so anything that
    // starts at the top of the page leaves this much room for them.
    final barHeight = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final downloads =
        ref.watch(downloadsProvider).value ?? const <DownloadTask>[];
    final tasks = {for (final task in downloads) task.unitId: task};
    final canDownload = media.kind.isReading && !widget.sourceMissing;
    final offlineCount = tasks.values
        .where((task) => task.mediaId == media.id && task.isFinished)
        .length;
    final visible = UnitNavigation.visible(
      units,
      query: _query,
      filter: _filter,
      sort: _sort,
      progress: data.progress,
      downloads: tasks,
    );
    bool pending(MediaUnit unit) {
      final task = tasks[unit.id];
      return task == null || task.isFailed;
    }

    final pendingDownloads = visible.where(pending).length;
    final bookmarks = ref.watch(readerBookmarksProvider);
    final bookmarked = units
        .where((unit) => bookmarks.containsKey(unit.id))
        .toList(growable: false);
    final pendingBookmarked = bookmarked.where(pending).length;
    final continuation = UnitNavigation.continuation(units, data.progress);
    final next = continuation?.unit;
    final needsSource = widget.sourceMissing &&
        next != null &&
        !(tasks[next.id]?.isFinished ?? false);
    final completed = units
        .where((unit) => data.progress[unit.id]?.completed ?? false)
        .length;
    final percent =
        units.isEmpty ? 0 : (completed * 100 / units.length).round();

    final overviewSlivers = <Widget>[
      SliverToBoxAdapter(
        child: _Hero(
          media: media,
          sourceMissing: widget.sourceMissing,
          offlineCount: offlineCount,
          titleKey: _heroTitle,
        ),
      ),
      if (media.genres.isNotEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final genre in media.genres.take(6))
                  _GenrePill(label: genre),
              ],
            ),
          ),
        ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: needsSource
                  ? () => context.push(Routes.sources)
                  : next == null
                      ? null
                      : () => openUnit(context, ref, media, next,
                          fromStart: continuation?.kind ==
                              UnitContinuationKind.replay),
              icon: Icon(
                needsSource
                    ? Icons.extension_outlined
                    : media.kind.isReading
                        ? Icons.menu_book_rounded
                        : Icons.play_arrow_rounded,
                size: 20,
              ),
              label: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(needsSource
                      ? l10n.directoryTitle
                      : _primaryLabel(l10n, media, continuation)),
                  if (next != null)
                    Text(
                      _primaryDescription(l10n, media, continuation!),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color:
                            theme.colorScheme.onPrimary.withValues(alpha: 0.85),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          child: _ShelfPlan(media: media),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          child: StatStrip(
            stats: [
              StatItem(
                value: '${units.length}',
                label: media.kind.isReading ? l10n.chapters : l10n.episodes,
              ),
              StatItem(
                value: '$offlineCount',
                label: l10n.offlineLabel,
              ),
              StatItem(value: '$percent%', label: l10n.progressLabel),
            ],
          ),
        ),
      ),
      if (media.synopsis != null && media.synopsis!.trim().isNotEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(title: l10n.aboutWork),
                _Synopsis(text: media.synopsis!),
              ],
            ),
          ),
        ),
    ];
    final chapterSlivers = <Widget>[
      if (widget.refreshing)
        const SliverToBoxAdapter(child: LinearProgressIndicator(minHeight: 2)),
      if (widget.cached && !widget.refreshing)
        SliverToBoxAdapter(
            child: Padding(
          padding: const EdgeInsets.all(BestLayout.gutter),
          child: _CachedChapterNotice(
            missingSource: widget.sourceMissing,
            hasDownloads: offlineCount > 0,
            onRetry: () => ref.invalidate(seriesProvider(seriesKey)),
            onSources: () => context.push(Routes.sources),
            onDownloads: () => _setFilter(UnitFilter.downloaded, reveal: true),
          ),
        )),
      SliverToBoxAdapter(
        child: Padding(
          key: _chapterHeader,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SectionHeader(
            title: media.kind.isReading ? l10n.chapters : l10n.episodes,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _query.trim().isNotEmpty || _filter != UnitFilter.all
                      ? l10n.seriesVisibleCount(visible.length, units.length)
                      : media.kind.isReading
                          ? l10n.chapterCount(units.length)
                          : l10n.episodeCount(units.length),
                  textDirection:
                      _query.trim().isNotEmpty || _filter != UnitFilter.all
                          ? TextDirection.ltr
                          : null,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (canDownload &&
                    (pendingDownloads > 0 || pendingBookmarked > 0)) ...[
                  const SizedBox(width: 2),
                  PopupMenuButton<bool>(
                    tooltip: l10n.downloadAll,
                    enabled: !_bulkBusy,
                    icon: const Icon(
                      Icons.download_for_offline_outlined,
                      size: 20,
                    ),
                    onSelected: (bookmarkedOnly) => _downloadAll(
                      context,
                      ref,
                      media,
                      bookmarkedOnly ? bookmarked : visible,
                      tasks,
                      bookmarkedOnly: bookmarkedOnly,
                    ),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: false,
                        enabled: pendingDownloads > 0,
                        child: Text(
                          _query.trim().isNotEmpty ||
                                  _filter != UnitFilter.all
                              ? l10n.seriesDownloadShown
                              : l10n.downloadAll,
                        ),
                      ),
                      PopupMenuItem(
                        value: true,
                        enabled: pendingBookmarked > 0,
                        child: Text(l10n.downloadBookmarked),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      PinnedHeaderSliver(
          child: Material(
        color: theme.colorScheme.surface,
        child: _chapterTools(context, media, units),
      )),
      if (units.isEmpty && widget.refreshing)
        SliverToBoxAdapter(
            child: Padding(
          padding: const EdgeInsets.all(BestLayout.gutter),
          child: Text(l10n.seriesUpdating),
        ))
      else if (units.isEmpty)
        SliverToBoxAdapter(
          child: EmptyState(
            icon: Icons.inbox_outlined,
            title: l10n.noUnits,
            body: l10n.nothingHereBody,
          ),
        )
      else if (visible.isEmpty)
        SliverToBoxAdapter(
            child: EmptyState(
          icon: Icons.filter_alt_off_outlined,
          title: l10n.seriesNoMatch,
          body: l10n.seriesNoMatchBody,
          action: TextButton(
            onPressed: _clearFilters,
            child: Text(l10n.seriesClearFilters),
          ),
        ))
      else
        SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            final unit = visible[index];
            final task = tasks[unit.id];
            return _UnitTile(
              key: ValueKey('series-unit-${unit.id}'),
              unit: unit,
              progress: data.progress[unit.id],
              download: task,
              canDownload: canDownload,
              onTap: () => openUnit(context, ref, media, unit),
              onDownload: () => _download(context, ref, media, unit),
              onPause: task == null
                  ? null
                  : () => ref.read(downloadManagerProvider).pause(task.unitId),
              onResume: task == null
                  ? null
                  : () => ref.read(downloadManagerProvider).resume(task.unitId),
            );
          }, childCount: visible.length),
        ),
      const SliverToBoxAdapter(child: SizedBox(height: 28)),
    ];
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: _SeriesAppBar(
        progress: _bar,
        title: Text(
          media.displayTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textDirection: autoTextDirection(
            media.displayTitle,
            Directionality.of(context),
          ),
        ),
        actions: [
          _GlassCircle(
            tooltip: media.favorite ? l10n.unfavorite : l10n.favorite,
            icon: media.favorite
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            active: media.favorite,
            onTap: () async {
              final repository = ref.read(repositoryProvider);
              if (!media.favorite && !media.inLibrary) {
                await repository.setInLibrary(media.id, true);
              }
              await repository.setFavorite(media.id, !media.favorite);
            },
          ),
          const SizedBox(width: BestSpace.xs),
          _GlassCircle(
            tooltip:
                media.inLibrary ? l10n.removeFromLibrary : l10n.addToLibrary,
            icon: media.inLibrary
                ? Icons.library_add_check_rounded
                : Icons.library_add_outlined,
            active: media.inLibrary,
            onTap: () => _toggleShelf(media),
          ),
          PopupMenuButton<_SeriesAction>(
            padding: EdgeInsets.zero,
            child: const _BarBubble(icon: Icons.more_vert_rounded),
            onSelected: (action) {
              switch (action) {
                case _SeriesAction.refresh:
                  ref.invalidate(seriesProvider(seriesKey));
                case _SeriesAction.migrate:
                  context.push(Routes.migrateOf(media));
                case _SeriesAction.source:
                  context.push(widget.sourceMissing
                      ? Routes.sources
                      : Routes.browseSource(media.ref.sourceId));
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                  value: _SeriesAction.refresh,
                  child: Text(l10n.seriesRefresh)),
              PopupMenuItem(
                  value: _SeriesAction.migrate, child: Text(l10n.migrateTitle)),
              PopupMenuItem(
                  value: _SeriesAction.source, child: Text(l10n.sourceLabel)),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: LayoutBuilder(builder: (context, constraints) {
              Widget chapterList(List<Widget> slivers, String key,
                      {ScrollController? controller}) =>
                  RefreshIndicator(
                    onRefresh: _refresh,
                    child: CustomScrollView(
                      key: PageStorageKey(key),
                      controller: controller,
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: slivers,
                    ),
                  );
              if (constraints.maxWidth < 840) {
                return chapterList(
                    [...overviewSlivers, ...chapterSlivers], 'series-phone',
                    controller: _scroll);
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                      width: 340,
                      child: CustomScrollView(
                        key: const PageStorageKey('series-overview'),
                        controller: _scroll,
                        slivers: overviewSlivers,
                      )),
                  VerticalDivider(
                      width: 1, color: theme.colorScheme.outlineVariant),
                  Expanded(
                      child: chapterList([
                        SliverToBoxAdapter(child: SizedBox(height: barHeight)),
                        ...chapterSlivers,
                      ], 'series-chapters')),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }

  Future<void> _refresh() async {
    ref.invalidate(seriesProvider(seriesKey));
    try {
      await ref.read(seriesProvider(seriesKey).future);
    } catch (_) {
      // The saved list stays visible; the cache notice offers recovery.
    }
  }

  void _setFilter(UnitFilter filter, {bool reveal = false}) {
    setState(() => _filter = filter);
    if (reveal) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = _chapterHeader.currentContext;
        if (mounted && target != null) {
          Scrollable.ensureVisible(target,
              duration: BestMotion.normal, curve: BestMotion.curve);
        }
      });
    }
  }

  void _clearFilters() {
    _search.clear();
    setState(() {
      _query = '';
      _filter = UnitFilter.all;
    });
  }

  String _primaryLabel(
      AppLocalizations l10n, Media media, UnitContinuation? next) {
    final reading = media.kind.isReading;
    return switch (next?.kind) {
      UnitContinuationKind.resume =>
        reading ? l10n.continueReading : l10n.continueWatching,
      UnitContinuationKind.next =>
        reading ? l10n.readerNextChapter : l10n.seriesNextEpisode,
      UnitContinuationKind.catchUp =>
        reading ? l10n.seriesReadRemaining : l10n.seriesWatchRemaining,
      UnitContinuationKind.replay =>
        reading ? l10n.seriesReadAgain : l10n.seriesWatchAgain,
      _ => reading ? l10n.startReading : l10n.startWatching,
    };
  }

  String _primaryDescription(
      AppLocalizations l10n, Media media, UnitContinuation next) {
    if (next.kind == UnitContinuationKind.resume && next.progress != null) {
      return '${unitTitle(l10n, next.unit)} · ${continueProgressLabel(
        l10n,
        ContinueEntry(media: media, unit: next.unit, progress: next.progress!),
      )}';
    }
    return unitTitle(l10n, next.unit);
  }

  Widget _chapterTools(
      BuildContext context, Media media, List<MediaUnit> units) {
    final l10n = AppLocalizations.of(context);
    final numbered = UnitNavigation.hasChronologicalOrder(units);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(children: [
        Row(children: [
          Expanded(
              child: TextField(
            key: const ValueKey('series-unit-search'),
            controller: _search,
            textInputAction: TextInputAction.search,
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: media.kind.isReading
                  ? l10n.seriesChapterSearch
                  : l10n.seriesEpisodeSearch,
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip:
                          MaterialLocalizations.of(context).closeButtonTooltip,
                      onPressed: () {
                        _search.clear();
                        setState(() => _query = '');
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          )),
          IconButton(
            key: const ValueKey('series-chapter-picker'),
            tooltip: media.kind.isReading ? l10n.chapters : l10n.episodes,
            onPressed:
                units.isEmpty ? null : () => _showUnitPicker(media, units),
            icon: const Icon(Icons.format_list_numbered_rounded),
          ),
          PopupMenuButton<UnitSort>(
            tooltip: l10n.seriesSort,
            initialValue: _sort,
            icon: const Icon(Icons.sort_rounded),
            onSelected: (sort) => setState(() => _sort = sort),
            itemBuilder: (context) => [
              PopupMenuItem(
                  value: UnitSort.oldest,
                  child: Text(numbered
                      ? l10n.readerSortOldest
                      : l10n.seriesSourceOrder)),
              PopupMenuItem(
                  value: UnitSort.newest,
                  child: Text(numbered
                      ? l10n.readerSortNewest
                      : l10n.seriesReverseOrder)),
            ],
          ),
        ]),
        const SizedBox(height: BestSpace.sm),
        // Wrap instead of a horizontal scroller: every filter is visible at
        // once, and the first chip can never be clipped at the screen edge.
        Wrap(
          spacing: BestSpace.sm,
          runSpacing: BestSpace.xs,
          children: [
            for (final filter in UnitFilter.values)
              if (filter != UnitFilter.downloaded || media.kind.isReading)
                ChoiceChip(
                  label: Text(switch (filter) {
                    UnitFilter.all => l10n.seriesAllUnits,
                    UnitFilter.unread => l10n.seriesUnreadUnits,
                    UnitFilter.inProgress => l10n.seriesStartedUnits,
                    UnitFilter.downloaded => l10n.seriesDownloadedUnits,
                  }),
                  selected: _filter == filter,
                  onSelected: (selected) =>
                      _setFilter(selected ? filter : UnitFilter.all),
                ),
          ],
        ),
      ]),
    );
  }

  void _showUnitPicker(Media media, List<MediaUnit> units) {
    FocusScope.of(context).unfocus();
    final continuation = UnitNavigation.continuation(units, data.progress);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(BestRadius.sheet)),
      ),
      builder: (sheetContext) => ChapterListSheet(
        units: units,
        workTitle: media.displayTitle,
        initialUnitId: continuation?.unit.id,
        currentUnitId: continuation?.kind == UnitContinuationKind.resume
            ? continuation!.unit.id
            : '',
        onSelected: (unit) {
          Navigator.of(sheetContext).pop();
          openUnit(context, ref, media, unit);
        },
      ),
    );
  }

  Future<void> _toggleShelf(Media media) async {
    if (media.inLibrary) {
      final l10n = AppLocalizations.of(context);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.removeFromLibrary),
          content: Text(l10n.seriesRemoveBody),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l10n.cancel)),
            FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(l10n.removeFromLibrary)),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    if (media.inLibrary) {
      await ref.read(repositoryProvider).setInLibrary(media.id, false);
    } else {
      await addMediaToLibrary(context, ref, media);
    }
  }

  Future<void> _downloadAll(
    BuildContext context,
    WidgetRef ref,
    Media media,
    List<MediaUnit> units,
    Map<String, DownloadTask> tasks, {
    bool bookmarkedOnly = false,
  }) async {
    if (_bulkBusy) return;
    final l10n = AppLocalizations.of(context);
    final pending = units.where((unit) {
      final task = tasks[unit.id];
      return task == null || task.isFailed;
    }).toList(growable: false);
    if (pending.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          bookmarkedOnly ? l10n.downloadBookmarked : l10n.downloadAllTitle,
        ),
        content: Text(l10n.downloadAllBody(pending.length)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.downloadAll),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final manager = ref.read(downloadManagerProvider);
    final repository = ref.read(repositoryProvider);
    var queued = 0;
    var failed = 0;
    setState(() => _bulkBusy = true);
    for (final unit in pending) {
      try {
        final current = await repository.downloadFor(unit.id);
        if (current != null &&
            (current.isFinished || current.isActive || current.isPaused)) {
          continue;
        }
        final task = await manager.enqueue(media, unit);
        if (task.isActive) queued++;
      } catch (_) {
        failed++;
      }
    }
    if (!context.mounted) return;
    setState(() => _bulkBusy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(
        '${l10n.downloadAllQueued(queued)}'
        '${failed == 0 ? '' : '\n${l10n.seriesQueueFailed(failed)}'}',
      )),
    );
  }

  Future<void> _download(
    BuildContext context,
    WidgetRef ref,
    Media media,
    MediaUnit unit,
  ) async {
    try {
      await ref.read(downloadManagerProvider).enqueue(media, unit);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(AppLocalizations.of(context).readerDownloadFailed)),
        );
      }
      return;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).downloadStarted)),
    );
  }
}

class _CachedChapterNotice extends StatelessWidget {
  const _CachedChapterNotice(
      {required this.missingSource,
      required this.hasDownloads,
      required this.onRetry,
      required this.onSources,
      required this.onDownloads});

  final bool missingSource;
  final bool hasDownloads;
  final VoidCallback onRetry;
  final VoidCallback onSources;
  final VoidCallback onDownloads;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('series-cache-notice'),
      padding: const EdgeInsets.all(BestSpace.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(BestRadius.md),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
            missingSource
                ? l10n.sourceNotInstalledTitle
                : l10n.seriesSavedTitle,
            style: theme.textTheme.titleSmall),
        const SizedBox(height: BestSpace.sm),
        Text(
            missingSource ? l10n.sourceNotInstalledBody : l10n.seriesCachedBody,
            style: theme.textTheme.bodySmall?.copyWith(height: 1.5)),
        const SizedBox(height: BestSpace.sm),
        Wrap(spacing: BestSpace.sm, children: [
          TextButton.icon(
            onPressed: missingSource ? onSources : onRetry,
            icon: Icon(
                missingSource
                    ? Icons.extension_outlined
                    : Icons.refresh_rounded,
                size: 18),
            label: Text(missingSource ? l10n.directoryTitle : l10n.retry),
          ),
          if (hasDownloads)
            TextButton.icon(
              onPressed: onDownloads,
              icon: const Icon(Icons.offline_pin_outlined, size: 18),
              label: Text(l10n.seriesShowDownloaded),
            ),
        ]),
      ]),
    );
  }
}

/// The work's front page: artwork, cover, title and the facts a reader checks
/// before starting. Left-aligned and layered, never a centred poster on an
/// empty background — a missing cover degrades to a themed gradient instead of
/// a broken-looking blur.
class _Hero extends ConsumerWidget {
  const _Hero({
    required this.media,
    required this.sourceMissing,
    required this.offlineCount,
    this.titleKey,
  });

  final Media media;
  final bool sourceMissing;
  final int offlineCount;

  /// Lets the page measure where the title sits as it scrolls.
  final Key? titleKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final source = ref.watch(sourceRegistryProvider).byId(media.ref.sourceId);
    final sourceName = source?.name ??
        (sourceMissing ? l10n.sourceNotInstalledTitle : media.ref.sourceId);
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Colors.transparent,
        theme.colorScheme.surface.withValues(alpha: 0.28),
        theme.colorScheme.surface.withValues(alpha: 0.82),
        theme.colorScheme.surface,
      ],
      stops: const [0.0, 0.45, 0.8, 1.0],
    );

    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
    return SizedBox(
      height: top + 312,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (media.coverUrl != null)
            // Clipped to the hero, so the blur never spills past its edge.
            ClipRect(
              child: BestBackdrop(
                title: media.displayTitle,
                url: media.coverUrl,
                blur: 32,
                opacity: 0.5,
              ),
            )
          else
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: AlignmentDirectional.topStart,
                  end: AlignmentDirectional.bottomEnd,
                  colors: [
                    theme.colorScheme.primary.withValues(alpha: 0.34),
                    theme.colorScheme.secondary.withValues(alpha: 0.18),
                    theme.colorScheme.surface,
                  ],
                ),
              ),
            ),
          DecoratedBox(decoration: BoxDecoration(gradient: gradient)),
          PositionedDirectional(
            start: 20,
            end: 20,
            bottom: 18,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  width: 116,
                  height: 174,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(BestRadius.md),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.16),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.42),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(BestRadius.md),
                    child: BestCover(
                      title: media.displayTitle,
                      url: media.coverUrl,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        media.displayTitle,
                        key: titleKey,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        textDirection: autoTextDirection(
                          media.displayTitle,
                          Directionality.of(context),
                        ),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          height: 1.08,
                          letterSpacing: BestType.tracking(context, -0.7),
                          shadows: const [
                            Shadow(color: Colors.black54, blurRadius: 12),
                          ],
                        ),
                      ),
                      if (media.nativeTitle != null &&
                          media.nativeTitle!.trim().isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(
                          media.nativeTitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white70,
                            shadows: const [
                              Shadow(color: Colors.black54, blurRadius: 8),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _HeroTag(
                            text: sourceName,
                            icon: Icons.extension_outlined,
                          ),
                          _HeroTag(text: kindLabel(l10n, media.kind)),
                          if (media.year != null)
                            _HeroTag(text: '${media.year}'),
                          _HeroTag(text: statusLabel(l10n, media.status)),
                          if (media.rating != null)
                            _HeroTag(text: media.rating!.toStringAsFixed(1)),
                          if (offlineCount > 0)
                            _HeroTag(
                              text: l10n.offlineCount(offlineCount),
                              accent: true,
                            ),
                        ],
                      ),
                      if (media.author != null &&
                          media.author!.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          media.author!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white70,
                            shadows: const [
                              Shadow(color: Colors.black54, blurRadius: 8),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroTag extends StatelessWidget {
  const _HeroTag({required this.text, this.accent = false, this.icon});

  final String text;

  /// Reserved for a real state (offline copies). Everything else stays neutral.
  final bool accent;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final foreground = accent ? BestColors.ink : Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: accent
            ? BestColors.jade.withValues(alpha: 0.92)
            : Colors.black.withValues(alpha: 0.36),
        borderRadius: BorderRadius.circular(BestRadius.pill),
        border: accent
            ? null
            : Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: foreground),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GenrePill extends StatelessWidget {
  const _GenrePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(BestRadius.pill),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _GlassCircle extends StatelessWidget {
  const _GlassCircle({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      style: IconButton.styleFrom(
        fixedSize: const Size(40, 40),
        shape: const CircleBorder(),
        backgroundColor:
            active ? BestColors.jade : Colors.black.withValues(alpha: 0.38),
        foregroundColor: active ? BestColors.ink : Colors.white,
        side: active
            ? null
            : BorderSide(color: Colors.white.withValues(alpha: 0.12)),
      ),
      icon: Icon(icon, size: 20),
    );
  }
}

/// The visual of a round top-bar button, for the control that opens a menu.
class _BarBubble extends StatelessWidget {
  const _BarBubble({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withValues(alpha: 0.38),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Icon(icon, size: 20, color: Colors.white),
    );
  }
}

/// The series page's app bar. It starts clear, so the backdrop runs up behind
/// the status bar, and fills in as the hero title scrolls under it.
class _SeriesAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _SeriesAppBar({
    required this.progress,
    required this.title,
    required this.actions,
  });

  final ValueListenable<double> progress;
  final Widget title;
  final List<Widget> actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return ValueListenableBuilder<double>(
      valueListenable: progress,
      builder: (context, value, _) => AppBar(
        backgroundColor: surface.withValues(alpha: value),
        title: Opacity(opacity: value, child: title),
        actions: actions,
      ),
    );
  }
}

class _Synopsis extends StatefulWidget {
  const _Synopsis({required this.text});

  final String text;

  @override
  State<_Synopsis> createState() => _SynopsisState();
}

class _SynopsisState extends State<_Synopsis> {
  bool _open = false;

  @override
  void didUpdateWidget(_Synopsis oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) _open = false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final style = theme.textTheme.bodyMedium?.copyWith(
      height: 1.7,
      color: theme.colorScheme.onSurfaceVariant,
    );
    return LayoutBuilder(builder: (context, constraints) {
      final measure = TextPainter(
        text: TextSpan(text: widget.text, style: style),
        maxLines: 4,
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: constraints.maxWidth);
      final expandable = measure.didExceedMaxLines;
      measure.dispose();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.text,
            maxLines: _open ? null : 4,
            overflow: _open ? null : TextOverflow.ellipsis,
            style: style,
          ),
          if (expandable || _open)
            TextButton(
              onPressed: () => setState(() => _open = !_open),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
              child: Text(_open ? l10n.less : l10n.more),
            ),
        ],
      );
    });
  }
}

class _UnitTile extends StatelessWidget {
  const _UnitTile({
    super.key,
    required this.unit,
    required this.progress,
    required this.download,
    required this.canDownload,
    required this.onTap,
    required this.onDownload,
    required this.onPause,
    required this.onResume,
  });

  final MediaUnit unit;
  final UnitProgress? progress;
  final DownloadTask? download;
  final bool canDownload;
  final VoidCallback onTap;
  final VoidCallback onDownload;
  final VoidCallback? onPause;
  final VoidCallback? onResume;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final saved = progress;
    final completed = saved?.completed ?? false;
    final started = UnitNavigation.hasStarted(saved) && !completed;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Material(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(BestRadius.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(BestRadius.md),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 34,
                  height: 34,
                  child: Center(
                    child: completed
                        ? const Icon(
                            Icons.check_circle_rounded,
                            color: BestColors.jade,
                            size: 26,
                          )
                        : started
                            ? SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  value: saved!.fraction,
                                  strokeWidth: 2.6,
                                ),
                              )
                            : Icon(
                                Icons.radio_button_unchecked,
                                size: 21,
                                color: theme.colorScheme.outlineVariant,
                              ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        unitTitle(l10n, unit),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: autoTextDirection(
                          unitTitle(l10n, unit),
                          Directionality.of(context),
                        ),
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _subtitle(l10n, unit),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                if (canDownload)
                  _DownloadControl(
                    unit: unit,
                    download: download,
                    onDownload: onDownload,
                    onPause: onPause,
                    onResume: onResume,
                  ),
                const SizedBox(width: 4),
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(BestRadius.sm),
                  ),
                  child: Text(
                    shortNumber(unit.number),
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _subtitle(AppLocalizations l10n, MediaUnit unit) {
    final parts = <String>[];
    final date = shortDate(unit.publishedAt);
    if (date.isNotEmpty) parts.add(date);
    if (unit.pageCount > 0) parts.add(l10n.pages(unit.pageCount));
    return parts.join(' · ');
  }
}

class _DownloadControl extends StatelessWidget {
  const _DownloadControl({
    required this.unit,
    required this.download,
    required this.onDownload,
    required this.onPause,
    required this.onResume,
  });

  final MediaUnit unit;
  final DownloadTask? download;
  final VoidCallback onDownload;
  final VoidCallback? onPause;
  final VoidCallback? onResume;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final task = download;

    if (task == null) {
      return IconButton(
        tooltip: unit.kind == UnitKind.episode
            ? l10n.downloadEpisode
            : l10n.downloadChapter,
        visualDensity: VisualDensity.compact,
        onPressed: onDownload,
        icon: const Icon(Icons.download_outlined, size: 20),
      );
    }
    if (task.isFinished) {
      return Tooltip(
        message: l10n.downloadDone,
        child: const Padding(
          padding: EdgeInsets.all(12),
          child: Icon(
            Icons.download_done_rounded,
            color: BestColors.jade,
            size: 20,
          ),
        ),
      );
    }
    if (task.isFailed) {
      return IconButton(
        tooltip: l10n.downloadRetry,
        visualDensity: VisualDensity.compact,
        onPressed: onResume,
        icon: Icon(
          Icons.refresh_rounded,
          size: 20,
          color: Theme.of(context).colorScheme.error,
        ),
      );
    }
    if (task.isPaused) {
      return IconButton(
        tooltip: l10n.downloadResume,
        visualDensity: VisualDensity.compact,
        onPressed: onResume,
        icon: const Icon(Icons.play_arrow_rounded, size: 22),
      );
    }
    return IconButton(
      tooltip: l10n.downloadPause,
      visualDensity: VisualDensity.compact,
      onPressed: onPause,
      icon: SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          value: task.progress,
          strokeWidth: 2.2,
        ),
      ),
    );
  }
}

/// The person's own plan and lists.
///
/// It reads the stored row, not the provider argument, so a tap shows up
/// immediately without re-fetching the work from its source.
class _ShelfPlan extends ConsumerWidget {
  const _ShelfPlan({required this.media});

  final Media media;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final stored = ref.watch(mediaByIdProvider(media.id)).value ?? media;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.shelfPlan.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  letterSpacing: BestType.tracking(context, 1.4),
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (stored.tags.isNotEmpty)
              Text(
                l10n.listsTitle,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final state in const [
              ReadingState.reading,
              ReadingState.planned,
              ReadingState.paused,
            ])
              ChoiceChip(
                avatar: Icon(_stateIcon(state), size: 15),
                label: Text(stateLabel(l10n, state)),
                selected: stored.state == state,
                onSelected: (selected) => setReadingState(
                  context,
                  ref,
                  stored,
                  selected ? state : ReadingState.none,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tag in stored.tags)
              InputChip(
                label: Text(tag),
                visualDensity: VisualDensity.compact,
                onDeleted: () => removeTag(ref, stored, tag),
              ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 15),
              label: Text(l10n.listAdd),
              onPressed: () => _addList(context, ref, stored),
            ),
          ],
        ),
      ],
    );
  }

  static IconData _stateIcon(ReadingState state) => switch (state) {
        ReadingState.reading => Icons.menu_book_rounded,
        ReadingState.planned => Icons.bookmark_outline_rounded,
        ReadingState.paused => Icons.pause_circle_outline_rounded,
        ReadingState.none => Icons.remove,
      };

  static Future<void> _addList(
    BuildContext context,
    WidgetRef ref,
    Media media,
  ) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.listName),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(hintText: l10n.listAdd),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(l10n.listAdd),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;
    await addTag(ref, media, name);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.listAdded(name.trim()))));
  }
}
