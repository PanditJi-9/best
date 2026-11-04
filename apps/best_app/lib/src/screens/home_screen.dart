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
import '../providers.dart';

/// The front page is a reading concierge, not a wall of posters.
///
/// The order is deliberate: resume the thing you were reading, choose a kind,
/// see what actually arrived from your sources, read an editorial pick with
/// enough context to decide, then browse the real ranking and your sources.
/// Nothing here is a made-up statistic; every rail is one of the app's existing
/// live queries.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  /// `null` is the whole catalogue. The other values are reading/watching
  /// families, not raw enum values: webtoons belong with manga, films with
  /// drama.
  MediaKind? _kind;

  bool _matches(Media media) {
    final kind = _kind;
    if (kind == null) return true;
    return switch (kind) {
      MediaKind.manga =>
        media.kind == MediaKind.manga || media.kind == MediaKind.webtoon,
      MediaKind.drama =>
        media.kind == MediaKind.drama || media.kind == MediaKind.film,
      _ => media.kind == kind,
    };
  }

  Future<void> _refresh() async {
    ref.invalidate(discoverProvider);
    ref.invalidate(rankingsProvider);
    ref.invalidate(recommendationsProvider);
    ref.invalidate(curatedProvider);
    ref.invalidate(continueProvider);
    try {
      await Future.wait([
        ref.read(discoverProvider.future),
        ref.read(rankingsProvider.future),
      ]);
    } catch (_) {
      // The screen renders the failure inline.
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final feed = ref.watch(discoverProvider);
    final rankings = ref.watch(rankingsProvider).value;
    final recs = ref.watch(recommendationsProvider).value;
    final curated = ref.watch(curatedProvider).value ?? const <Media>[];
    final continuing =
        ref.watch(continueProvider).value ?? const <ContinueEntry>[];
    final sources = ref
        .watch(sourceRegistryProvider)
        .all
        .where((source) => source.id != DemoSource.sourceId)
        .toList(growable: false);

    final latest = (feed.value?.latest ?? const <Media>[])
        .where(_matches)
        .toList(growable: false);
    final popular = (feed.value?.works ?? const <Media>[])
        .where(_matches)
        .toList(growable: false);
    final rated = (rankings?.works ?? const <Media>[])
        .where(_matches)
        .toList(growable: false);
    final picks = (recs != null && recs.works.isNotEmpty ? recs.works : curated)
        .where(_matches)
        .toList(growable: false);

    final resume = continuing.isEmpty ? null : continuing.first;
    final featured = rated.isNotEmpty
        ? rated.first
        : (popular.isNotEmpty ? popular.first : null);
    final loading = feed.isLoading && popular.isEmpty && latest.isEmpty;
    final failed = feed.hasError && popular.isEmpty && latest.isEmpty;
    final emptyKind = !loading &&
        !failed &&
        latest.isEmpty &&
        popular.isEmpty &&
        rated.isEmpty &&
        picks.isEmpty;

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _Masthead(l10n: l10n)),
            if (resume != null)
              SliverToBoxAdapter(
                child: _ResumeHero(
                  entry: resume,
                  onOpen: () => openUnit(
                    context,
                    ref,
                    resume.media,
                    resume.unit,
                  ),
                ),
              )
            else if (featured != null)
              SliverToBoxAdapter(
                child: _SpotlightHero(
                  media: featured,
                  label:
                      rated.isNotEmpty ? l10n.topRatedTitle : l10n.homePickUp,
                  onOpen: () => openSeries(context, ref, featured),
                ),
              )
            else if (loading)
              const SliverToBoxAdapter(child: _HeroSkeleton())
            else if (failed)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                  child: _NoticeCard(
                    icon: Icons.cloud_off_outlined,
                    title: l10n.sourceError,
                    body: l10n.nothingHereBody,
                    actionLabel: l10n.retry,
                    onAction: () {
                      ref.invalidate(discoverProvider);
                      ref.invalidate(rankingsProvider);
                    },
                  ),
                ),
              )
            else
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                  child: _NoticeCard(
                    icon: Icons.auto_stories_outlined,
                    title: l10n.libraryWaiting,
                    body: l10n.libraryWaitingBody,
                    actionLabel: l10n.openGuide,
                    onAction: () => openGuide(context, ref),
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: _KindBar(
                selected: _kind,
                onSelected: (kind) => setState(() => _kind = kind),
              ),
            ),
            if (feed.value?.live == false && popular.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                  child: _InlineNote(
                    icon: Icons.science_outlined,
                    text: l10n.homeDemoMode,
                    actionLabel: l10n.homeAddSources,
                    onAction: () => context.push(Routes.sources),
                  ),
                ),
              ),
            if (loading) ...[
              const SliverToBoxAdapter(child: _RailSkeleton()),
              const SliverToBoxAdapter(child: _RailSkeleton()),
            ] else if (emptyKind)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
                  child: _NoticeCard(
                    icon: Icons.filter_alt_off_outlined,
                    title: l10n.homeNothingKind,
                    body: l10n.nothingHereBody,
                    actionLabel: l10n.filterAll,
                    onAction: () => setState(() => _kind = null),
                  ),
                ),
              )
            else ...[
              if (latest.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: _SectionHeader(
                    title: l10n.homeNewFromSources,
                    actionLabel: l10n.seeAll,
                    onAction: () => context.push(Routes.news),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _PosterRail(
                    works: latest.take(12).toList(growable: false),
                    badge: l10n.homeLatestBadge,
                    onOpen: (media) => openSeries(context, ref, media),
                  ),
                ),
              ],
              if (picks.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: _SectionHeader(
                    title: l10n.homeForYou,
                    subtitle: recs != null && recs.personalised
                        ? l10n.forYouBecause(recs.genres.join(' · '))
                        : null,
                    actionLabel: l10n.seeAll,
                    onAction: () => context.push(Routes.discover),
                  ),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => Padding(
                      padding: EdgeInsets.fromLTRB(
                        20,
                        index == 0 ? 0 : 10,
                        20,
                        0,
                      ),
                      child: _EditorialCard(
                        media: picks[index],
                        onOpen: () => openSeries(context, ref, picks[index]),
                      ),
                    ),
                    childCount: picks.take(4).length,
                  ),
                ),
              ],
              if (rated.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: _SectionHeader(
                    title: l10n.topRatedTitle,
                    subtitle: l10n.rankingsNote,
                    actionLabel: l10n.seeAll,
                    onAction: () => context.push(Routes.topRated),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _PosterRail(
                    works: rated.take(12).toList(growable: false),
                    ranked: true,
                    onOpen: (media) => openSeries(context, ref, media),
                  ),
                ),
              ],
            ],
            SliverToBoxAdapter(
              child: _SectionHeader(
                title: l10n.mangaSourcesTitle,
                actionLabel:
                    sources.isEmpty ? l10n.homeAddSources : l10n.seeAll,
                onAction: () => context.push(Routes.sources),
              ),
            ),
            SliverToBoxAdapter(
              child: _SourceRail(
                sources: sources,
                onOpen: (source) =>
                    context.push(Routes.browseSource(source.id)),
                onAdd: () => context.push(Routes.sources),
              ),
            ),
            // Clear the floating tab bar: the source rail must not sit under it.
            const SliverToBoxAdapter(child: SizedBox(height: 104)),
          ],
        ),
      ),
    );
  }
}

class _Masthead extends StatelessWidget {
  const _Masthead({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 14, 0),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: BestColors.aurora,
              ),
              borderRadius: BorderRadius.circular(14),
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
                fontSize: 23,
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
                  l10n.appName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                Text(
                  l10n.homeSubtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          _RoundIcon(
            icon: Icons.search_rounded,
            tooltip: l10n.searchAll,
            onTap: () => context.push(Routes.browseQuery('')),
          ),
          const SizedBox(width: 6),
          _RoundIcon(
            icon: Icons.notifications_none_rounded,
            tooltip: l10n.newsTitle,
            onTap: () => context.push(Routes.news),
          ),
        ],
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Icon(icon, size: 21, color: theme.colorScheme.onSurface),
        ),
      ),
    );
  }
}

class _ResumeHero extends StatelessWidget {
  const _ResumeHero({required this.entry, required this.onOpen});

  final ContinueEntry entry;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final media = entry.media;
    final total = entry.progress.total;
    final position = entry.progress.position;
    final fraction = total <= 0
        ? (entry.progress.completed ? 1.0 : 0.0)
        : (position / total).clamp(0.0, 1.0);
    final percent = (fraction * 100).round();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(BestRadius.xl),
        child: SizedBox(
          height: 198,
          child: Stack(
            fit: StackFit.expand,
            children: [
              BestBackdrop(
                title: media.displayTitle,
                url: media.coverUrl,
                blur: 30,
                opacity: 0.72,
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: AlignmentDirectional.centerStart,
                    end: AlignmentDirectional.centerEnd,
                    colors: [
                      theme.colorScheme.surface.withValues(alpha: 0.18),
                      theme.colorScheme.surface.withValues(alpha: 0.92),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    SizedBox(
                      width: 86,
                      height: 129,
                      child: BestCover(
                        title: media.displayTitle,
                        url: media.coverUrl,
                        radius: BestRadius.md,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            l10n.homePickUp.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1,
                              fontSize: 10,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            media.displayTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${kindLabel(l10n, media.kind)} · '
                            '${l10n.menuChaptersShort} '
                            '${shortNumber(entry.unit.number)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius:
                                BorderRadius.circular(BestRadius.pill),
                            child: LinearProgressIndicator(
                              value: fraction,
                              minHeight: 4,
                              color: theme.colorScheme.primary,
                              backgroundColor:
                                  theme.colorScheme.surfaceContainerHighest,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              Text(
                                '$percent%',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const Spacer(),
                              SizedBox(
                                height: 34,
                                child: FilledButton.icon(
                                  onPressed: onOpen,
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size(0, 34),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        BestRadius.sm,
                                      ),
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.play_arrow_rounded,
                                    size: 17,
                                  ),
                                  label: Text(
                                    l10n.continueReading,
                                    style: const TextStyle(fontSize: 11.5),
                                  ),
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
            ],
          ),
        ),
      ),
    );
  }
}

class _SpotlightHero extends StatelessWidget {
  const _SpotlightHero({
    required this.media,
    required this.label,
    required this.onOpen,
  });

  final Media media;
  final String label;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(BestRadius.xl),
        child: SizedBox(
          height: 232,
          child: Stack(
            fit: StackFit.expand,
            children: [
              BestBackdrop(
                title: media.displayTitle,
                url: media.coverUrl,
                blur: 24,
                opacity: 0.8,
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      theme.colorScheme.surface.withValues(alpha: 0.05),
                      theme.colorScheme.surface.withValues(alpha: 0.55),
                      theme.colorScheme.surface.withValues(alpha: 0.97),
                    ],
                    stops: const [0, 0.45, 1],
                  ),
                ),
              ),
              PositionedDirectional(
                start: 16,
                end: 16,
                bottom: 14,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    SizedBox(
                      width: 92,
                      height: 138,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(BestRadius.md),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.45),
                              blurRadius: 22,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: BestCover(
                          title: media.displayTitle,
                          url: media.coverUrl,
                          radius: BestRadius.md,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.auto_awesome_rounded,
                                size: 13,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            media.displayTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            media.genres.take(3).join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              if (media.rating != null) ...[
                                RatingBadge(
                                    score: media.rating!, compact: true),
                                const SizedBox(width: 8),
                              ],
                              Flexible(
                                child: Text(
                                  statusLabel(l10n, media.status),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            height: 36,
                            child: FilledButton.icon(
                              onPressed: onOpen,
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(0, 36),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(BestRadius.sm),
                                ),
                              ),
                              icon: const Icon(
                                Icons.menu_book_rounded,
                                size: 17,
                              ),
                              label: Text(
                                l10n.startReading,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
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
}

class _KindBar extends StatelessWidget {
  const _KindBar({required this.selected, required this.onSelected});

  final MediaKind? selected;
  final ValueChanged<MediaKind?> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final options = <(MediaKind?, String)>[
      (null, l10n.filterAll),
      (MediaKind.manga, l10n.kindManga),
      (MediaKind.manhwa, l10n.kindManhwa),
      (MediaKind.manhua, l10n.kindManhua),
      (MediaKind.anime, l10n.kindAnime),
      (MediaKind.drama, l10n.kindDrama),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: SizedBox(
        height: 36,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: options.length,
          separatorBuilder: (context, index) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final option = options[index];
            return _KindChip(
              label: option.$2,
              selected: option.$1 == selected,
              onTap: () => onSelected(option.$1),
            );
          },
        ),
      ),
    );
  }
}

class _KindChip extends StatelessWidget {
  const _KindChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(BestRadius.pill),
      child: AnimatedContainer(
        duration: BestMotion.fast,
        curve: BestMotion.curve,
        padding: const EdgeInsets.symmetric(horizontal: 15),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(BestRadius.pill),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          style: theme.textTheme.labelMedium?.copyWith(
            color: selected
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 26, 14, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3,
            height: 17,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(BestRadius.pill),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                textStyle: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

class _PosterRail extends StatelessWidget {
  const _PosterRail({
    required this.works,
    required this.onOpen,
    this.badge,
    this.ranked = false,
  });

  final List<Media> works;
  final ValueChanged<Media> onOpen;
  final String? badge;
  final bool ranked;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 224,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: works.length,
        separatorBuilder: (context, index) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final media = works[index];
          return SizedBox(
            width: 122,
            child: PosterTile(
              title: media.displayTitle,
              coverUrl: media.coverUrl,
              badge: ranked ? '#${index + 1}' : badge,
              genres: media.genres,
              rating: media.rating,
              onTap: () => onOpen(media),
            ),
          );
        },
      ),
    );
  }
}

class _EditorialCard extends StatelessWidget {
  const _EditorialCard({required this.media, required this.onOpen});

  final Media media;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(BestRadius.lg),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(BestRadius.lg),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(BestRadius.lg),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 78,
                height: 117,
                child: BestCover(
                  title: media.displayTitle,
                  url: media.coverUrl,
                  radius: BestRadius.sm,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      media.displayTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      media.genres.take(3).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        if (media.rating != null) ...[
                          RatingBadge(score: media.rating!, compact: true),
                          const SizedBox(width: 7),
                        ],
                        Flexible(
                          child: Text(
                            '${kindLabel(l10n, media.kind)} · '
                            '${statusLabel(l10n, media.status)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (media.synopsis != null &&
                        media.synopsis!.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        media.synopsis!.replaceAll(RegExp(r'\s+'), ' ').trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 11,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceRail extends StatelessWidget {
  const _SourceRail({
    required this.sources,
    required this.onOpen,
    required this.onAdd,
  });

  final List<SourceAdapter> sources;
  final ValueChanged<SourceAdapter> onOpen;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (sources.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: _NoticeCard(
          icon: Icons.extension_outlined,
          title: l10n.mangaNoSourcesTitle,
          body: l10n.mangaNoSourcesBody,
          actionLabel: l10n.homeAddSources,
          onAction: onAdd,
        ),
      );
    }
    return SizedBox(
      height: 54,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: sources.length + 1,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == sources.length) {
            return _AddSourceChip(label: l10n.homeAddSources, onTap: onAdd);
          }
          final source = sources[index];
          return _SourceChip(source: source, onTap: () => onOpen(source));
        },
      ),
    );
  }
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({required this.source, required this.onTap});

  final SourceAdapter source;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final letter = source.name.trim().isEmpty
        ? '?'
        : String.fromCharCode(source.name.trim().runes.first);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(BestRadius.md),
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(7, 7, 12, 7),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(BestRadius.md),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.colorScheme.primary,
                    theme.colorScheme.secondary,
                  ],
                ),
                borderRadius: BorderRadius.circular(BestRadius.sm),
              ),
              child: Text(
                letter,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 110),
              child: Text(
                source.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 11.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddSourceChip extends StatelessWidget {
  const _AddSourceChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(BestRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(BestRadius.md),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
                fontSize: 11.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(BestRadius.lg),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(BestRadius.md),
            ),
            child: Icon(icon, size: 21, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onAction,
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

class _InlineNote extends StatelessWidget {
  const _InlineNote({
    required this.icon,
    required this.text,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String text;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              minimumSize: const Size(0, 30),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

class _HeroSkeleton extends StatelessWidget {
  const _HeroSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Container(
        height: 198,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(BestRadius.xl),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
    );
  }
}

class _RailSkeleton extends StatelessWidget {
  const _RailSkeleton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 130,
            height: 15,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(BestRadius.pill),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 170,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 4,
              separatorBuilder: (context, index) => const SizedBox(width: 10),
              itemBuilder: (context, index) => Container(
                width: 110,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(BestRadius.md),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
