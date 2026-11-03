import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';
import '../providers.dart';

/// The people behind the extension directory.
///
/// This is a publisher list, not a leaderboard of readers: the index already
/// records who signs each APK, and that is the only contribution the app can
/// verify. The reader's own numbers sit beside it, clearly labelled local.
class ContributorsScreen extends ConsumerWidget {
  const ContributorsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final publishers = ref.watch(publishersProvider);
    final rewards = ref.watch(weeklyRewardsProvider).value;
    final stats = ref.watch(readingStatsProvider).value;
    final market = publishers.value;

    return Scaffold(
      appBar: AppBar(),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(publishersProvider);
          ref.invalidate(weeklyRewardsProvider);
          try {
            await ref.read(publishersProvider.future);
          } catch (_) {
            // Rendered inline.
          }
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            PageMasthead(
              index: "08",
              title: l10n.contributorsTitle,
              subtitle: l10n.contributorsSubtitle,
            ),
            const SizedBox(height: BestSpace.md),
            Text(
              l10n.contributorsBody,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.55,
              ),
            ),
            const SizedBox(height: BestSpace.lg),
            _YourCard(
              works: stats?.works ?? 0,
              units: stats?.completedUnits ?? 0,
              streak: rewards?.streakDays ?? 0,
              badges: rewards?.earned.length ?? 0,
            ),
            const SizedBox(height: BestSpace.xl),
            SectionHeader(
              index: "01",
              title: l10n.contributorsTitle,
              trailing: market == null
                  ? null
                  : Text(
                      l10n.contributorsSources(market.sources),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
            ),
            const SizedBox(height: BestSpace.md),
            if (publishers.isLoading && market == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (market == null || market.items.isEmpty)
              EmptyState(
                icon: Icons.groups_outlined,
                title: l10n.contributorsTitle,
                body: l10n.contributorsEmpty,
                action: FilledButton.icon(
                  onPressed: () => ref.invalidate(publishersProvider),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(l10n.retry),
                ),
              )
            else
              for (var index = 0; index < market.items.length; index++) ...[
                _PublisherTile(
                  rank: index + 1,
                  publisher: market.items[index],
                  onCopy: () {
                    Clipboard.setData(
                      ClipboardData(text: market.items[index].url),
                    );
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        SnackBar(content: Text(market.items[index].url)),
                      );
                  },
                ),
                if (index < market.items.length - 1)
                  const SizedBox(height: BestSpace.sm),
              ],
            if (market != null && market.errors.isNotEmpty) ...[
              const SizedBox(height: BestSpace.md),
              Text(
                market.errors.first,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _YourCard extends StatelessWidget {
  const _YourCard({
    required this.works,
    required this.units,
    required this.streak,
    required this.badges,
  });

  final int works;
  final int units;
  final int streak;
  final int badges;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(BestSpace.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(BestRadius.md),
        border: Border.all(color: BestColors.brass.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.person_outline_rounded,
                size: 20,
                color: BestColors.brass,
              ),
              const SizedBox(width: 8),
              Text(
                l10n.contributorsYourTitle,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontFamily: BestFonts.display,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: BestSpace.md),
          Text(
            l10n.contributorsYourBody(works, units),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: BestSpace.sm),
          Wrap(
            spacing: BestSpace.sm,
            runSpacing: BestSpace.sm,
            children: [
              _Stat(
                icon: Icons.local_fire_department_outlined,
                label: l10n.weeklyStreak(streak),
              ),
              _Stat(
                icon: Icons.workspace_premium_outlined,
                label: '${l10n.weeklyBadgesTitle} · $badges',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(BestRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _PublisherTile extends StatelessWidget {
  const _PublisherTile({
    required this.rank,
    required this.publisher,
    required this.onCopy,
  });

  final int rank;
  final Publisher publisher;
  final VoidCallback onCopy;

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
        onTap: onCopy,
        child: Padding(
          padding: const EdgeInsets.all(BestSpace.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 26,
                child: Text(
                  '$rank',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontFamily: BestFonts.display,
                    fontWeight: FontWeight.w800,
                    color: medal,
                  ),
                ),
              ),
              const SizedBox(width: BestSpace.sm),
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(BestRadius.sm),
                ),
                child: Text(
                  publisher.name.isEmpty
                      ? '?'
                      : publisher.name.characters.first.toUpperCase(),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontFamily: BestFonts.display,
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: BestSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            publisher.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontFamily: BestFonts.display,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (publisher.hasManga)
                          _KindChip(label: l10n.contributorsManga),
                        if (publisher.hasAnime) ...[
                          const SizedBox(width: 4),
                          _KindChip(label: l10n.contributorsAnime),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        l10n.contributorsExtensions(publisher.extensions),
                        l10n.contributorsSources(publisher.sources),
                        if (publisher.languages.isNotEmpty)
                          publisher.languages.take(4).join(', '),
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
              const SizedBox(width: 4),
              Icon(
                Icons.content_copy_rounded,
                size: 15,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KindChip extends StatelessWidget {
  const _KindChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          fontSize: 9,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
