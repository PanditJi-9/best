import 'dart:async';

import 'package:best_data/best_data.dart';
import 'package:best_domain/best_domain.dart';
import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../actions.dart';
import '../extension_host.dart';
import '../l10n/generated/app_localizations.dart';
import '../labels.dart';
import '../navigation.dart';
import '../providers.dart';

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

  /// Every source the reader installed, manga and anime alike. No switch is
  /// shown: a source already knows what it publishes, and a reader who never
  /// adds an anime extension should never see an anime control.
  List<SourceAdapter> _sources() {
    return ref.read(sourceRegistryProvider).all.toList(growable: false);
  }

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

    try {
      final works = await _fetch(source, feed, page);
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
      await repository.setInLibrary(media.id, true);
      if (!mounted) return;
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
    final sources = _sources();
    SourceAdapter? current;
    for (final source in sources) {
      if (source.id == _sourceId) {
        current = source;
        break;
      }
    }
    current ??= sources.isEmpty ? null : sources.first;
    final feed = _feed == _Feed.latest && current is LatestSource
        ? _Feed.latest
        : _Feed.popular;

    // The source list can arrive after the first frame (extensions load
    // asynchronously) or change when a source is installed. Binding here keeps
    // the first real source supplied without a state write during build.
    if (!_initialised &&
        current != null &&
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
              BestSpace.md,
              BestSpace.sm,
              0,
            ),
            child: Row(
              children: [
                const BestMark(size: 40),
                const SizedBox(width: BestSpace.md),
                Expanded(
                  child: Text(
                    l10n.appName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                      height: 1,
                      letterSpacing: BestType.tracking(context, -0.7),
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('home-unified-search'),
                  tooltip: l10n.searchEverything,
                  onPressed: () => context.push(Routes.metaSearch),
                  icon: const Icon(Icons.search_rounded),
                ),
                IconButton(
                  key: const ValueKey('home-settings'),
                  tooltip: l10n.navSettings,
                  onPressed: () => context.push(Routes.settings),
                  icon: const Icon(Icons.settings_outlined),
                ),
              ],
            ),
          ),
          const SizedBox(height: BestSpace.sm),
          _SourceStrip(
            sources: sources,
            current: current,
            onSelected: _selectSource,
            onManage: () => _openSourcePicker(context, current, sources),
            manageLabel: l10n.homeChooseSource,
          ),
          const SizedBox(height: BestSpace.sm),
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
          Expanded(
            child: _body(context, l10n, current, feed),
          ),
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
      return _scrollableEmpty(
        EmptyState(
          icon: Icons.extension_outlined,
          title: l10n.mangaNoSourcesTitle,
          body: l10n.mangaNoSourcesBody,
          action: FilledButton.icon(
            onPressed: () => context.push(
              Routes.sources,
            ),
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
          body: _error!,
          action: FilledButton.icon(
            onPressed: () => _load(reset: true),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(l10n.retry),
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
                final columns = width >= 840
                    ? 5
                    : width >= 600
                        ? 4
                        : 3;
                final tileWidth =
                    (width - (columns - 1) * BestSpace.md) / columns;
                return SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: BestSpace.lg,
                    crossAxisSpacing: BestSpace.md,
                    mainAxisExtent: tileWidth * 1.5 + 50,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final media = _works[index];
                      return PosterTile(
                        title: media.displayTitle,
                        coverUrl: media.coverUrl,
                        badge: kindLabel(l10n, media.kind),
                        genres: media.genres.isEmpty ? const [] : media.genres,
                        rating: media.rating,
                        inLibrary: media.inLibrary,
                        onTap: () => openSeries(context, ref, media),
                        onLongPress: () => _toggleShelf(media, l10n),
                      );
                    },
                    childCount: _works.length,
                  ),
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
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(BestRadius.pill),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(BestRadius.pill),
          child: Container(
            padding: const EdgeInsetsDirectional.only(start: 6, end: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(BestRadius.pill),
              border: Border.all(
                color: selected
                    ? theme.colorScheme.primary.withValues(alpha: 0.55)
                    : theme.colorScheme.outlineVariant,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SourceAvatar(source: source, size: 32),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: Text(
                    source.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      color: selected
                          ? theme.colorScheme.onPrimaryContainer
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

/// A site's real icon when it has one, a typographic monogram otherwise. The
/// anime side of the catalogue shipped text-only rows for months; an avatar is
/// the fastest way to tell seven sites apart.
class _SourceAvatar extends ConsumerWidget {
  const _SourceAvatar({required this.source, this.size = 40});

  final SourceAdapter source;
  final double size;

  String? _iconUrl(WidgetRef ref) {
    if (source is JsonSourceAdapter) {
      return (source as JsonSourceAdapter).pack.iconUrl;
    }
    if (source is SuwayomiSource) {
      return (source as SuwayomiSource).info.iconUrl;
    }
    if (source is ExtensionSourceAdapter) {
      final package = (source as ExtensionSourceAdapter).info.packageName;
      final entries =
          ref.watch(extensionDirectoryProvider).value?.entries ?? const [];
      for (final entry in entries) {
        if (entry.packageName == package &&
            entry.iconUrl != null &&
            entry.iconUrl!.isNotEmpty) {
          return entry.iconUrl;
        }
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final url = _iconUrl(ref);
    final initial = source.name.trim().isEmpty
        ? '?'
        : String.fromCharCode(source.name.trim().runes.first).toUpperCase();
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.14),
        shape: BoxShape.circle,
      ),
      child: Text(
        initial,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w900,
          fontSize: size * 0.42,
        ),
      ),
    );
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: url == null
            ? fallback
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) => fallback,
              ),
      ),
    );
  }
}

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
        for (final entry in options.entries)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 6),
            child: InkWell(
              key: ValueKey('home-feed-${entry.key.name}'),
              onTap: () => onSelected(entry.key),
              borderRadius: BorderRadius.circular(BestRadius.pill),
              child: AnimatedContainer(
                duration: BestMotion.fast,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: entry.key == selected
                      ? theme.colorScheme.primary.withValues(alpha: 0.14)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(BestRadius.pill),
                ),
                child: Text(
                  entry.value,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: entry.key == selected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                    fontWeight: entry.key == selected
                        ? FontWeight.w800
                        : FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
      ],
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
    required this.onAdd,
  });

  final SourceAdapter? current;
  final List<SourceAdapter> sources;
  final ValueChanged<SourceAdapter> onSelected;
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
                          leading: _SourceAvatar(source: source),
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
