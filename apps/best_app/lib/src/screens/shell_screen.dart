import 'dart:async';

import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/generated/app_localizations.dart';
import '../providers.dart';

/// The six rooms of the app: the chosen catalogue, the shelf, new chapters,
/// offline downloads, the encyclopedia, and the reading history. Settings is a
/// pushed screen from the home masthead, so the dock stays for content only.
///
/// The 2.0 dock floats inside the page like a printed index tab: a warm raised
/// bar with a hairline edge, one vermilion selected pill, and labels that stay
/// visible in both languages. Switching tabs eases the new page in (a short
/// fade, never a slide: tabs are peers, not steps) and gives a light haptic
/// tick.
class ShellScreen extends ConsumerStatefulWidget {
  const ShellScreen({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends ConsumerState<ShellScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: BestMotion.normal,
    value: 1,
  );
  late final Animation<double> _opacity = Tween<double>(
    begin: 0.4,
    end: 1,
  ).animate(CurvedAnimation(parent: _fade, curve: BestMotion.curve));
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _autoRefresh);
    // A cold launch never fires onResume, so ask once the first frame is ready.
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoRefresh());
  }

  void _autoRefresh() {
    if (!mounted) return;
    unawaited(ref.read(libraryAutoRefreshProvider.notifier).maybeRefresh());
  }

  @override
  void didUpdateWidget(covariant ShellScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.navigationShell.currentIndex !=
            widget.navigationShell.currentIndex &&
        !BestMotionPolicy.reduced(context)) {
      _fade.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    _fade.dispose();
    super.dispose();
  }

  void _select(int index) {
    final shell = widget.navigationShell;
    if (index != shell.currentIndex) {
      HapticFeedback.selectionClick();
      // A snackbar belongs to the action that raised it. Carrying "removed
      // from shelf" into Downloads makes the new tab look like it failed.
      ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    }
    shell.goBranch(index, initialLocation: index == shell.currentIndex);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

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
        icon: Icons.collections_bookmark_outlined,
        selectedIcon: Icons.collections_bookmark_rounded,
      ),
      _Destination(
        label: l10n.navUpdates,
        icon: Icons.new_releases_outlined,
        selectedIcon: Icons.new_releases_rounded,
      ),
      _Destination(
        label: l10n.navDownloads,
        icon: Icons.download_for_offline_outlined,
        selectedIcon: Icons.download_for_offline_rounded,
      ),
      _Destination(
        label: l10n.navDatabase,
        icon: Icons.explore_outlined,
        selectedIcon: Icons.explore_rounded,
      ),
      _Destination(
        label: l10n.navHistory,
        icon: Icons.history_rounded,
        selectedIcon: Icons.history_rounded,
      ),
    ];

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          // The room: ink at the foot, a breath of ember at the crown. The
          // glow is an atmosphere, never a background gradient behind text.
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? const [Color(0xFF120D0D), BestColors.ink, BestColors.inkDeep]
                : const [Color(0xFFFFF8EC), BestColors.paper, BestColors.paper],
            stops: const [0, 0.38, 1],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            PositionedDirectional(
              top: -180,
              start: -120,
              child: IgnorePointer(
                child: Container(
                  width: 420,
                  height: 420,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        BestColors.ember.withValues(
                          alpha: isDark ? 0.16 : 0.09,
                        ),
                        BestColors.ember.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Tabs use InkWell for their cards and rows. Scaffold does not put
            // a Material above its body, so without this the ink lookups fail
            // in debug as soon as a tab with a tappable card is opened.
            LayoutBuilder(
              builder: (context, constraints) {
                final contentWidth =
                    constraints.maxWidth > BestLayout.maxContentWidth
                    ? BestLayout.maxContentWidth
                    : constraints.maxWidth;
                return Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: contentWidth,
                    height: constraints.maxHeight,
                    child: Material(
                      type: MaterialType.transparency,
                      child: FadeTransition(
                        opacity: _opacity,
                        child: widget.navigationShell,
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      bottomNavigationBar: _NavigationDock(
        destinations: destinations,
        currentIndex: widget.navigationShell.currentIndex,
        onSelected: _select,
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
    final isDark = theme.brightness == Brightness.dark;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isDark ? BestColors.inkRaised : BestColors.paperRaised,
          borderRadius: BorderRadius.circular(BestRadius.xl),
          border: Border.all(color: theme.colorScheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.42 : 0.10),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(BestRadius.xl),
          child: SizedBox(
            height: 66,
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

/// One dock destination: an icon on a pill that grows when selected, and a
/// label that always stays visible so English and Arabic both fit.
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
    final scheme = theme.colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    final duration = BestMotionPolicy.of(context, BestMotion.normal);

    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(BestRadius.lg),
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 5),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: duration,
                  curve: BestMotion.curve,
                  width: selected ? 46 : 36,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected
                        ? scheme.primary.withValues(alpha: 0.16)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(BestRadius.pill),
                  ),
                  child: Icon(
                    selected ? destination.selectedIcon : destination.icon,
                    size: 21.5,
                    color: color,
                  ),
                ),
                const SizedBox(height: 3),
                SizedBox(
                  height: 15,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      destination.label,
                      maxLines: 1,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 10.5,
                        height: 1.1,
                        letterSpacing: 0,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w500,
                        color: color,
                      ),
                    ),
                  ),
                ),
                // A hair of vermilion under the active label: the seal again,
                // at the smallest scale the dock can carry.
                AnimatedContainer(
                  duration: duration,
                  margin: const EdgeInsets.only(top: 2),
                  width: selected ? 12 : 0,
                  height: 2,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(1),
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
