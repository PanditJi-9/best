import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import 'meta_labels.dart';
import 'meta_models.dart';

/// A compact, colour-coded attribution badge. The colour belongs to the
/// provider, so a screen with four catalogues still reads at a glance.
class MetaSourceChip extends StatelessWidget {
  const MetaSourceChip({
    super.key,
    required this.source,
    this.compact = false,
  });

  final MetaSource source;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = metaSourceColor(source);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 5 : 7,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(BestRadius.sm),
        border: Border.all(color: color.withValues(alpha: 0.38)),
      ),
      child: Text(
        source.shortLabel,
        maxLines: 1,
        style: TextStyle(
          color: color,
          fontSize: compact ? 8.5 : 9.5,
          fontWeight: FontWeight.w800,
          height: 1.1,
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}

class MetaScore extends StatelessWidget {
  const MetaScore({
    super.key,
    required this.score,
    this.source,
    this.large = false,
  });

  final double? score;
  final String? source;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (score == null) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.star_rounded,
          size: large ? 20 : 13,
          color: BestColors.gold,
        ),
        const SizedBox(width: 3),
        Text(
          metaScoreText(score),
          style: theme.textTheme.titleSmall?.copyWith(
            color: BestColors.gold,
            fontWeight: FontWeight.w900,
            fontSize: large ? 24 : 12.5,
            height: 1,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (large) ...[
          const SizedBox(width: 2),
          Text(
            '/10',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
        ],
        if (source != null && !large) ...[
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              source!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 9,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// A catalogue poster with an optional rank or status badge. This is the
/// database's unit: cover first, two lines of title, one line of facts.
class MetaPosterCard extends StatelessWidget {
  const MetaPosterCard({
    super.key,
    required this.work,
    required this.onTap,
    this.width = 126,
    this.badge,
    this.subtitle,
    this.showSource = false,
  });

  final MetaWork work;
  final VoidCallback onTap;
  final double width;
  final String? badge;
  final String? subtitle;
  final bool showSource;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = badge ?? (work.rank == null ? null : '#${work.rank}');
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(BestRadius.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 2 / 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(BestRadius.md),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                    child: BestCover(
                      title: work.displayTitle,
                      url: work.coverUrl,
                      radius: BestRadius.md,
                    ),
                  ),
                  if (label != null)
                    PositionedDirectional(
                      top: 6,
                      start: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: BestColors.ink.withValues(alpha: 0.82),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.16),
                          ),
                        ),
                        child: Text(
                          label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ),
                  if (showSource)
                    PositionedDirectional(
                      top: 6,
                      end: 6,
                      child: MetaSourceChip(source: work.source, compact: true),
                    ),
                  if (work.score != null)
                    PositionedDirectional(
                      start: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: BestColors.ink.withValues(alpha: 0.84),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: MetaScore(score: work.score),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              work.displayTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                height: 1.22,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle ?? _subtitle(context, work),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 9.5,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _subtitle(BuildContext context, MetaWork work) {
    final l10n = AppLocalizations.of(context);
    final parts = <String>[];
    final format = metaFormatLabel(work.format);
    if (format.isNotEmpty) parts.add(format);
    if (work.episodes != null) {
      parts.add('${work.episodes} ${l10n.metaEpShort}');
    }
    if (work.chapters != null) {
      parts.add('${work.chapters} ${l10n.metaChShort}');
    }
    if (work.year != null) parts.add('${work.year}');
    if (parts.isEmpty && work.genres.isNotEmpty) parts.add(work.genres.first);
    return parts.join(' · ');
  }
}

/// The header used by every database rail: a provider-coloured rule, a title,
/// a source line, and an optional action.
class MetaSectionHeader extends StatelessWidget {
  const MetaSectionHeader({
    super.key,
    required this.source,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final MetaSource source;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = metaSourceColor(source);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 26, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 3,
            height: 34,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(BestRadius.pill),
            ),
          ),
          const SizedBox(width: 10),
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
                      fontSize: 10.5,
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

/// One row in a ranked list. The rank is the loud element; the score is the
/// only number that competes with it.
class MetaRankRow extends StatelessWidget {
  const MetaRankRow({
    super.key,
    required this.work,
    required this.onTap,
    this.rank,
  });

  final MetaWork work;
  final VoidCallback onTap;
  final int? rank;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final position = rank ?? work.rank;
    final rankColor = switch (position) {
      1 => BestColors.rankGold,
      2 => BestColors.rankSilver,
      3 => BestColors.rankBronze,
      _ => theme.colorScheme.onSurfaceVariant,
    };
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(BestRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
        child: Row(
          children: [
            SizedBox(
              width: 30,
              child: Text(
                position == null ? '' : '$position',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: rankColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                  height: 1,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 38,
              height: 56,
              child: BestCover(
                title: work.displayTitle,
                url: work.coverUrl,
                radius: BestRadius.sm,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    work.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _meta(context, work),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            MetaScore(score: work.score),
          ],
        ),
      ),
    );
  }

  String _meta(BuildContext context, MetaWork work) {
    final l10n = AppLocalizations.of(context);
    final parts = <String>[];
    final format = metaFormatLabel(work.format);
    if (format.isNotEmpty) parts.add(format);
    if (work.episodes != null) {
      parts.add('${work.episodes} ${l10n.metaEpShort}');
    }
    if (work.votes != null) {
      parts.add('${metaCount(work.votes)} ${l10n.metaMembersShort}');
    }
    return parts.join(' · ');
  }
}

/// A real article thumbnail, or a typographic fallback when the publisher
/// does not expose one. Never another article's image.
class MetaNewsCard extends StatelessWidget {
  const MetaNewsCard({
    super.key,
    required this.news,
    required this.onTap,
  });

  final MetaNews news;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(BestRadius.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(BestRadius.lg),
        child: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(BestRadius.lg),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(BestRadius.sm),
                child: SizedBox(
                  width: 92,
                  height: 70,
                  child: news.imageUrl == null
                      ? _NewsFallback(title: news.title)
                      : Image.network(
                          news.imageUrl!,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.medium,
                          errorBuilder: (context, error, stack) =>
                              _NewsFallback(title: news.title),
                        ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      news.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        MetaSourceChip(
                          source: MetaSource.animeCorner,
                          compact: true,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            metaDateLabel(
                              news.publishedAt,
                              Directionality.of(context) == TextDirection.rtl,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 9,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.open_in_new_rounded,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewsFallback extends StatelessWidget {
  const _NewsFallback({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A1A12), Color(0xFF120B08)],
        ),
      ),
      child: Center(
        child: Text(
          'AC',
          style: TextStyle(
            color: const Color(0xFFF97316).withValues(alpha: 0.9),
            fontSize: 19,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }
}

/// A source-level failure notice. It names the provider and never replaces
/// the sections that did load.
class MetaSourceNotice extends StatelessWidget {
  const MetaSourceNotice({
    super.key,
    required this.failures,
    required this.onRetry,
    required this.retryLabel,
  });

  final Map<MetaSource, String> failures;
  final VoidCallback onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    if (failures.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final names = failures.keys.map((source) => source.label).join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(BestRadius.md),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                names,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 30),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Text(retryLabel),
            ),
          ],
        ),
      ),
    );
  }
}

/// The provider-coloured dot used in the source strip under the masthead.
class MetaSourceDot extends StatelessWidget {
  const MetaSourceDot({super.key, required this.source});

  final MetaSource source;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        color: metaSourceColor(source),
        shape: BoxShape.circle,
      ),
    );
  }
}
