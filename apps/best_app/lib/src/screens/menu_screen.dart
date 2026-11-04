import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../actions.dart';
import '../l10n/generated/app_localizations.dart';
import '../navigation.dart';
import '../updates.dart';

/// Frequent actions first; exploration tools tucked into one expandable group.
class MenuScreen extends ConsumerWidget {
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final build = ref.watch(appBuildProvider).value;
    return SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          children: [
            Text(l10n.menuTitle, style: BestType.pageTitle(context)),
            const SizedBox(height: 8),
            Text(
                build == null
                    ? l10n.menuLocalProfile
                    : '${l10n.menuVersion} ${build.version}',
                style: BestType.body(context)),
            _Group(title: l10n.menuSourcesGroup, children: [
              _Tile(
                  icon: Icons.collections_bookmark_outlined,
                  title: l10n.mangaSourcesTitle,
                  body: l10n.menuSourcesBody,
                  onTap: () => context.push(Routes.manga)),
              _Tile(
                  icon: Icons.extension_outlined,
                  title: l10n.directoryTitle,
                  body: l10n.menuDirectoryBody,
                  onTap: () => context.push(Routes.sources)),
              _Tile(
                  icon: Icons.menu_book_outlined,
                  title: l10n.openGuide,
                  body: l10n.menuGuideBody,
                  onTap: () => openGuide(context, ref)),
            ]),
            _Group(title: l10n.menuDeviceGroup, children: [
              _Tile(
                  icon: Icons.settings_outlined,
                  title: l10n.navSettings,
                  body: l10n.menuSettingsBody,
                  onTap: () => context.push(Routes.settings)),
              _Tile(
                  icon: Icons.history_rounded,
                  title: l10n.navHistory,
                  body: l10n.menuHistoryBody,
                  onTap: () => context.push(Routes.history)),
              _Tile(
                  icon: Icons.insights_outlined,
                  title: l10n.statsTitle,
                  body: l10n.menuStatsBody,
                  onTap: () => context.push(Routes.stats)),
              _Tile(
                  icon: Icons.inventory_2_outlined,
                  title: l10n.backupTitle,
                  body: l10n.menuBackupBody,
                  onTap: () => context.push(Routes.backup)),
              _Tile(
                  icon: Icons.cloud_sync_outlined,
                  title: l10n.syncTitle,
                  body: l10n.menuSyncBody,
                  onTap: () => context.push(Routes.sync)),
            ]),
            const SizedBox(height: 18),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(l10n.discoverTitle,
                  style: BestType.sectionTitle(context)),
              children: [
                _Tile(
                    icon: Icons.travel_explore_rounded,
                    title: l10n.metaTitle,
                    body: l10n.menuDatabaseBody,
                    onTap: () => context.go(Routes.database)),
                _Tile(
                    icon: Icons.explore_outlined,
                    title: l10n.discoverTitle,
                    body: l10n.discoverSubtitle,
                    onTap: () => context.push(Routes.discover)),
                _Tile(
                    icon: Icons.newspaper_outlined,
                    title: l10n.newsTitle,
                    body: l10n.menuNewsBody,
                    onTap: () => context.push(Routes.news)),
                _Tile(
                    icon: Icons.workspace_premium_outlined,
                    title: l10n.topRatedTitle,
                    body: l10n.menuTopBody,
                    onTap: () => context.push(Routes.topRated)),
                _Tile(
                    icon: Icons.groups_outlined,
                    title: l10n.contributorsTitle,
                    body: l10n.menuContributorsBody,
                    onTap: () => context.push(Routes.contributors)),
              ],
            ),
            _Tile(
                icon: Icons.info_outline_rounded,
                title: l10n.aboutTitle,
                body: l10n.menuAboutBody,
                onTap: () => context.push(Routes.about)),
            const SizedBox(height: 24),
            Text(l10n.menuLocalNote, style: BestType.body(context)),
          ],
        ));
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: BestType.sectionTitle(context)),
          const SizedBox(height: 10),
          Material(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(BestRadius.lg),
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                for (var i = 0; i < children.length; i++) ...[
                  children[i],
                  if (i < children.length - 1)
                    const Divider(height: 1, indent: 16, endIndent: 16),
                ]
              ])),
        ]),
      );
}

class _Tile extends StatelessWidget {
  const _Tile(
      {required this.icon,
      required this.title,
      required this.body,
      required this.onTap});
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        leading:
            Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
        title: Text(title, style: BestType.cardTitle(context)),
        subtitle: Text(body,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: BestType.body(context)),
        trailing: const Icon(Icons.chevron_right_rounded, size: 20),
        onTap: onTap,
      );
}
