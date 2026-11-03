import 'package:best_data/best_data.dart';
import 'package:best_domain/best_domain.dart';
import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../actions.dart';
import '../l10n/generated/app_localizations.dart';
import '../labels.dart';
import '../navigation.dart';
import '../progress_label.dart';
import '../providers.dart';

/// The daily edition.
///
/// A returning reader sees the story they left first. Below it sits the live
/// catalogue, one editorial spotlight, the four new destinations, and the
/// weekly challenge. A fresh install gets the guide and the sample player
/// instead, so the app is never an empty screen with a spinner.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static const BrowseKey _guideKey = (
    sourceId: DemoSource.sourceId,
    query: '',
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final discover = ref.watch(discoverProvider);
    final continuing =
        ref.watch(continueProvider).value ?? const <ContinueEntry>[];
    final shelf = ref.watch(libraryProvider).value ?? const <LibraryEntry>[];
    final recs = ref.watch(recommendationsProvider).value;
    final rewards = ref.watch(weeklyRewardsProvider).value;
    final works = discover.value?.works ?? const <Media>[];
    final latest = discover.value?.latest ?? const <Media>[];
    final featured = works.isEmpty ? null : works.first;
    final trending = works.length <= 1
        ? const <Media>[]
        : works.sublist(1, works.length > 13 ? 13 : works.length);
    final sourceCount = ref
        .watch(sourceRegistryProvider)
        .all
        .where((source) => source.id != DemoSource.sourceId)
        .length;

    final samples = ref
            .watch(browseProvider(_guideKey))
            .value
            ?.where((media) => media.kind.isWatching)
            .toList() ??
        const <Media>[];

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(discoverProvider);
          ref.invalidate(curatedProvider);
          ref.invalidate(rankingsProvider);
          ref.invalidate(recommendationsProvider);
          ref.invalidate(weeklyRewardsProvider);
          ref.invalidate(continueProvider);
          ref.invalidate(libraryProvider);
          try {
            await ref.read(discoverProvider.future);
          } catch (_) {
            // The error state is rendered inline.
          }
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: BestWordmark(
                        markSize: 30,
                        tagline: l10n.tagline,
                        label: l10n.appName,
                      ),
                    ),
                    IconButton.outlined(
                      tooltip: l10n.searchAll,
                      onPressed: () => context.push(Routes.browse),
                      style: IconButton.styleFrom(
                        foregroundColor: theme.colorScheme.primary,
                        side: BorderSide(
                          color: theme.colorScheme.outlineVariant,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(BestRadius.sm),
                        ),
                        fixedSize: const Size(46, 46),
                      ),
                      icon: const Icon(Icons.search, size: 20),
                    ),
                    const SizedBox(width: 8),
                    IconButton.outlined(
                      tooltip: l10n.navSettings,
                      onPressed: () => context.push(Routes.settings),
                      style: IconButton.styleFrom(
                        foregroundColor: theme.colorScheme.onSurfaceVariant,
                        side: BorderSide(
                          color: theme.colorScheme.outlineVariant,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(BestRadius.sm),
                        ),
                        fixedSize: const Size(46, 46),
                      ),
                      icon: const Icon(Icons.tune_rounded, size: 20),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                child: Row(
                  children: [
                    Text(
                      l10n.homeEdition.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: BestColors.brass,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.6,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        height: 1,
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                    if (discover.value?.live == true) ...[
                      const SizedBox(width: 10),
                      Text(
                        l10n.homeSourcesLive(sourceCount),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (discover.value != null && !discover.value!.live)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  child: Row(
                    children: [
                      Icon(
                        Icons.cloud_off_outlined,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.guideFallback,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (continuing.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: SectionHeader(
                    index: "01",
                    title: l10n.continueTitle,
                    actionLabel: l10n.seeAll,
                    onAction: () => context.go(Routes.library),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 172,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: continuing.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: BestSpace.md),
                    itemBuilder: (context, index) {
                      final entry = continuing[index];
                      return ContinueCard(
                        title: entry.media.displayTitle,
                        subtitle: entry.unit.displayTitle,
                        coverUrl: entry.media.coverUrl,
                        progress: entry.progress.fraction,
                        progressLabel: continueProgressLabel(l10n, entry),
                        isVideo: entry.media.kind.isWatching,
                        onOpen: () =>
                            openUnit(context, ref, entry.media, entry.unit),
                      );
                    },
                  ),
                ),
              ),
            ],
            if (discover.isLoading && works.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 80),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (discover.hasError && works.isEmpty)
              SliverToBoxAdapter(
                child: EmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: l10n.sourceError,
                  body: '${discover.error}',
                  action: FilledButton.icon(
                    onPressed: () => ref.invalidate(discoverProvider),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: Text(l10n.retry),
                  ),
                ),
              )
            else if (featured != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
                  // A 4:5 poster reads well on a phone; on a tablet an
                  // uncapped one becomes a page-tall wall, so cap the hero and
                  // centre it while the rest of the column keeps its measure.
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: SpotlightCard(
                        title: featured.displayTitle,
                        nativeTitle: featured.nativeTitle,
                        badge: kindLabel(l10n, featured.kind),
                        meta: _metaFor(l10n, featured),
                        coverUrl: featured.coverUrl,
                        actionLabel: featured.kind.isReading
                            ? l10n.startReading
                            : l10n.startWatching,
                        actionIcon: featured.kind.isReading
                            ? Icons.menu_book_rounded
                            : Icons.play_arrow_rounded,
                        onOpen: () => openSeries(context, ref, featured),
                      ),
                    ),
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                child: SectionHeader(
                  index: "02",
                  title: l10n.homeQuickTitle,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final width = (constraints.maxWidth - BestSpace.md) / 2;
                    return Wrap(
                      spacing: BestSpace.md,
                      runSpacing: BestSpace.md,
                      children: [
                        SizedBox(
                          width: width,
                          child: _QuickTile(
                            icon: Icons.explore_outlined,
                            label: l10n.navDiscover,
                            body: l10n.quickDiscoverBody,
                            onTap: () => context.go(Routes.discover),
                          ),
                        ),
                        SizedBox(
                          width: width,
                          child: _QuickTile(
                            icon: Icons.emoji_events_outlined,
                            label: l10n.quickTopRatedBody,
                            body: l10n.topRatedSubtitle,
                            onTap: () => context.push(Routes.topRated),
                          ),
                        ),
                        SizedBox(
                          width: width,
                          child: _QuickTile(
                            icon: Icons.newspaper_outlined,
                            label: l10n.newsTitle,
                            body: l10n.quickNewsBody,
                            onTap: () => context.push(Routes.news),
                          ),
                        ),
                        SizedBox(
                          width: width,
                          child: _QuickTile(
                            icon: Icons.groups_outlined,
                            label: l10n.contributorsTitle,
                            body: l10n.quickContributorsBody,
                            onTap: () => context.push(Routes.contributors),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            if (rewards != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, BestSpace.lg, 20, 0),
                  child: _WeeklyCard(
                    rewards: rewards,
                    onTap: () => context.push(Routes.topRated),
                  ),
                ),
              ),
            if (latest.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: SectionHeader(
                    index: "03",
                    title: l10n.latestTitle,
                    actionLabel: l10n.seeAll,
                    onAction: () => context.go(Routes.discover),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _MediaRail(
                  works: latest,
                  onOpen: (media) => openSeries(context, ref, media),
                ),
              ),
            ],
            if (recs != null && recs.works.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: SectionHeader(
                    index: "04",
                    title:
                        recs.personalised ? l10n.forYouTitle : l10n.picksTitle,
                    actionLabel: l10n.seeAll,
                    onAction: () => context.go(Routes.discover),
                  ),
                ),
              ),
              if (recs.personalised)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                    child: Text(
                      l10n.forYouBecause(recs.genres.join(' · ')),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: _MediaRail(
                  works: recs.works,
                  onOpen: (media) => openSeries(context, ref, media),
                ),
              ),
            ],
            if (trending.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: SectionHeader(
                    index: "05",
                    title: l10n.trendingTitle,
                    actionLabel: l10n.seeAll,
                    onAction: () => context.go(Routes.manga),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _MediaRail(
                  works: trending,
                  ranked: true,
                  onOpen: (media) => openSeries(context, ref, media),
                ),
              ),
            ],
            if (samples.isNotEmpty && shelf.isEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                  child: SectionHeader(
                    index: "06",
                    title: l10n.samplesTitle,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    l10n.samplesBody,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 150,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    itemCount: samples.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: BestSpace.md),
                    itemBuilder: (context, index) {
                      final media = samples[index];
                      return _SampleCard(
                        title: media.displayTitle,
                        badge: l10n.sampleFilmBadge,
                        coverUrl: media.coverUrl,
                        onTap: () => openSeries(context, ref, media),
                      );
                    },
                  ),
                ),
              ),
            ],
            if (shelf.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Container(
                    padding: const EdgeInsets.all(BestSpace.xl),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(BestRadius.md),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const BestMark(size: 38),
                        const SizedBox(height: BestSpace.md),
                        Text(
                          l10n.libraryWaiting,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: BestSpace.xs),
                        Text(
                          l10n.libraryWaitingBody,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.55,
                          ),
                        ),
                        const SizedBox(height: BestSpace.lg),
                        FilledButton.icon(
                          onPressed: () => context.go(Routes.manga),
                          icon: const Icon(Icons.menu_book_rounded, size: 18),
                          label: Text(l10n.openManga),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }
}

String _metaFor(AppLocalizations l10n, Media media) {
  final parts = <String>[
    kindLabel(l10n, media.kind),
    if (media.year != null) '${media.year}',
    if (media.author != null && media.author!.trim().isNotEmpty) media.author!,
    if (media.rating != null) '★ ${media.rating!.toStringAsFixed(1)}',
  ];
  return parts.join(' · ');
}

class _MediaRail extends StatelessWidget {
  const _MediaRail({
    required this.works,
    required this.onOpen,
    this.ranked = false,
  });

  final List<Media> works;
  final void Function(Media) onOpen;
  final bool ranked;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: 288,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        itemCount: works.length,
        separatorBuilder: (context, index) =>
            const SizedBox(width: BestSpace.md),
        itemBuilder: (context, index) {
          final media = works[index];
          return SizedBox(
            width: 132,
            child: MediaCard(
              title: media.displayTitle,
              subtitle: kindLabel(l10n, media.kind),
              coverUrl: media.coverUrl,
              badge: kindLabel(l10n, media.kind),
              rating: media.rating,
              rank: ranked ? index + 1 : null,
              onTap: () => onOpen(media),
            ),
          );
        },
      ),
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({
    required this.icon,
    required this.label,
    required this.body,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(BestRadius.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(BestSpace.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(BestRadius.md),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 22, color: theme.colorScheme.primary),
              const SizedBox(height: BestSpace.sm),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontFamily: BestFonts.display,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WeeklyCard extends StatelessWidget {
  const _WeeklyCard({required this.rewards, required this.onTap});

  final WeeklyRewards rewards;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(BestRadius.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(BestSpace.lg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(BestRadius.md),
            border: Border.all(
              color: BestColors.brass.withValues(alpha: 0.42),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.local_fire_department_outlined,
                    size: 18,
                    color: BestColors.brass,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.weeklyChallengeTitle,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontFamily: BestFonts.display,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    l10n.weeklyStreak(rewards.streakDays),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: BestSpace.md),
              Text(
                l10n.weeklyChallengeBody(rewards.weekPages, rewards.goal),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: BestSpace.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(BestRadius.pill),
                child: LinearProgressIndicator(
                  value: rewards.progress,
                  minHeight: 6,
                  color: BestColors.brass,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: BestSpace.sm),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.weeklyBadgesEarned(
                        rewards.earned.length,
                        RewardBadge.values.length,
                      ),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Text(
                    l10n.weeklyChallengeCta,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SampleCard extends StatelessWidget {
  const _SampleCard({
    required this.title,
    required this.badge,
    required this.coverUrl,
    required this.onTap,
  });

  final String title;
  final String badge;
  final String? coverUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 210,
      child: Material(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(BestRadius.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Row(
            children: [
              SizedBox(
                width: 92,
                height: 150,
                child: BestCover(title: title, url: coverUrl),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(BestSpace.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        badge.toUpperCase(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: BestColors.brass,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontFamily: BestFonts.display,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
