import 'package:best_domain/best_domain.dart';
import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../actions.dart';
import '../l10n/generated/app_localizations.dart';
import '../labels.dart';
import '../providers.dart';

/// The ranking, plus the part a ranking site usually fakes: the rewards.
///
/// Every score below comes from MangaDex and every badge is derived from the
/// local activity log. There is no vote button, no coin and no server: a badge
/// is a label on your own shelf.
class TopRatedScreen extends ConsumerWidget {
  const TopRatedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final rankings = ref.watch(rankingsProvider);
    final rewards = ref.watch(weeklyRewardsProvider).value ??
        const WeeklyRewards(
          goal: 300,
          weekPages: 0,
          streakDays: 0,
          completedUnits: 0,
          lifetimePages: 0,
          works: 0,
        );
    final works = rankings.value?.works ?? const <Media>[];

    return Scaffold(
      appBar: AppBar(),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(rankingsProvider);
          ref.invalidate(weeklyRewardsProvider);
          try {
            await ref.read(rankingsProvider.future);
          } catch (_) {
            // Rendered inline.
          }
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            PageMasthead(
              title: l10n.topRatedRanking,
              subtitle: l10n.topRatedSubtitle,
            ),
            const SizedBox(height: BestSpace.lg),
            _ChallengeCard(rewards: rewards),
            const SizedBox(height: BestSpace.lg),
            _BadgesCard(rewards: rewards),
            const SizedBox(height: BestSpace.xl),
            SectionHeader(
              title: l10n.topRatedRanking,
            ),
            const SizedBox(height: BestSpace.sm),
            if (rankings.isLoading && works.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (works.isEmpty)
              EmptyState(
                icon: Icons.star_border_rounded,
                eyebrow: l10n.topRatedTitle.toUpperCase(),
                title: l10n.topRatedEmptyTitle,
                body: l10n.topRatedEmptyBody,
                action: FilledButton.icon(
                  onPressed: () => ref.invalidate(rankingsProvider),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(l10n.retry),
                ),
              )
            else
              for (var index = 0; index < works.length; index++) ...[
                _RankRow(
                  rank: index + 1,
                  media: works[index],
                  onTap: () => openSeries(context, ref, works[index]),
                ),
                if (index < works.length - 1)
                  const SizedBox(height: BestSpace.sm),
              ],
            const SizedBox(height: BestSpace.lg),
            Text(
              l10n.topRatedNote,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChallengeCard extends StatelessWidget {
  const _ChallengeCard({required this.rewards});

  final WeeklyRewards rewards;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(BestSpace.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(BestRadius.md),
        border: Border.all(color: BestColors.brass.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.local_fire_department_outlined,
                size: 20,
                color: BestColors.brass,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.weeklyChallengeTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontFamily: BestFonts.display,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                l10n.weeklyStreak(rewards.streakDays),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: BestSpace.md),
          Text(
            l10n.weeklyGoalLabel(rewards.weekPages, rewards.goal),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontFamily: BestFonts.display,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: BestSpace.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(BestRadius.pill),
            child: LinearProgressIndicator(
              value: rewards.progress,
              minHeight: 8,
              color: BestColors.brass,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: BestSpace.sm),
          Text(
            l10n.weeklyBadgesEarned(
              rewards.earned.length,
              RewardBadge.values.length,
            ),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _BadgesCard extends StatelessWidget {
  const _BadgesCard({required this.rewards});

  final WeeklyRewards rewards;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final earned = rewards.earned;
    return Container(
      padding: const EdgeInsets.all(BestSpace.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(BestRadius.md),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.weeklyBadgesTitle,
            style: theme.textTheme.titleSmall?.copyWith(
              fontFamily: BestFonts.display,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: BestSpace.md),
          Wrap(
            spacing: BestSpace.sm,
            runSpacing: BestSpace.sm,
            children: [
              for (final badge in RewardBadge.values)
                _BadgeChip(
                  badge: badge,
                  earned: earned.contains(badge),
                ),
            ],
          ),
          const SizedBox(height: BestSpace.md),
          Text(
            l10n.rewardsLocalNote,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _BadgeChip extends StatelessWidget {
  const _BadgeChip({required this.badge, required this.earned});

  final RewardBadge badge;
  final bool earned;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final color =
        earned ? BestColors.brass : theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: earned
            ? BestColors.brass.withValues(alpha: 0.12)
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(BestRadius.sm),
        border: Border.all(
          color: earned
              ? BestColors.brass.withValues(alpha: 0.5)
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_badgeIcon(badge), size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            _badgeLabel(l10n, badge),
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: earned ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          if (!earned) ...[
            const SizedBox(width: 5),
            Icon(
              Icons.lock_outline_rounded,
              size: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ],
      ),
    );
  }
}

IconData _badgeIcon(RewardBadge badge) => switch (badge) {
      RewardBadge.firstUnit => Icons.check_circle_outline_rounded,
      RewardBadge.streak3 => Icons.local_fire_department_outlined,
      RewardBadge.streak7 => Icons.whatshot_outlined,
      RewardBadge.pages100 => Icons.auto_stories_outlined,
      RewardBadge.pages300 => Icons.menu_book_outlined,
      RewardBadge.pages1000 => Icons.workspace_premium_outlined,
    };

String _badgeLabel(AppLocalizations l10n, RewardBadge badge) => switch (badge) {
      RewardBadge.firstUnit => l10n.badgeFirstUnit,
      RewardBadge.streak3 => l10n.badgeStreak3,
      RewardBadge.streak7 => l10n.badgeStreak7,
      RewardBadge.pages100 => l10n.badgePages100,
      RewardBadge.pages300 => l10n.badgePages300,
      RewardBadge.pages1000 => l10n.badgePages1000,
    };

class _RankRow extends StatelessWidget {
  const _RankRow({
    required this.rank,
    required this.media,
    required this.onTap,
  });

  final int rank;
  final Media media;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final medal = switch (rank) {
      1 => BestColors.rankGold,
      2 => BestColors.rankSilver,
      3 => BestColors.rankBronze,
      _ => theme.colorScheme.onSurfaceVariant,
    };
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
                width: 34,
                child: Text(
                  '$rank',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontFamily: BestFonts.display,
                    fontWeight: FontWeight.w800,
                    color: medal,
                  ),
                ),
              ),
              const SizedBox(width: BestSpace.sm),
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
                        kindLabel(l10n, media.kind),
                        if (media.year != null) '${media.year}',
                        if (media.genres.isNotEmpty)
                          media.genres.take(2).join(' · '),
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
              const SizedBox(width: BestSpace.sm),
              if (media.rating != null) RatingBadge(score: media.rating!),
            ],
          ),
        ),
      ),
    );
  }
}
