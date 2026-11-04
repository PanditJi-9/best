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

/// A film-database detail page: one poster, one score per community, the
/// facts the provider actually published, and a way to find the work in the
/// person's own reading sources.
class MetaDetailScreen extends ConsumerWidget {
  const MetaDetailScreen({
    super.key,
    required this.source,
    required this.id,
  });

  final MetaSource source;
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(metaDetailProvider(MetaKey(source, id)));
    return Scaffold(
      body: async.when(
        loading: () => _DetailLoading(title: l10n.metaLoading),
        error: (error, stack) => _DetailError(
          l10n: l10n,
          message: error.toString(),
          onRetry: () => ref.read(metaRefreshProvider.notifier).bump(),
        ),
        data: (work) => _DetailBody(work: work),
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.work});

  final MetaWork work;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final arabic = Directionality.of(context) == TextDirection.rtl;
    final links = _uniqueLinks(work.links);

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: 300,
          backgroundColor: theme.colorScheme.surface,
          surfaceTintColor: Colors.transparent,
          leadingWidth: 58,
          leading: Padding(
            padding: const EdgeInsetsDirectional.only(start: 8),
            child: _CircleAction(
              icon: Icons.arrow_back_rounded,
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onTap: () => context.pop(),
            ),
          ),
          actions: [
            if (work.siteUrl != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: _CircleAction(
                  icon: Icons.open_in_new_rounded,
                  tooltip: l10n.metaOpenSource,
                  onTap: () => _open(context, l10n, work.siteUrl!),
                ),
              ),
          ],
          flexibleSpace: FlexibleSpaceBar(
            collapseMode: CollapseMode.parallax,
            background: Stack(
              fit: StackFit.expand,
              children: [
                _DetailBanner(work: work),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        BestColors.ink.withValues(alpha: 0.12),
                        theme.colorScheme.surface,
                      ],
                      stops: const [0, 0.55, 1],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 108,
                  height: 162,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(BestRadius.md),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: BestCover(
                    title: work.displayTitle,
                    url: work.coverUrl,
                    radius: BestRadius.md,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          MetaSourceChip(source: work.source),
                          const SizedBox(width: 6),
                          if (work.kind != MetaKind.unknown)
                            Text(
                              metaKindLabel(l10n, work.kind),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 9.5,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        work.displayTitle,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          height: 1.12,
                          letterSpacing: -0.4,
                        ),
                      ),
                      if (work.nativeTitle != null &&
                          work.nativeTitle!.trim().isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          work.nativeTitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                      const SizedBox(height: 9),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          MetaScore(
                            score: work.score,
                            large: true,
                          ),
                          const SizedBox(width: 7),
                          if (work.scoreSource != null)
                            Expanded(
                              child: Text(
                                work.votes == null
                                    ? work.scoreSource!
                                    : '${work.scoreSource!} · '
                                        '${metaCount(work.votes)} ${l10n.metaMembersShort}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontSize: 9.5,
                                  height: 1.3,
                                  fontWeight: FontWeight.w400,
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
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (metaFormatLabel(work.format).isNotEmpty)
                  _InfoPill(
                    icon: Icons.movie_outlined,
                    text: metaFormatLabel(work.format),
                  ),
                if (work.episodes != null)
                  _InfoPill(
                    icon: Icons.playlist_play_rounded,
                    text: '${work.episodes} ${l10n.metaEpShort}',
                  ),
                if (work.chapters != null)
                  _InfoPill(
                    icon: Icons.menu_book_rounded,
                    text: '${work.chapters} ${l10n.metaChShort}',
                  ),
                if (work.status != null)
                  _InfoPill(
                    icon: Icons.circle_outlined,
                    text: metaStatusLabel(l10n, work.status),
                  ),
                if (work.year != null)
                  _InfoPill(
                    icon: Icons.calendar_today_rounded,
                    text: metaSeasonLabel(work.season, work.year, arabic),
                  ),
                if (work.duration != null)
                  _InfoPill(
                    icon: Icons.schedule_rounded,
                    text: work.duration!,
                  ),
                if (work.country != null)
                  _InfoPill(
                    icon: Icons.public_rounded,
                    text: work.country!,
                  ),
              ],
            ),
          ),
        ),
        if (work.nextEpisode != null && work.nextEpisodeAt != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: _NextEpisodeCard(work: work, l10n: l10n),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => context.push(
                      Routes.browseQuery(work.displayTitle),
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(BestRadius.sm),
                      ),
                    ),
                    icon: const Icon(Icons.search_rounded, size: 18),
                    label: Text(
                      l10n.metaFindInSources,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                if (work.siteUrl != null) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => _open(context, l10n, work.siteUrl!),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(BestRadius.sm),
                      ),
                    ),
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: Text(
                      l10n.metaOpenSource,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (work.synopsis != null && work.synopsis!.trim().isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DetailSection(title: l10n.metaStory),
                  const SizedBox(height: 8),
                  _Synopsis(text: work.synopsis!),
                ],
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DetailSection(title: l10n.metaNumbers),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (work.rank != null)
                      _StatTile(
                        label: l10n.metaRank,
                        value: '#${work.rank}',
                        color: BestColors.gold,
                      ),
                    if (work.popularityRank != null)
                      _StatTile(
                        label: l10n.metaPopularity,
                        value: '#${work.popularityRank}',
                      ),
                    if (work.favourites != null)
                      _StatTile(
                        label: l10n.metaFavourites,
                        value: metaCount(work.favourites),
                      ),
                    if (work.votes != null)
                      _StatTile(
                        label: l10n.metaMembers,
                        value: metaCount(work.votes),
                      ),
                    if (work.episodes != null)
                      _StatTile(
                        label: l10n.metaEpisodes,
                        value: '${work.episodes}',
                      ),
                    if (work.chapters != null)
                      _StatTile(
                        label: l10n.metaChapters,
                        value: '${work.chapters}',
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (work.genres.isNotEmpty || work.tags.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DetailSection(title: l10n.metaGenres),
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final genre in work.genres)
                        _TagChip(
                          label: metaGenreLabel(genre, arabic),
                          strong: true,
                        ),
                      for (final tag in work.tags)
                        _TagChip(label: metaGenreLabel(tag.name, arabic)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        if (work.authors.isNotEmpty ||
            work.artists.isNotEmpty ||
            work.studios.isNotEmpty ||
            work.publishers.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DetailSection(title: l10n.metaCredits),
                  const SizedBox(height: 10),
                  if (work.authors.isNotEmpty)
                    _CreditGroup(
                      label: l10n.metaStoryCredit,
                      names: work.authors,
                    ),
                  if (work.artists.isNotEmpty)
                    _CreditGroup(
                      label: l10n.metaArtCredit,
                      names: work.artists,
                    ),
                  if (work.studios.isNotEmpty)
                    _CreditGroup(
                      label: l10n.metaStudio,
                      names: work.studios,
                    ),
                  if (work.publishers.isNotEmpty)
                    _CreditGroup(
                      label: l10n.metaPublisher,
                      names: work.publishers,
                    ),
                ],
              ),
            ),
          ),
        if (links.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DetailSection(title: l10n.metaLinks),
                  const SizedBox(height: 8),
                  for (final link in links.take(10))
                    _LinkRow(
                      link: link,
                      onTap: () => _open(context, l10n, link.url),
                    ),
                ],
              ),
            ),
          ),
        if (work.recommendations.isNotEmpty)
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 26, 20, 10),
                  child: _DetailSection(title: l10n.metaSimilar),
                ),
                SizedBox(
                  height: 228,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: work.recommendations.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 11),
                    itemBuilder: (context, index) {
                      final item = work.recommendations[index];
                      return MetaPosterCard(
                        work: item,
                        width: 118,
                        onTap: () => context.push(
                          Routes.metaWork(item.source, item.id),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
            child: Text(
              l10n.metaAttribution,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 9,
                height: 1.45,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );
  }

  List<MetaLink> _uniqueLinks(List<MetaLink> links) {
    final seen = <String>{};
    final unique = <MetaLink>[];
    for (final link in links) {
      if (link.url.isEmpty) continue;
      if (seen.add(link.url)) unique.add(link);
    }
    return unique;
  }
}

class _DetailBanner extends StatelessWidget {
  const _DetailBanner({required this.work});

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
            metaSourceColor(work.source).withValues(alpha: 0.50),
            BestColors.ink,
          ],
        ),
      ),
      child: Center(
        child: Text(
          work.displayTitle.length > 2
              ? work.displayTitle.substring(0, 2)
              : work.displayTitle,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.12),
            fontSize: 80,
            fontWeight: FontWeight.w900,
            height: 1,
          ),
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

class _CircleAction extends StatelessWidget {
  const _CircleAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: BestColors.ink.withValues(alpha: 0.55),
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(icon, size: 19, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 3,
          height: 15,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(BestRadius.pill),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
        ),
      ],
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
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final text = widget.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final long = text.length > 260;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          maxLines: _expanded ? null : 5,
          overflow: _expanded ? null : TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 12.5,
            height: 1.65,
          ),
        ),
        if (long)
          TextButton(
            onPressed: () => setState(() => _expanded = !_expanded),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 30),
              visualDensity: VisualDensity.compact,
            ),
            child: Text(
              _expanded ? l10n.metaReadLess : l10n.metaReadMore,
              style: const TextStyle(fontSize: 11),
            ),
          ),
      ],
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(BestRadius.pill),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            text,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 9.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 104,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(BestRadius.md),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              color: color ?? theme.colorScheme.onSurface,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 9,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.label, this.strong = false});

  final String label;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: strong
            ? theme.colorScheme.primary.withValues(alpha: 0.12)
            : theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(BestRadius.pill),
        border: Border.all(
          color: strong
              ? theme.colorScheme.primary.withValues(alpha: 0.30)
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: strong
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
          fontSize: 9.5,
          fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }
}

class _CreditGroup extends StatelessWidget {
  const _CreditGroup({required this.label, required this.names});

  final String label;
  final List<String> names;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 66,
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              names.take(8).join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11.5,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.link, required this.onTap});

  final MetaLink link;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final host = Uri.tryParse(link.url)?.host ?? '';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(BestRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(BestRadius.sm),
              ),
              child: Icon(
                link.kind == 'streaming'
                    ? Icons.play_arrow_rounded
                    : Icons.link_rounded,
                size: 17,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    link.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (host.isNotEmpty)
                    Text(
                      host,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 9,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              Icons.open_in_new_rounded,
              size: 14,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _NextEpisodeCard extends StatelessWidget {
  const _NextEpisodeCard({required this.work, required this.l10n});

  final MetaWork work;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final arabic = Directionality.of(context) == TextDirection.rtl;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(BestRadius.md),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.28),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.schedule_rounded,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              '${l10n.metaNextEpisode} ${work.nextEpisode} · '
              '${metaCountdown(work.nextEpisodeAt, arabic)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailLoading extends StatelessWidget {
  const _DetailLoading({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 14),
            Text(
              title,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailError extends StatelessWidget {
  const _DetailError({
    required this.l10n,
    required this.message,
    required this.onRetry,
  });

  final AppLocalizations l10n;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: EmptyState(
            icon: Icons.cloud_off_rounded,
            title: l10n.metaError,
            body: message,
            action: FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(l10n.retry),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _open(
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
