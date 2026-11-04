import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/generated/app_localizations.dart';
import '../providers.dart';

/// The five rooms of the app: what is new, what is out there, what you own,
/// what is offline, and the controls.
///
/// A quiet, full-width dock keeps all five destinations legible in either language.
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
        label: l10n.navDatabase,
        icon: Icons.travel_explore_outlined,
        selectedIcon: Icons.travel_explore_rounded,
      ),
      _Destination(
        label: l10n.navLibrary,
        icon: Icons.collections_bookmark_outlined,
        selectedIcon: Icons.collections_bookmark_rounded,
      ),
      _Destination(
        label: l10n.navDownloads,
        icon: Icons.download_outlined,
        selectedIcon: Icons.download_rounded,
      ),
      _Destination(
        label: l10n.navMenu,
        icon: Icons.menu_rounded,
        selectedIcon: Icons.menu_rounded,
      ),
    ];

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -1.25),
            radius: 1.1,
            colors: [
              theme.colorScheme.primary.withValues(
                alpha: theme.brightness == Brightness.dark ? 0.10 : 0.05,
              ),
              theme.colorScheme.surface,
            ],
            stops: const [0, 0.7],
          ),
        ),
        // Tabs use InkWell for their cards and rows. Scaffold does not put a
        // Material above its body, so without this the ink lookups fail in
        // debug as soon as a tab with a tappable card is opened.
        child: LayoutBuilder(
          builder: (context, constraints) {
            final contentWidth = constraints.maxWidth > 1120
                ? 1120.0
                : constraints.maxWidth;
            return Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: contentWidth,
                height: constraints.maxHeight,
                child: Material(
                  type: MaterialType.transparency,
                  child: navigationShell,
                ),
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: _NavigationDock(
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

class _NavigationDock extends StatelessWidget {
  const _NavigationDock({
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
      color: theme.colorScheme.surfaceContainerLow,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border:
              Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
        ),
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
        borderRadius: BorderRadius.circular(20),
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: 3,
                  child: AnimatedContainer(
                    duration: BestMotion.normal,
                    curve: BestMotion.curve,
                    width: selected ? 30 : 0,
                    height: 2,
                    decoration: BoxDecoration(
                      color: selected
                          ? theme.colorScheme.primary
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(BestRadius.pill),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Icon(
                  selected ? destination.selectedIcon : destination.icon,
                  size: 22,
                  color: color,
                ),
                const SizedBox(height: 3),
                SizedBox(
                  height: 16,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      destination.label,
                      maxLines: 1,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 11,
                        height: 1.2,
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
      ),
    );
  }
}
