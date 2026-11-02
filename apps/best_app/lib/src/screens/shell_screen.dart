import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/generated/app_localizations.dart';
import '../providers.dart';

/// The five destinations are the whole information architecture: where to
/// start, what you own, what exists, what is offline, and how the app behaves.
/// Anything deeper is a pushed route, never a sixth tab.
class ShellScreen extends ConsumerWidget {
  const ShellScreen({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    // Keeps the offline queue alive while any tab is open: leaving Downloads
    // must not pause a chapter that is already downloading.
    ref.watch(downloadManagerProvider);

    final destinations = <_Destination>[
      _Destination(
        label: l10n.navHome,
        icon: Icons.home_outlined,
        selectedIcon: Icons.home_rounded,
      ),
      _Destination(
        label: l10n.navLibrary,
        icon: Icons.auto_stories_outlined,
        selectedIcon: Icons.auto_stories,
      ),
      _Destination(
        label: l10n.navBrowse,
        icon: Icons.explore_outlined,
        selectedIcon: Icons.explore,
      ),
      _Destination(
        label: l10n.navDownloads,
        icon: Icons.download_outlined,
        selectedIcon: Icons.download,
      ),
      _Destination(
        label: l10n.navSettings,
        icon: Icons.tune_outlined,
        selectedIcon: Icons.tune_rounded,
      ),
    ];

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -1.15),
            radius: 1.25,
            colors: [
              theme.colorScheme.primary.withValues(
                alpha: theme.brightness == Brightness.dark ? 0.10 : 0.06,
              ),
              theme.colorScheme.surface,
            ],
            stops: const [0, 0.62],
          ),
        ),
        child: navigationShell,
      ),
      bottomNavigationBar: _IndexBar(
        destinations: destinations,
        currentIndex: navigationShell.currentIndex,
        onSelected: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
      ),
    );
  }
}

class _Destination {
  const _Destination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// A printed index bar: one hairline, five columns, and an ember rule over the
/// current tab. It replaces Material's floating pill so navigation feels like
/// part of the page rather than a widget laid on top of it.
class _IndexBar extends StatelessWidget {
  const _IndexBar({
    required this.destinations,
    required this.currentIndex,
    required this.onSelected,
  });

  final List<_Destination> destinations;
  final int currentIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                for (var index = 0; index < destinations.length; index++)
                  Expanded(
                    child: _NavItem(
                      destination: destinations[index],
                      selected: index == currentIndex,
                      onTap: () => onSelected(index),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _Destination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      child: InkWell(
        onTap: onTap,
        child: ExcludeSemantics(
          child: Stack(
            children: [
              if (selected)
                PositionedDirectional(
                  top: 0,
                  start: 14,
                  end: 14,
                  child: Container(
                    height: 2,
                    color: theme.colorScheme.primary,
                  ),
                ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 9, 4, 7),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        selected ? destination.selectedIcon : destination.icon,
                        size: 21,
                        color: color,
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: 12,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            destination.label,
                            maxLines: 1,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: 9.5,
                              height: 1,
                              letterSpacing: 0,
                              fontWeight:
                                  selected ? FontWeight.w700 : FontWeight.w500,
                              color: color,
                            ),
                          ),
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
