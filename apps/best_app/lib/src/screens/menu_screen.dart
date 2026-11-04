import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/generated/app_localizations.dart';
import '../navigation.dart';
import '../providers.dart';
import '../updates.dart';

/// The controls, grouped by what they act on.
///
/// The card at the top is the only "profile" in the app: it describes what is
/// stored on this phone, not an account. There is no sign-in because there is
/// no server holding a person's shelf.
class MenuScreen extends ConsumerWidget {
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final stats = ref.watch(readingStatsProvider).value;
    final build = ref.watch(appBuildProvider).value;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 120),
        children: [
          Row(
            children: [
              const BestMark(size: 42),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.menuTitle,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontSize: 25,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.6,
                        height: 1.05,
                      ),
                    ),
                    Text(
                      build == null
                          ? l10n.menuLocalProfile
                          : '${l10n.menuVersion} ${build.version}',
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
            ],
          ),
          const SizedBox(height: 18),
          _ProfileCard(
            l10n: l10n,
            works: stats?.works ?? 0,
            units: stats?.units ?? 0,
            minutes: stats?.minutes ?? 0,
          ),
          _MenuGroup(
            title: l10n.menuLibraryGroup,
            tiles: [
              _MenuTile(
                icon: Icons.history_rounded,
                title: l10n.navHistory,
                body: l10n.menuHistoryBody,
                onTap: () => context.push(Routes.history),
              ),
              _MenuTile(
                icon: Icons.download_rounded,
                title: l10n.navDownloads,
                body: l10n.menuDownloadsBody,
                onTap: () => context.go(Routes.downloads),
              ),
              _MenuTile(
                icon: Icons.insights_rounded,
                title: l10n.statsTitle,
                body: l10n.menuStatsBody,
                onTap: () => context.push(Routes.stats),
              ),
              _MenuTile(
                icon: Icons.workspace_premium_rounded,
                title: l10n.topRatedTitle,
                body: l10n.menuTopBody,
                onTap: () => context.push(Routes.topRated),
              ),
            ],
          ),
          _MenuGroup(
            title: l10n.menuSourcesGroup,
            tiles: [
              _MenuTile(
                icon: Icons.travel_explore_rounded,
                title: l10n.metaTitle,
                body: l10n.menuDatabaseBody,
                onTap: () => context.go(Routes.database),
              ),
              _MenuTile(
                icon: Icons.explore_rounded,
                title: l10n.discoverTitle,
                body: l10n.discoverSubtitle,
                onTap: () => context.push(Routes.discover),
              ),
              _MenuTile(
                icon: Icons.newspaper_rounded,
                title: l10n.newsTitle,
                body: l10n.menuNewsBody,
                onTap: () => context.push(Routes.news),
              ),
              _MenuTile(
                icon: Icons.extension_rounded,
                title: l10n.directoryTitle,
                body: l10n.menuDirectoryBody,
                onTap: () => context.push(Routes.sources),
              ),
              _MenuTile(
                icon: Icons.groups_rounded,
                title: l10n.contributorsTitle,
                body: l10n.menuContributorsBody,
                onTap: () => context.push(Routes.contributors),
              ),
            ],
          ),
          _MenuGroup(
            title: l10n.menuToolsGroup,
            tiles: [
              _MenuTile(
                icon: Icons.settings_rounded,
                title: l10n.navSettings,
                body: l10n.menuSettingsBody,
                onTap: () => context.push(Routes.settings),
              ),
              _MenuTile(
                icon: Icons.inventory_2_rounded,
                title: l10n.backupTitle,
                body: l10n.menuBackupBody,
                onTap: () => context.push(Routes.backup),
              ),
              _MenuTile(
                icon: Icons.cloud_sync_rounded,
                title: l10n.syncTitle,
                body: l10n.menuSyncBody,
                onTap: () => context.push(Routes.sync),
              ),
              _MenuTile(
                icon: Icons.info_rounded,
                title: l10n.aboutTitle,
                body: l10n.menuAboutBody,
                onTap: () => context.push(Routes.about),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            l10n.menuLocalNote,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
              fontSize: 9.5,
              height: 1.45,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.l10n,
    required this.works,
    required this.units,
    required this.minutes,
  });

  final AppLocalizations l10n;
  final int works;
  final int units;
  final int minutes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF12213D), Color(0xFF0A1120)],
        ),
        borderRadius: BorderRadius.circular(BestRadius.xl),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: BestColors.blue.withValues(alpha: 0.14),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: BestColors.blue.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(BestRadius.sm),
                  border: Border.all(
                    color: BestColors.blue.withValues(alpha: 0.35),
                  ),
                ),
                child: const Icon(
                  Icons.person_outline_rounded,
                  size: 18,
                  color: BestColors.blueSoft,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.menuLocalProfile,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _ProfileStat(value: '$works', label: l10n.menuWorks),
              _ProfileDivider(),
              _ProfileStat(value: '$units', label: l10n.menuChaptersShort),
              _ProfileDivider(),
              _ProfileStat(value: '$minutes', label: l10n.menuMinutes),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfileStat extends StatelessWidget {
  const _ProfileStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              height: 1,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.52),
              fontSize: 9,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 30,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      color: Colors.white.withValues(alpha: 0.10),
    );
  }
}

class _MenuGroup extends StatelessWidget {
  const _MenuGroup({required this.title, required this.tiles});

  final String title;
  final List<_MenuTile> tiles;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              title.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 9,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(BestRadius.lg),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Column(
              children: [
                for (var index = 0; index < tiles.length; index++) ...[
                  tiles[index],
                  if (index != tiles.length - 1)
                    Divider(
                      height: 1,
                      indent: 56,
                      endIndent: 14,
                      color: theme.colorScheme.outlineVariant,
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(BestRadius.lg),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(13, 11, 10, 11),
        child: Row(
          children: [
            Container(
              width: 33,
              height: 33,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(BestRadius.sm),
              ),
              child: Icon(
                icon,
                size: 17,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    body,
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
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right_rounded,
              size: 17,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
    );
  }
}
