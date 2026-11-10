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
import '../widgets/source_avatar.dart';

/// The front door is one source at a time.
///
/// Best is not a merged search engine: the reader chooses where they read or
/// watch, and the home feed shows that site's catalogue — never a silent mix of
/// a manga site, an anime site and an external database. The source and the
/// manga/anime half stay pinned above the grid, so changing either never needs
/// a scroll back to the top.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

enum _Feed { latest, popular }

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final ScrollController _scroll = ScrollController();

  String? _sourceId;
  _Feed _feed = _Feed.latest;

  List<Media> _works = const [];
  int _page = 0;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _initialised = false;
  String? _error;
  int _generation = 0;
  String? _boundSourceId;
  _Feed? _boundFeed;

  @override
  void initState() {
    super.initState();
    final scope = ref.read(homeScopeProvider);
    _sourceId = scope.sourceId;
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - 900) {
      unawaited(_load());
    }
  }

  /// Every source the reader installed, manga and anime alike, minus the ones
  /// they hid from Home. No switch is shown: a source already knows what it
  /// publishes, and a reader who never adds an anime extension should never see
  /// an anime control.
  List<SourceAdapter> _sources() {
    final hidden = ref.read(sourceVisibilityProvider);
    return ref
        .read(sourceRegistryProvider)
        .all
        .where((source) => !hidden.contains(source.id))
        .toList(growable: false);
  }

  bool get _hasInstalledSources =>
      ref.read(sourceRegistryProvider).all.isNotEmpty;

  Future<List<Media>> _fetch(SourceAdapter source, _Feed feed, int page) {
    if (feed == _Feed.latest && source is LatestSource) {
      return (source as LatestSource).latest(page: page);
    }
    return source.popular(page: page);
  }

  Future<void> _load({bool reset = false}) async {
    final sources = _sources();
    if (sources.isEmpty) {
      setState(() {
        _works = const [];
        _loading = false;
        _loadingMore = false;
        _error = null;
        _initialised = true;
      });
      return;
    }
    SourceAdapter source = sources.first;
    for (final candidate in sources) {
      if (candidate.id == _sourceId) {
        source = candidate;
        break;
      }
    }
    if (_sourceId != source.id) {
      _sourceId = source.id;
    }

    final feed = _feed == _Feed.latest && source is LatestSource
        ? _Feed.latest
        : _Feed.popular;
    if (_loadingMore || (!reset && !_hasMore)) return;

    final generation = ++_generation;
    final page = reset ? 1 : _page + 1;
    if (reset) {
      setState(() {
        _works = const [];
        _page = 0;
        _hasMore = true;
        _error = null;
        _loading = true;
        _loadingMore = false;
        _boundSourceId = source.id;
        _boundFeed = feed;
      });
      if (_scroll.hasClients) _scroll.jumpTo(0);
    } else {
      setState(() => _loadingMore = true);
    }

    final started = DateTime.now();
    try {
      final works = await _fetch(source, feed, page);
      if (mounted) {
        ref
            .read(sourceHealthProvider.notifier)
            .recordSuccess(source.id, DateTime.now().difference(started));
      }
      if (!mounted || generation != _generation) return;
      final seen = {for (final work in _works) work.id};
      final fresh = <Media>[];
      for (final work in works) {
        if (seen.add(work.id)) fresh.add(work);
      }
      setState(() {
        _works = reset ? fresh : [..._works, ...fresh];
        _page = page;
        // A short page or a page made entirely of repeats is the end. Never
        // keep asking a source that has started repeating itself.
        _hasMore = works.isNotEmpty && fresh.isNotEmpty;
        _loading = false;
        _loadingMore = false;
        _initialised = true;
        _boundSourceId = source.id;
        _boundFeed = feed;
      });
    } catch (error) {
      if (mounted) {
        ref.read(sourceHealthProvider.notifier).recordFailure(source.id, error);
      }
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _initialised = true;
        _error = reset || _works.isEmpty ? '$error' : null;
        if (_works.isNotEmpty) _hasMore = false;
      });
    }
  }

  void _selectSource(SourceAdapter source) {
    if (source.id == _sourceId) return;
    setState(() {
      _sourceId = source.id;
      _boundSourceId = null;
      _boundFeed = null;
    });
    ref.read(homeScopeProvider.notifier).selectSource(source.id);
    unawaited(_load(reset: true));
  }

  void _setFeed(_Feed feed) {
    if (feed == _feed) return;
    setState(() {
      _feed = feed;
      _boundFeed = null;
    });
    unawaited(_load(reset: true));
  }

  void _openSourcePicker(
    BuildContext context,
    SourceAdapter? current,
    List<SourceAdapter> sources,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _SourcePicker(
        current: current,
        sources: sources,
        onSelected: (source) {
          Navigator.of(sheetContext).pop();
          _selectSource(source);
        },
        onManage: () {
          Navigator.of(sheetContext).pop();
          context.push(Routes.manageSources);
        },
        onAdd: () {
          Navigator.of(sheetContext).pop();
          context.push(Routes.sources);
        },
      ),
    );
  }

  Future<void> _toggleShelf(Media media, AppLocalizations l10n) async {
    final repository = ref.read(repositoryProvider);
    if (!media.inLibrary) {
      final added = await addMediaToLibrary(context, ref, media);
      if (!added || !mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('${media.displayTitle} · ${l10n.addToLibrary}'),
            duration: const Duration(seconds: 2),
          ),
        );
      return;
    }
    if (!mounted) return;
    final remove = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.bookmark_added_rounded),
              title: Text(media.displayTitle, maxLines: 2),
              subtitle: Text(l10n.inLibrary),
            ),
            ListTile(
              leading: const Icon(Icons.bookmark_remove_outlined),
              title: Text(l10n.removeFromLibrary),
              onTap: () => Navigator.of(sheetContext).pop(true),
            ),
          ],
        ),
      ),
    );
    if (remove == true) {
      await repository.setInLibrary(media.id, false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // Rebuild when a source is hidden or shown in Manage sources.
    ref.watch(sourceVisibilityProvider);
    final sources = _sources();
    SourceAdapter? current;
    for (final source in sources) {
      if (source.id == _sourceId) {
        current = source;
        break;
      }
    }
    current ??= sources.isEmpty ? null : sources.first;
    // The remembered source was hidden. Move to the first visible source after
    // this frame instead of showing a chip that is no longer there.
    if (_sourceId != null && current != null && current.id != _sourceId) {
      final fallback = current;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _sourceId != fallback.id) _selectSource(fallback);
      });
    }
    final feed = _feed == _Feed.latest && current is LatestSource
        ? _Feed.latest
        : _Feed.popular;

    // The source list can arrive after the first frame (extensions load
    // asynchronously) or change when a source is installed. Binding here keeps
    // the first real source supplied without a state write during build.
    if (current != null &&
        !_loading &&
        (_boundSourceId != current.id || _boundFeed != feed)) {
      _boundSourceId = current.id;
      _boundFeed = feed;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_load(reset: true));
      });
    }

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              BestLayout.gutter,
              BestSpace.lg,
              BestLayout.gutter - 4,
              0,
            ),
            child: Row(
              children: [
                const BestMark(size: 44),
                const SizedBox(width: BestSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          l10n.appName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.displaySmall?.copyWith(
                            fontFamily: BestFonts.display,
                            fontSize: 31,
                            fontWeight: FontWeight.w700,
                            height: 0.98,
                            letterSpacing: BestType.tracking(context, -0.2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        l10n.homeRole,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.secondary,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: BestType.tracking(context, 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                _MastheadAction(
                  key: const ValueKey('home-unified-search'),
                  tooltip: l10n.searchEverything,
                  icon: Icons.search_rounded,
                  onPressed: () => context.push(Routes.metaSearch),
                ),
                const SizedBox(width: 6),
                _MastheadAction(
                  key: const ValueKey('home-settings'),
                  tooltip: l10n.navSettings,
                  icon: Icons.settings_outlined,
                  onPressed: () => context.push(Routes.settings),
                ),
              ],
            ),
          ),
          const SizedBox(height: BestSpace.lg),
          _SourceStrip(
            sources: sources,
            current: current,
            onSelected: _selectSource,
            onManage: () => _openSourcePicker(context, current, sources),
            manageLabel: l10n.homeChooseSource,
          ),
          const SizedBox(height: BestSpace.md),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: BestLayout.gutter),
            child: _FeedTabs(
              selected: feed,
              latestAvailable: current is LatestSource,
              latestLabel: l10n.homeLatest,
              popularLabel: l10n.homePopular,
              onSelected: _setFeed,
            ),
          ),
          const SizedBox(height: BestSpace.sm),
          Expanded(child: _body(context, l10n, current, feed)),
        ],
      ),
    );
  }

  /// Empty states sit under a tall header on small phones. Letting them scroll
  /// keeps large text and a 320 dp screen from overflowing.
  Widget _scrollableEmpty(Widget child) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: child,
          ),
        );
      },
    );
  }

  Widget _body(
    BuildContext context,
    AppLocalizations l10n,
    SourceAdapter? current,
    _Feed feed,
  ) {
    if (current == null) {
      if (_hasInstalledSources) {
        return _scrollableEmpty(
          EmptyState(
            icon: Icons.visibility_off_outlined,
            title: l10n.sourcesHiddenEmptyTitle,
            body: l10n.sourcesHiddenEmptyBody,
            action: FilledButton.icon(
              onPressed: () => context.push(Routes.manageSources),
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: Text(l10n.sourcesManage),
            ),
          ),
        );
      }
      return _scrollableEmpty(
        EmptyState(
          icon: Icons.extension_outlined,
          title: l10n.mangaNoSourcesTitle,
          body: l10n.mangaNoSourcesBody,
          action: FilledButton.icon(
            onPressed: () => context.push(Routes.sources),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text(l10n.homeAddSources),
          ),
        ),
      );
    }
    if (_works.isEmpty && (_loading || !_initialised)) {
      return const CustomScrollView(
        physics: NeverScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: 8)),
          SliverPosterGridSkeleton(),
        ],
      );
    }
    if (_works.isEmpty && _error != null) {
      return _scrollableEmpty(
        EmptyState(
          icon: Icons.cloud_off_outlined,
          title: l10n.sourceError,
          body: '${current.name}\n$_error',
          action: Wrap(
            alignment: WrapAlignment.center,
            spacing: BestSpace.sm,
            runSpacing: BestSpace.xs,
            children: [
              FilledButton.icon(
                onPressed: () => _load(reset: true),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(l10n.retry),
              ),
              OutlinedButton.icon(
                onPressed: () => context.push(Routes.manageSources),
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: Text(l10n.sourcesManage),
              ),
            ],
          ),
        ),
      );
    }
    if (_works.isEmpty) {
      return _scrollableEmpty(
        EmptyState(
          icon: Icons.auto_stories_outlined,
          title: feed == _Feed.latest ? l10n.homeNoLatest : l10n.homeNoResults,
          body: l10n.homeDiscoveryBody,
          action: OutlinedButton.icon(
            onPressed: () => _load(reset: true),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(l10n.retry),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: BestLayout.gutter),
            sliver: SliverLayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.crossAxisExtent;
                // One density on every phone: two readable posters per row,
                // the same card the shelf uses. Three columns made the covers
                // and one-line titles too small to scan.
                final columns = (width / 170).floor().clamp(2, 6).toInt();
                final tileWidth = (width - (columns - 1) * 12) / columns;
                return SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    mainAxisExtent: tileWidth * 1.5 + 80,
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final media = _works[index];
                    return WorkCard(
                      title: media.displayTitle,
                      subtitle: media.genres.isEmpty
                          ? null
                          : media.genres.take(2).join(' · '),
                      coverUrl: media.coverUrl,
                      badge: media.inLibrary
                          ? '${kindLabel(l10n, media.kind)} ✓'
                          : kindLabel(l10n, media.kind),
                      rating: media.rating,
                      onTap: () => openSeries(context, ref, media),
                      onLongPress: () => _toggleShelf(media, l10n),
                    );
                  }, childCount: _works.length),
                );
              },
            ),
          ),
          SliverToBoxAdapter(
            child: _FeedFooter(
              loading: _loadingMore,
              hasMore: _hasMore,
              failed: _error != null && _works.isNotEmpty,
              retryLabel: l10n.retry,
              onRetry: () => _load(),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: BestSpace.xl)),
        ],
      ),
    );
  }
}

class _SourceStrip extends StatelessWidget {
  const _SourceStrip({
    required this.sources,
    required this.current,
    required this.onSelected,
    required this.onManage,
    required this.manageLabel,
  });

  final List<SourceAdapter> sources;
  final SourceAdapter? current;
  final ValueChanged<SourceAdapter> onSelected;
  final VoidCallback onManage;
  final String manageLabel;

  @override
  Widget build(BuildContext context) {
    if (sources.isEmpty) {
      return const SizedBox(height: 4);
    }
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: BestLayout.gutter),
        itemCount: sources.length + 1,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == sources.length) {
            return IconButton.outlined(
              tooltip: manageLabel,
              onPressed: onManage,
              icon: const Icon(Icons.tune_rounded, size: 19),
            );
          }
          final source = sources[index];
          final selected = source.id == current?.id;
          return _SourceChip(
            source: source,
            selected: selected,
            onTap: selected ? onManage : () => onSelected(source),
          );
        },
      ),
    );
  }
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({
    required this.source,
    required this.selected,
    required this.onTap,
  });

  final SourceAdapter source;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: source.name,
      child: Material(
        color: selected
            ? theme.colorScheme.primary.withValues(alpha: 0.10)
            : theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(BestRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(BestRadius.md),
          child: Container(
            padding: const EdgeInsetsDirectional.only(start: 6, end: 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(BestRadius.md),
              border: Border.all(
                color: selected
                    ? theme.colorScheme.primary.withValues(alpha: 0.45)
                    : theme.colorScheme.outlineVariant,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SourceAvatar(source: source, size: 30),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: Text(
                    source.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontSize: 12.5,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      color: selected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
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
}

/// Two editorial feed tabs, not a segmented control: a running text line
/// with a short vermilion rule under the chosen feed. The rule is the only
/// chrome, so the catalogue beneath it stays the loudest thing on screen.
class _FeedTabs extends StatelessWidget {
  const _FeedTabs({
    required this.selected,
    required this.latestAvailable,
    required this.latestLabel,
    required this.popularLabel,
    required this.onSelected,
  });

  final _Feed selected;
  final bool latestAvailable;
  final String latestLabel;
  final String popularLabel;
  final ValueChanged<_Feed> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final options = <_Feed, String>{
      if (latestAvailable) _Feed.latest: latestLabel,
      _Feed.popular: popularLabel,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final entry in options.entries) ...[
          if (entry.key != options.keys.first) const SizedBox(width: 22),
          Semantics(
            button: true,
            selected: entry.key == selected,
            child: InkWell(
              key: ValueKey('home-feed-${entry.key.name}'),
              onTap: () => onSelected(entry.key),
              borderRadius: BorderRadius.circular(BestRadius.xs),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.value,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontSize: 15,
                        color: entry.key == selected
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.onSurfaceVariant,
                        fontWeight: entry.key == selected
                            ? FontWeight.w800
                            : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 5),
                    AnimatedContainer(
                      duration: BestMotionPolicy.of(context, BestMotion.normal),
                      curve: BestMotion.curve,
                      width: entry.key == selected ? 26 : 0,
                      height: 2.5,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// A circular masthead action. Two of these are the whole global chrome on
/// Home; a square icon button made the header look like a toolbar instead of
/// a title page.
class _MastheadAction extends StatelessWidget {
  const _MastheadAction({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: theme.colorScheme.surfaceContainerLow,
        shape: CircleBorder(
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, size: 20, color: theme.colorScheme.onSurface),
          ),
        ),
      ),
    );
  }
}

class _FeedFooter extends StatelessWidget {
  const _FeedFooter({
    required this.loading,
    required this.hasMore,
    required this.failed,
    required this.retryLabel,
    required this.onRetry,
  });

  final bool loading;
  final bool hasMore;
  final bool failed;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (failed) {
      return Padding(
        padding: const EdgeInsets.all(BestSpace.lg),
        child: Center(
          child: TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(retryLabel),
          ),
        ),
      );
    }
    if (loading) {
      return const Padding(
        padding: EdgeInsets.all(BestSpace.lg),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          ),
        ),
      );
    }
    return SizedBox(height: hasMore ? BestSpace.md : BestSpace.sm);
  }
}

class _SourcePicker extends StatelessWidget {
  const _SourcePicker({
    required this.current,
    required this.sources,
    required this.onSelected,
    required this.onManage,
    required this.onAdd,
  });

  final SourceAdapter? current;
  final List<SourceAdapter> sources;
  final ValueChanged<SourceAdapter> onSelected;
  final VoidCallback onManage;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, controller) => Material(
        color: theme.colorScheme.surfaceContainerLow,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(BestRadius.sheet),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            const SizedBox(height: BestSpace.sm),
            Container(
              width: 42,
              height: 5,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(BestRadius.pill),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                BestLayout.gutter,
                BestSpace.lg,
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
                          l10n.homeChooseSource,
                          style: BestType.sectionTitle(context),
                        ),
                        const SizedBox(height: BestSpace.xs),
                        Text(
                          l10n.homeSourcesSubtitle,
                          style: BestType.body(context),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.sourcesManage,
                    onPressed: onManage,
                    icon: const Icon(Icons.tune_rounded),
                  ),
                  IconButton(
                    tooltip: l10n.homeAddSources,
                    onPressed: onAdd,
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: sources.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(BestSpace.xxl),
                        child: Text(
                          l10n.homeSourcesEmpty,
                          textAlign: TextAlign.center,
                          style: BestType.body(context),
                        ),
                      ),
                    )
                  : ListView.separated(
                      controller: controller,
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        BestLayout.gutter,
                        BestSpace.sm,
                        BestLayout.gutter,
                        BestSpace.lg,
                      ),
                      itemCount: sources.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: BestSpace.xs),
                      itemBuilder: (context, index) {
                        final source = sources[index];
                        final selected = source.id == current?.id;
                        return ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(BestRadius.lg),
                            side: BorderSide(
                              color: selected
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.outlineVariant,
                            ),
                          ),
                          leading: SourceAvatar(source: source),
                          title: Text(
                            source.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            [
                              homeKindOf(source) == HomeKind.watching
                                  ? l10n.kindAnime
                                  : l10n.kindManga,
                              if (source.language.trim().isNotEmpty)
                                source.language.toUpperCase(),
                            ].join(' · '),
                          ),
                          trailing: selected
                              ? Icon(
                                  Icons.check_circle_rounded,
                                  color: theme.colorScheme.primary,
                                )
                              : null,
                          onTap: () => onSelected(source),
                        );
                      },
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  BestLayout.gutter,
                  BestSpace.sm,
                  BestLayout.gutter,
                  BestSpace.md,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onAdd,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text(l10n.homeAddSources),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
