import 'package:best_data/best_data.dart';
import 'package:best_domain/best_domain.dart';
import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../actions.dart';
import '../labels.dart';
import '../l10n/generated/app_localizations.dart';
import '../navigation.dart';
import '../providers.dart';

/// The catalogue-first front door.
///
/// The layout deliberately keeps the covers in charge: a compact app bar,
/// category tabs and a three-column poster grid make it possible to scan a
/// source at a glance. Search, news and source management stay one tap away.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

enum _HomeFeed { latest, popular, rated, recommended }

class _HomeScreenState extends ConsumerState<HomeScreen> {
  _HomeFeed _feed = _HomeFeed.latest;

  Future<void> _refresh() async {
    ref.invalidate(resumeProvider);
    ref.invalidate(discoverProvider);
    ref.invalidate(rankingsProvider);
    ref.invalidate(recommendationsProvider);
    try {
      await switch (_feed) {
        _HomeFeed.latest || _HomeFeed.popular =>
          ref.read(discoverProvider.future),
        _HomeFeed.rated => ref.read(rankingsProvider.future),
        _HomeFeed.recommended => ref.read(recommendationsProvider.future),
      };
    } catch (_) {
      // The empty state gives the reader an honest retry action. The rest of
      // the home screen, including their saved progress, remains available.
    }
  }

  void _openSourcePicker(
    BuildContext context,
    List<SourceAdapter> sources,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _SourcePicker(
        sources: sources,
        onRefresh: _refresh,
        onOpen: (source) {
          Navigator.of(sheetContext).pop();
          context.push(Routes.browseSource(source.id));
        },
        onManage: () {
          Navigator.of(sheetContext).pop();
          context.push(Routes.sources);
        },
      ),
    );
  }

  List<_HomeGridItem> _itemsFor({
    required List<Media> works,
    required List<ResumeSlot> slots,
  }) {
    final seen = <String>{};
    final items = <_HomeGridItem>[];

    // A reader's active chapter belongs in the same fast-scanning grid rather
    // than growing a second, competing hero above it. It also means the first
    // card is always a useful action when the app is reopened.
    if (_feed == _HomeFeed.latest && slots.isNotEmpty) {
      final slot = slots.first;
      seen.add(slot.media.id);
      items.add(_HomeGridItem(media: slot.media, slot: slot));
    }

    for (final media in works) {
      if (seen.add(media.id)) {
        items.add(_HomeGridItem(media: media));
      }
    }
    return List<_HomeGridItem>.unmodifiable(items.take(30));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final continuing = ref.watch(resumeProvider);
    final slots = continuing.value ?? const <ResumeSlot>[];
    final discovery = ref.watch(discoverProvider);
    final rankings = ref.watch(rankingsProvider);
    final recommendations = ref.watch(recommendationsProvider);
    final sources = ref
        .watch(sourceRegistryProvider)
        .all
        .where((source) => source.id != DemoSource.sourceId)
        .toList(growable: false);

    // A recommendation is only actionable when its adapter is still enabled.
    // Resume cards remain available even after a source disappears, since the
    // reader may still resolve them through a compatible fallback.
    bool available(Media media) =>
        sources.any((source) => source.id == media.ref.sourceId);

    final latest = (discovery.value?.latest ?? const <Media>[])
        .where(available)
        .toList(growable: false);
    final popular = (discovery.value?.works ?? const <Media>[])
        .where(available)
        .toList(growable: false);
    final rated = (rankings.value?.works ?? const <Media>[])
        .where(available)
        .toList(growable: false);
    final personalised = (recommendations.value?.works ?? const <Media>[])
        .where(available)
        .toList(growable: false);

    final selectedWorks = switch (_feed) {
      _HomeFeed.latest => latest,
      _HomeFeed.popular => popular,
      _HomeFeed.rated => rated,
      _HomeFeed.recommended => personalised,
    };
    final items = _itemsFor(works: selectedWorks, slots: slots);
    final loading = switch (_feed) {
      _HomeFeed.latest || _HomeFeed.popular => discovery.isLoading,
      _HomeFeed.rated => rankings.isLoading,
      _HomeFeed.recommended => recommendations.isLoading,
    };
    final error = switch (_feed) {
      _HomeFeed.latest || _HomeFeed.popular => discovery.hasError,
      _HomeFeed.rated => rankings.hasError,
      _HomeFeed.recommended => recommendations.hasError,
    };

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  BestLayout.gutter,
                  BestSpace.lg,
                  BestLayout.gutter,
                  BestSpace.md,
                ),
                child: _HomeHeader(
                  title: l10n.appName,
                  searchLabel: l10n.searchEverything,
                  newsLabel: l10n.newsTitle,
                  sourcesLabel: l10n.sources,
                  onSearch: () => context.push(Routes.metaSearch),
                  onNews: () => context.push(Routes.news),
                  onSources: () => _openSourcePicker(context, sources),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: _HomeTabs(
                selected: _feed,
                onSelected: (feed) => setState(() => _feed = feed),
                labels: <_HomeFeed, String>{
                  _HomeFeed.latest: l10n.homeLatest,
                  _HomeFeed.popular: l10n.homePopular,
                  _HomeFeed.rated: l10n.topRatedTitle,
                  _HomeFeed.recommended: l10n.homeRecommended,
                },
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: BestSpace.lg)),
            if (items.isNotEmpty)
              _HomePosterGrid(
                items: items,
                feed: _feed,
                onOpen: (item) {
                  if (item.slot != null) {
                    openUnit(context, ref, item.slot!.media, item.slot!.unit);
                  } else {
                    openSeries(context, ref, item.media);
                  }
                },
              )
            else if (loading)
              const SliverPosterGridSkeleton()
            else
              SliverFillRemaining(
                hasScrollBody: false,
                child: _HomeEmpty(
                  title: _emptyTitle(l10n, sources.isEmpty),
                  body: _emptyBody(l10n, error, sources.isEmpty),
                  icon: sources.isEmpty
                      ? Icons.extension_outlined
                      : error
                          ? Icons.cloud_off_outlined
                          : Icons.auto_stories_outlined,
                  actionLabel: sources.isEmpty ? l10n.homeAddSources : l10n.retry,
                  onAction: sources.isEmpty
                      ? () => context.push(Routes.sources)
                      : _refresh,
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: BestSpace.xxl)),
          ],
        ),
      ),
    );
  }

  String _emptyTitle(AppLocalizations l10n, bool noSources) {
    if (noSources) return l10n.mangaNoSourcesTitle;
    return switch (_feed) {
      _HomeFeed.latest => l10n.homeNoLatest,
      _HomeFeed.popular => l10n.homeNoResults,
      _HomeFeed.rated => l10n.homeNoRatings,
      _HomeFeed.recommended => l10n.homeNoRecommendations,
    };
  }

  String _emptyBody(AppLocalizations l10n, bool error, bool noSources) {
    if (noSources) return l10n.mangaNoSourcesBody;
    return error ? l10n.sourceError : l10n.homeDiscoveryBody;
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.title,
    required this.searchLabel,
    required this.newsLabel,
    required this.sourcesLabel,
    required this.onSearch,
    required this.onNews,
    required this.onSources,
  });

  final String title;
  final String searchLabel;
  final String newsLabel;
  final String sourcesLabel;
  final VoidCallback onSearch;
  final VoidCallback onNews;
  final VoidCallback onSources;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        const BestMark(size: 48),
        const SizedBox(width: BestSpace.md),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontSize: 27,
              fontWeight: FontWeight.w800,
              height: 1,
              letterSpacing: BestType.tracking(context, -0.7),
            ),
          ),
        ),
        IconButton(
          key: const ValueKey('home-unified-search'),
          tooltip: searchLabel,
          onPressed: onSearch,
          icon: const Icon(Icons.search_rounded),
        ),
        IconButton(
          key: const ValueKey('home-news'),
          tooltip: newsLabel,
          onPressed: onNews,
          icon: const Icon(Icons.notifications_none_rounded),
        ),
        IconButton(
          key: const ValueKey('home-source-picker'),
          tooltip: sourcesLabel,
          onPressed: onSources,
          icon: const Icon(Icons.dns_outlined),
        ),
      ],
    );
  }
}

class _HomeTabs extends StatelessWidget {
  const _HomeTabs({
    required this.selected,
    required this.onSelected,
    required this.labels,
  });

  final _HomeFeed selected;
  final ValueChanged<_HomeFeed> onSelected;
  final Map<_HomeFeed, String> labels;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SizedBox(
        height: 54,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsetsDirectional.only(
            start: BestLayout.gutter,
            end: BestLayout.gutter,
          ),
          itemCount: _HomeFeed.values.length,
          separatorBuilder: (context, index) => const SizedBox(width: 4),
          itemBuilder: (context, index) {
            final feed = _HomeFeed.values[index];
            final isSelected = feed == selected;
            return Semantics(
              button: true,
              selected: isSelected,
              child: InkWell(
                key: ValueKey('home-tab-${feed.name}'),
                onTap: () => onSelected(feed),
                child: AnimatedContainer(
                  duration: BestMotionPolicy.of(context, BestMotion.normal),
                  curve: BestMotion.curve,
                  alignment: Alignment.center,
                  padding: const EdgeInsetsDirectional.only(
                    start: BestSpace.md,
                    end: BestSpace.md,
                    top: 2,
                  ),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: isSelected
                            ? theme.colorScheme.primary
                            : Colors.transparent,
                        width: 4,
                      ),
                    ),
                  ),
                  child: Text(
                    labels[feed]!,
                    maxLines: 1,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: isSelected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                      fontSize: 17,
                      fontWeight:
                          isSelected ? FontWeight.w800 : FontWeight.w500,
                      height: 1,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HomeGridItem {
  const _HomeGridItem({required this.media, this.slot});

  final Media media;
  final ResumeSlot? slot;
}

class _HomePosterGrid extends StatelessWidget {
  const _HomePosterGrid({
    required this.items,
    required this.feed,
    required this.onOpen,
  });

  final List<_HomeGridItem> items;
  final _HomeFeed feed;
  final ValueChanged<_HomeGridItem> onOpen;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
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
              mainAxisSpacing: BestSpace.xl,
              crossAxisSpacing: BestSpace.md,
              mainAxisExtent: tileWidth * 1.5 + 57,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final item = items[index];
                final media = item.media;
                final genres = media.genres.isEmpty
                    ? <String>[kindLabel(AppLocalizations.of(context), media.kind)]
                    : media.genres;
                return PosterTile(
                  title: media.displayTitle,
                  coverUrl: media.coverUrl,
                  badge: _badgeFor(
                    AppLocalizations.of(context),
                    media,
                    item.slot,
                  ),
                  genres: genres,
                  progress: item.slot?.fraction ?? 0,
                  onTap: () => onOpen(item),
                );
              },
              childCount: items.length,
            ),
          );
        },
      ),
    );
  }

  String? _badgeFor(
    AppLocalizations l10n,
    Media media,
    ResumeSlot? slot,
  ) {
    if (slot != null) return l10n.continueTitle;
    if (media.status != MediaStatus.unknown) {
      return statusLabel(l10n, media.status);
    }
    return feed == _HomeFeed.latest ? l10n.homeLatestBadge : null;
  }
}

class _HomeEmpty extends StatelessWidget {
  const _HomeEmpty({
    required this.title,
    required this.body,
    required this.icon,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String body;
  final IconData icon;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: BestLayout.gutter),
        child: EmptyState(
          icon: icon,
          title: title,
          body: body,
          action: FilledButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(actionLabel),
          ),
        ),
      );
}

enum _SourceFilter { all, arabic, english }

class _SourcePicker extends StatefulWidget {
  const _SourcePicker({
    required this.sources,
    required this.onRefresh,
    required this.onOpen,
    required this.onManage,
  });

  final List<SourceAdapter> sources;
  final Future<void> Function() onRefresh;
  final ValueChanged<SourceAdapter> onOpen;
  final VoidCallback onManage;

  @override
  State<_SourcePicker> createState() => _SourcePickerState();
}

class _SourcePickerState extends State<_SourcePicker> {
  _SourceFilter _filter = _SourceFilter.all;

  bool _matches(SourceAdapter source) {
    final language = source.language.toLowerCase();
    return switch (_filter) {
      _SourceFilter.all => true,
      _SourceFilter.arabic => language == 'all' || language.startsWith('ar'),
      _SourceFilter.english => language == 'all' || language.startsWith('en'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sources = widget.sources.where(_matches).toList(growable: false);
    final labels = <_SourceFilter, String>{
      _SourceFilter.arabic: l10n.homeSourcesArabic,
      _SourceFilter.english: l10n.homeSourcesEnglish,
      _SourceFilter.all: l10n.filterAll,
    };

    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.44,
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
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(BestRadius.lg),
                      border: Border.all(
                        color:
                            theme.colorScheme.primary.withValues(alpha: 0.38),
                      ),
                    ),
                    child: Icon(
                      Icons.dns_rounded,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: BestSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.homeChooseSource,
                          style: BestType.sectionTitle(context).copyWith(
                            fontSize: 22,
                          ),
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
                    tooltip: l10n.homeRefreshSources,
                    onPressed: () => widget.onRefresh(),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
            ),
            _SourceFilterTabs(
              selected: _filter,
              labels: labels,
              onSelected: (filter) => setState(() => _filter = filter),
            ),
            const SizedBox(height: BestSpace.sm),
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
                      itemBuilder: (context, index) => _SourceRow(
                        source: sources[index],
                        onTap: () => widget.onOpen(sources[index]),
                      ),
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
                  child: OutlinedButton.icon(
                    onPressed: widget.onManage,
                    icon: const Icon(Icons.tune_rounded, size: 18),
                    label: Text(l10n.homeManageSources),
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

class _SourceFilterTabs extends StatelessWidget {
  const _SourceFilterTabs({
    required this.selected,
    required this.labels,
    required this.onSelected,
  });

  final _SourceFilter selected;
  final Map<_SourceFilter, String> labels;
  final ValueChanged<_SourceFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: BestLayout.gutter),
      child: Row(
        children: [
          for (final filter in _SourceFilter.values) ...[
            if (filter != _SourceFilter.values.first)
              const SizedBox(width: BestSpace.sm),
            Expanded(
              child: Semantics(
                button: true,
                selected: filter == selected,
                child: InkWell(
                  onTap: () => onSelected(filter),
                  borderRadius: BorderRadius.circular(BestRadius.md),
                  child: AnimatedContainer(
                    duration: BestMotionPolicy.of(context, BestMotion.normal),
                    curve: BestMotion.curve,
                    height: 46,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: filter == selected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(BestRadius.md),
                      border: Border.all(
                        color: filter == selected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outlineVariant,
                      ),
                    ),
                    child: Text(
                      labels[filter]!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: filter == selected
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurfaceVariant,
                        fontWeight: filter == selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.source, required this.onTap});

  final SourceAdapter source;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sourceName = source.name.trim();
    final initial = sourceName.isEmpty ? '?' : sourceName.substring(0, 1);
    final language = source.language.trim().isEmpty
        ? 'ALL'
        : source.language.trim().toUpperCase();
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(BestRadius.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(BestRadius.lg),
        child: Container(
          padding: const EdgeInsets.all(BestSpace.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(BestRadius.lg),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(BestRadius.md),
                ),
                child: Text(
                  initial,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: BestSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      language,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: BestType.meta(context),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_rounded,
                color: theme.colorScheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
