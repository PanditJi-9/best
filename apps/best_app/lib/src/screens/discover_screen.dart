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

/// Discovery, modelled on the way a film database works: one scored title to
/// lead, a ranked shelf, a personalised shelf, and a real "new chapters" list.
///
/// Nothing here is a recommendation model. Scores come from MangaDex, new
/// chapters come from sources that declare a latest page, and "for you" is the
/// intersection of the genres on the shelf with the live pool.
class DiscoverScreen extends ConsumerWidget {
  const DiscoverScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final feed = ref.watch(discoverProvider);
    final rankings = ref.watch(rankingsProvider);
    final recs = ref.watch(recommendationsProvider).value;
    final picks = ref.watch(curatedProvider).value ?? const <Media>[];
    final rated = rankings.value?.works ?? const <Media>[];
    final latest = feed.value?.latest ?? const <Media>[];
    final feedWorks = feed.value?.works ?? const <Media>[];
    final featured = rated.isEmpty ? null : rated.first;
    final genres = <String>{};
    for (final media in [...rated.take(8), ...feedWorks.take(8)]) {
      genres.addAll(media.genres.take(2));
    }

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(discoverProvider);
          ref.invalidate(rankingsProvider);
          ref.invalidate(recommendationsProvider);
          ref.invalidate(curatedProvider);
          try {
            await ref.read(discoverProvider.future);
          } catch (_) {
            // Rendered inline.
          }
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                child: PageMasthead(
                  index: "03",
                  title: l10n.discoverTitle,
                  subtitle: l10n.discoverSubtitle,
                  trailing: IconButton(
                    tooltip: l10n.topRatedTitle,
                    onPressed: () => context.push(Routes.topRated),
                    icon: const Icon(Icons.emoji_events_outlined),
                  ),
                ),
              ),
            ),
            if (featured != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: SpotlightCard(
                        title: featured.displayTitle,
                        nativeTitle: featured.nativeTitle,
                        badge: '★ ${featured.rating!.toStringAsFixed(1)}',
                        meta: _metaFor(l10n, featured),
                        coverUrl: featured.coverUrl,
                        actionLabel: l10n.startReading,
                        actionIcon: Icons.menu_book_rounded,
                        onOpen: () => openSeries(context, ref, featured),
                      ),
                    ),
                  ),
                ),
              ),
            if (rankings.isLoading && rated.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (rankings.value?.error != null && rated.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: _NoteCard(
                    icon: Icons.star_border_rounded,
                    title: l10n.discoverEmptyRatings,
                    body: l10n.discoverEmptyRatingsBody,
                  ),
                ),
              ),
            if (rated.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: SectionHeader(
                    index: "01",
                    title: l10n.discoverTopRated,
                    actionLabel: l10n.seeAll,
                    onAction: () => context.push(Routes.topRated),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _RatedRail(
                  works: rated.take(12).toList(),
                  onOpen: (media) => openSeries(context, ref, media),
                ),
              ),
            ],
            if (recs != null && recs.works.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: SectionHeader(
                    index: "02",
                    title: recs.personalised
                        ? l10n.discoverForYou
                        : l10n.picksTitle,
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
                child: SizedBox(
                  height: 288,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    itemCount: recs.works.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: BestSpace.md),
                    itemBuilder: (context, index) {
                      final media = recs.works[index];
                      return SizedBox(
                        width: 132,
                        child: MediaCard(
                          title: media.displayTitle,
                          subtitle: kindLabel(l10n, media.kind),
                          coverUrl: media.coverUrl,
                          badge: kindLabel(l10n, media.kind),
                          rating: media.rating,
                          onTap: () => openSeries(context, ref, media),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
            if (picks.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: SectionHeader(
                    index: "03",
                    title: l10n.picksTitle,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 288,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    itemCount: picks.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: BestSpace.md),
                    itemBuilder: (context, index) {
                      final media = picks[index];
                      return SizedBox(
                        width: 132,
                        child: MediaCard(
                          title: media.displayTitle,
                          subtitle: kindLabel(l10n, media.kind),
                          coverUrl: media.coverUrl,
                          badge: kindLabel(l10n, media.kind),
                          rating: media.rating,
                          onTap: () => openSeries(context, ref, media),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: SectionHeader(
                  index: "04",
                  title: l10n.discoverNewChapters,
                ),
              ),
            ),
            if (latest.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                  child: feed.isLoading
                      ? const SizedBox(
                          height: 40,
                          child: Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        )
                      : Text(
                          l10n.newsChaptersEmpty,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                sliver: SliverList.separated(
                  itemCount: latest.take(12).length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: BestSpace.sm),
                  itemBuilder: (context, index) {
                    final media = latest[index];
                    return _ChapterRow(
                      media: media,
                      source: _sourceName(ref, media),
                      onTap: () => openSeries(context, ref, media),
                    );
                  },
                ),
              ),
            if (genres.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: SectionHeader(
                    index: "04",
                    title: l10n.discoverExplore,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Wrap(
                    spacing: BestSpace.sm,
                    runSpacing: BestSpace.sm,
                    children: [
                      for (final genre in genres.take(12))
                        ActionChip(
                          label: Text(genre),
                          onPressed: () =>
                              context.push(Routes.browseQuery(genre)),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, BestSpace.lg, 20, 0),
                child: Text(
                  l10n.discoverScoresNote,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.5,
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

String _sourceName(WidgetRef ref, Media media) {
  final source = ref.watch(sourceRegistryProvider).byId(media.ref.sourceId);
  return source?.name ?? media.ref.sourceId;
}

String _metaFor(AppLocalizations l10n, Media media) {
  final parts = <String>[
    kindLabel(l10n, media.kind),
    if (media.year != null) '${media.year}',
    if (media.genres.isNotEmpty) media.genres.take(2).join(' · '),
  ];
  return parts.join(' · ');
}

class _RatedRail extends StatelessWidget {
  const _RatedRail({required this.works, required this.onOpen});

  final List<Media> works;
  final void Function(Media) onOpen;

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
              rank: index + 1,
              onTap: () => onOpen(media),
            ),
          );
        },
      ),
    );
  }
}

class _ChapterRow extends StatelessWidget {
  const _ChapterRow({
    required this.media,
    required this.source,
    required this.onTap,
  });

  final Media media;
  final String source;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(BestRadius.sm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(BestSpace.sm),
          child: Row(
            children: [
              SizedBox(
                width: 46,
                height: 64,
                child: BestCover(
                  title: media.displayTitle,
                  url: media.coverUrl,
                  radius: BestRadius.sm,
                ),
              ),
              const SizedBox(width: BestSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      media.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontFamily: BestFonts.display,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        source,
                        kindLabel(l10n, media.kind),
                        if (media.status != MediaStatus.unknown)
                          statusLabel(l10n, media.status),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (media.rating != null) ...[
                RatingBadge(score: media.rating!),
                const SizedBox(width: 6),
              ],
              const Icon(Icons.chevron_right_rounded, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(BestSpace.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(BestRadius.md),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: BestSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.45,
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
