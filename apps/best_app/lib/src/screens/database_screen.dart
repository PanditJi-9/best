import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/generated/app_localizations.dart';
import '../meta/meta_labels.dart';
import '../meta/meta_models.dart';
import '../meta/meta_providers.dart';
import '../meta/meta_widgets.dart';
import '../navigation.dart';

/// The database front page: four public catalogues, one editorial surface.
///
/// It is deliberately not a clone of any of them. AniList supplies the live
/// trending signal, MyAnimeList the community ranking, hwa.so the manhwa shelf
/// and Anime Corner the news. Each keeps its own score and its own colour.
class DatabaseScreen extends ConsumerWidget {
  const DatabaseScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.read(metaRefreshProvider.notifier).bump();
    try {
      await Future.wait([
        ref.read(metaHomeProvider.future),
        ref.read(metaManhwaProvider.future),
      ]);
    } catch (_) {
      // The screen renders each failure inline.
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final home = ref.watch(metaHomeProvider);
    final manhwaAsync = ref.watch(metaManhwaProvider);
    final value = home.value;
    final loading = home.isLoading && value == null;
    final failed = home.hasError && value == null;

    // The shelf comes from its own provider so hwa.so's slow page never holds
    // back the hero and the ranked rails.
    final manhwa = manhwaAsync.value ?? value?.topManhwa ?? const <MetaWork>[];
    final failures = <MetaSource, String>{
      ...?value?.failures,
      if (manhwaAsync.hasError) MetaSource.hwa: manhwaAsync.error.toString(),
    };

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: () => _refresh(ref),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _Masthead(l10n: l10n)),
            SliverToBoxAdapter(
              child: _SearchLauncher(
                hint: l10n.metaSearchHint,
                onTap: () => context.push(Routes.metaSearch),
              ),
            ),
            SliverToBoxAdapter(child: _SourceStrip(l10n: l10n)),
            if (loading)
              const SliverToBoxAdapter(child: _DatabaseSkeleton())
            else if (failed)
              SliverToBoxAdapter(
                child: _DatabaseError(
                  l10n: l10n,
                  onRetry: () => ref.read(metaRefreshProvider.notifier).bump(),
                ),
              )
            else if (value != null) ...[
              if (value.hero != null)
                SliverToBoxAdapter(
                  child: _Hero(
                    work: value.hero!,
                    badge: _heroBadge(value, l10n),
                    l10n: l10n,
                    onOpen: () => _openWork(context, value.hero!),
                    onFind: () => context.push(
                      Routes.browseQuery(value.hero!.displayTitle),
                    ),
                    onSource: value.hero!.siteUrl == null
                        ? null
                        : () => _openExternal(
                              context,
                              l10n,
                              value.hero!.siteUrl!,
                            ),
                  ),
                ),
              SliverToBoxAdapter(
                child: MetaSourceNotice(
                  failures: failures,
                  retryLabel: l10n.retry,
                  onRetry: () => ref.read(metaRefreshProvider.notifier).bump(),
                ),
              ),
              if (value.trending.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: MetaSectionHeader(
                    source: MetaSource.anilist,
                    title: l10n.metaTrending,
                    subtitle: l10n.metaTrendingSub,
                    actionLabel: l10n.seeAll,
                    onAction: () => context.push(
                      Routes.metaList(MetaListKind.anilistTrending),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _PosterRail(
                    works: value.trending.take(10).toList(growable: false),
                    showRank: true,
                    onOpen: (work) => _openWork(context, work),
                  ),
                ),
              ],
              if (value.airing.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: MetaSectionHeader(
                    source: MetaSource.anilist,
                    title: l10n.metaAiring,
                    subtitle: l10n.metaAiringSub,
                    actionLabel: l10n.seeAll,
                    onAction: () => context.push(
                      Routes.metaList(MetaListKind.anilistAiring),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _PosterRail(
                    works: value.airing.take(10).toList(growable: false),
                    onOpen: (work) => _openWork(context, work),
                  ),
                ),
              ],
              if (value.topMal.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: MetaSectionHeader(
                    source: MetaSource.myAnimeList,
                    title: l10n.metaMalTop,
                    subtitle: l10n.metaMalTopSub,
                    actionLabel: l10n.metaFullRanking,
                    onAction: () => context.push(
                      Routes.metaList(MetaListKind.malTop),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _MalRanking(
                    works: value.topMal.take(5).toList(growable: false),
                    onOpen: (work) => _openWork(context, work),
                  ),
                ),
              ],
              if (manhwa.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: MetaSectionHeader(
                    source: MetaSource.hwa,
                    title: l10n.metaHwaTop,
                    subtitle: l10n.metaHwaTopSub,
                    actionLabel: l10n.seeAll,
                    onAction: () => context.push(
                      Routes.metaList(MetaListKind.hwaTop),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _PosterRail(
                    works: manhwa.take(10).toList(growable: false),
                    statusBadges: true,
                    onOpen: (work) => _openWork(context, work),
                  ),
                ),
              ],
              if (value.news.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: MetaSectionHeader(
                    source: MetaSource.animeCorner,
                    title: l10n.metaNews,
                    subtitle: l10n.metaNewsSub,
                    actionLabel: l10n.metaAllNews,
                    onAction: () => _openExternal(
                      context,
                      l10n,
                      MetaSource.animeCorner.homeUrl,
                    ),
                  ),
                ),
                SliverList.separated(
                  itemCount: value.news.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final news = value.news[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: MetaNewsCard(
                        news: news,
                        onTap: () => _openExternal(context, l10n, news.url),
                      ),
                    );
                  },
                ),
              ],
              const SliverToBoxAdapter(child: _Attribution()),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 112)),
          ],
        ),
      ),
    );
  }

  /// The hero falls through to whichever catalogue answered, so its label has
  /// to name that rail instead of always claiming "trending".
  String _heroBadge(MetaHome home, AppLocalizations l10n) {
    if (home.trending.isNotEmpty) return l10n.metaTrending;
    if (home.airing.isNotEmpty) return l10n.metaAiring;
    if (home.topMal.isNotEmpty) return l10n.metaMalTop;
    return l10n.metaHwaTop;
  }

  void _openWork(BuildContext context, MetaWork work) {
    context.push(Routes.metaWork(work.source, work.id));
  }
}

class _Masthead extends StatelessWidget {
  const _Masthead({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: BestColors.aurora,
              ),
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(
                  color: BestColors.blue.withValues(alpha: 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Text(
              'B',
              style: TextStyle(
                fontFamily: BestFonts.display,
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.metaTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  l10n.metaSubtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: l10n.metaSearchTitle,
            onPressed: () => context.push(Routes.metaSearch),
            icon: const Icon(Icons.search_rounded, size: 23),
          ),
        ],
      ),
    );
  }
}

class _SearchLauncher extends StatelessWidget {
  const _SearchLauncher({required this.hint, required this.onTap});

  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Material(
        color: theme.colorScheme.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BestRadius.lg),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 48,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      hint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SourceStrip extends StatelessWidget {
  const _SourceStrip({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(
        children: [
          Text(
            l10n.metaSources,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 9,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final source in MetaSource.values) ...[
                    MetaSourceDot(source: source),
                    const SizedBox(width: 4),
                    Text(
                      source.shortLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.work,
    required this.badge,
    required this.l10n,
    required this.onOpen,
    required this.onFind,
    this.onSource,
  });

  final MetaWork work;
  final String badge;
  final AppLocalizations l10n;
  final VoidCallback onOpen;
  final VoidCallback onFind;
  final VoidCallback? onSource;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(BestRadius.xl),
        child: SizedBox(
          height: 322,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _MetaBanner(work: work),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      BestColors.ink.withValues(alpha: 0.30),
                      BestColors.ink.withValues(alpha: 0.94),
                    ],
                    stops: const [0, 0.45, 1],
                  ),
                ),
              ),
              PositionedDirectional(
                top: 12,
                start: 12,
                end: 12,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: BestColors.ink.withValues(alpha: 0.66),
                        borderRadius: BorderRadius.circular(BestRadius.pill),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.16),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.trending_up_rounded,
                            size: 12,
                            color: BestColors.cyan,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            badge,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              height: 1.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    MetaSourceChip(source: work.source),
                  ],
                ),
              ),
              PositionedDirectional(
                start: 16,
                end: 16,
                bottom: 14,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      work.displayTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        height: 1.12,
                        letterSpacing: -0.4,
                      ),
                    ),
                    if (work.nativeTitle != null &&
                        work.nativeTitle!.trim().isNotEmpty &&
                        work.nativeTitle != work.displayTitle) ...[
                      const SizedBox(height: 3),
                      Text(
                        work.nativeTitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.62),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        MetaScore(
                          score: work.score,
                          source: work.scoreSource,
                          large: true,
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            _heroMeta(work, l10n),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.72),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      work.genres
                          .take(3)
                          .map((genre) => metaGenreLabel(
                                genre,
                                Directionality.of(context) == TextDirection.rtl,
                              ))
                          .join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.64),
                        fontSize: 10,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 11),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilledButton.icon(
                          onPressed: onOpen,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 36),
                            padding: const EdgeInsets.symmetric(horizontal: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(BestRadius.sm),
                            ),
                          ),
                          icon: const Icon(
                            Icons.auto_stories_rounded,
                            size: 16,
                          ),
                          label: Text(
                            l10n.metaDetails,
                            style: const TextStyle(fontSize: 11.5),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: onFind,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 36),
                            padding: const EdgeInsets.symmetric(horizontal: 11),
                            foregroundColor: Colors.white,
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.28),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(BestRadius.sm),
                            ),
                          ),
                          icon: const Icon(Icons.search_rounded, size: 15),
                          label: Text(
                            l10n.metaFindInSources,
                            style: const TextStyle(fontSize: 10.5),
                          ),
                        ),
                        if (onSource != null)
                          IconButton(
                            tooltip: l10n.metaOpenSource,
                            onPressed: onSource,
                            visualDensity: VisualDensity.compact,
                            icon: Icon(
                              Icons.open_in_new_rounded,
                              size: 17,
                              color: Colors.white.withValues(alpha: 0.78),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _heroMeta(MetaWork work, AppLocalizations l10n) {
    final parts = <String>[];
    final format = metaFormatLabel(work.format);
    if (format.isNotEmpty) parts.add(format);
    if (work.episodes != null) {
      parts.add('${work.episodes} ${l10n.metaEpShort}');
    }
    if (work.year != null) parts.add('${work.year}');
    final status = metaStatusLabel(l10n, work.status);
    if (status.isNotEmpty) parts.add(status);
    return parts.join(' · ');
  }
}

class _MetaBanner extends StatelessWidget {
  const _MetaBanner({required this.work});

  final MetaWork work;

  @override
  Widget build(BuildContext context) {
    final url = work.bannerUrl ?? work.coverUrl;
    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            metaSourceColor(work.source).withValues(alpha: 0.45),
            BestColors.ink,
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.auto_awesome_rounded,
          size: 54,
          color: Colors.white.withValues(alpha: 0.12),
        ),
      ),
    );
    if (url == null || url.isEmpty) return fallback;
    return Image.network(
      url,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stack) => fallback,
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : fallback,
    );
  }
}

class _PosterRail extends StatelessWidget {
  const _PosterRail({
    required this.works,
    required this.onOpen,
    this.showRank = false,
    this.statusBadges = false,
  });

  final List<MetaWork> works;
  final ValueChanged<MetaWork> onOpen;
  final bool showRank;
  final bool statusBadges;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: 252,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: works.length,
        separatorBuilder: (context, index) => const SizedBox(width: 11),
        itemBuilder: (context, index) {
          final work = works[index];
          final status = metaStatusLabel(l10n, work.status);
          return MetaPosterCard(
            work: work,
            badge: showRank
                ? '#${index + 1}'
                : statusBadges && status.isNotEmpty
                    ? status
                    : null,
            onTap: () => onOpen(work),
          );
        },
      ),
    );
  }
}

class _MalRanking extends StatelessWidget {
  const _MalRanking({required this.works, required this.onOpen});

  final List<MetaWork> works;
  final ValueChanged<MetaWork> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(BestRadius.lg),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          children: [
            for (var index = 0; index < works.length; index++) ...[
              MetaRankRow(
                work: works[index],
                onTap: () => onOpen(works[index]),
              ),
              if (index != works.length - 1)
                Divider(
                  height: 1,
                  indent: 66,
                  endIndent: 16,
                  color: theme.colorScheme.outlineVariant,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Attribution extends StatelessWidget {
  const _Attribution();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(BestRadius.lg),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 5,
              children: [
                for (final source in MetaSource.values)
                  MetaSourceChip(source: source),
              ],
            ),
            const SizedBox(height: 9),
            Text(
              l10n.metaAttribution,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 9.5,
                height: 1.45,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              l10n.metaAttributionNote,
              style: theme.textTheme.labelSmall?.copyWith(
                color:
                    theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
                fontSize: 9,
                height: 1.45,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DatabaseSkeleton extends StatelessWidget {
  const _DatabaseSkeleton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget block({double height = 14, double width = double.infinity}) {
      return Container(
        height: height,
        width: width,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(BestRadius.sm),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 210,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(BestRadius.xl),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
          ),
          const SizedBox(height: 26),
          block(width: 150, height: 16),
          const SizedBox(height: 12),
          SizedBox(
            height: 180,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 4,
              separatorBuilder: (context, index) => const SizedBox(width: 11),
              itemBuilder: (context, index) => Container(
                width: 120,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(BestRadius.md),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
              ),
            ),
          ),
          const SizedBox(height: 26),
          block(width: 190, height: 16),
          const SizedBox(height: 12),
          Container(
            height: 180,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(BestRadius.lg),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _DatabaseError extends StatelessWidget {
  const _DatabaseError({required this.l10n, required this.onRetry});

  final AppLocalizations l10n;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
      child: EmptyState(
        icon: Icons.cloud_off_rounded,
        title: l10n.metaError,
        body: l10n.metaErrorBody,
        action: FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: Text(l10n.retry),
        ),
      ),
    );
  }
}

Future<void> _openExternal(
  BuildContext context,
  AppLocalizations l10n,
  String url,
) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.metaOpenFailed)),
    );
  }
}
