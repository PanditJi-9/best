import 'package:best_domain/best_domain.dart';
import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../l10n/generated/app_localizations.dart';
import '../providers.dart';

/// The numbers a reader actually looks at: how many days in a row, how much
/// this week, and the lifetime totals. Everything is local; there is no upload
/// and no comparison with anyone else.
class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final stats = ref.watch(readingStatsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.statsTitle)),
      body: stats.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => EmptyState(
          icon: Icons.insights_outlined,
          title: l10n.statsEmptyTitle,
          body: '$error',
        ),
        data: (stats) {
          if (stats.pages == 0 && stats.minutes == 0) {
            return EmptyState(
              icon: Icons.insights_outlined,
              title: l10n.statsEmptyTitle,
              body: l10n.statsEmptyBody,
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              _StreakCard(stats: stats),
              const SizedBox(height: 14),
              _WeekCard(stats: stats),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _StatTile(
                      icon: Icons.menu_book_outlined,
                      value: '${stats.pages}',
                      label: l10n.statsPagesLabel,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatTile(
                      icon: Icons.timelapse_outlined,
                      value: '${stats.minutes}',
                      label: l10n.statsMinutesLabel,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _StatTile(
                      icon: Icons.done_all_outlined,
                      value: '${stats.completedUnits}',
                      label: l10n.statsFinishedLabel,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatTile(
                      icon: Icons.collections_bookmark_outlined,
                      value: '${stats.works}',
                      label: l10n.statsWorks,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                l10n.statsEmptyBody,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.stats});

  final ReadingStats stats;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final active = stats.streakDays > 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(BestRadius.lg),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [
            BestColors.jade.withValues(alpha: active ? 0.22 : 0.08),
            theme.colorScheme.surfaceContainerLow,
          ],
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.statsStreakTitle.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.streakDays(stats.streakDays),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.6,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  active ? l10n.statsSubtitle : l10n.streakEmpty,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: BestColors.jade.withValues(alpha: active ? 0.9 : 0.25),
            ),
            child: Icon(
              Icons.local_fire_department_rounded,
              color: active ? BestColors.ink : theme.colorScheme.onSurfaceVariant,
              size: 30,
            ),
          ),
        ],
      ),
    );
  }
}

/// Seven bars, oldest first. Bars are scaled to the busiest day of the week so
/// a reader with three pages a day still sees shape instead of a flat line.
class _WeekCard extends StatelessWidget {
  const _WeekCard({required this.stats});

  final ReadingStats stats;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final format = DateFormat.E(locale);
    final todayKey = ReadingStats.dayKey(DateTime.now());

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(BestRadius.lg),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        color: theme.colorScheme.surfaceContainerLow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.statsWeek,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 104,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final day in stats.week)
                  Expanded(
                    child: _DayBar(
                      day: day,
                      peak: stats.weekPeak,
                      isToday: day.day == todayKey,
                      label: _weekday(format, day.day),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _weekday(DateFormat format, String day) {
    final date = DateTime.tryParse(day);
    return date == null ? '' : format.format(date);
  }
}

class _DayBar extends StatelessWidget {
  const _DayBar({
    required this.day,
    required this.peak,
    required this.isToday,
    required this.label,
  });

  final DailyActivity day;
  final int peak;
  final bool isToday;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final load = day.pages + day.minutes;
    final fraction = (load / peak).clamp(0.0, 1.0);

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: 16,
              height: load == 0 ? 4 : 8 + fraction * 60,
              decoration: BoxDecoration(
                color: load == 0
                    ? theme.colorScheme.outlineVariant
                    : (isToday ? BestColors.jade : BestColors.jade.withValues(alpha: 0.55)),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            fontSize: 10,
            color: isToday
                ? theme.colorScheme.onSurface
                : theme.colorScheme.onSurfaceVariant,
            fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(BestRadius.lg),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        color: theme.colorScheme.surfaceContainerLow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: BestColors.jade),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 2,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
