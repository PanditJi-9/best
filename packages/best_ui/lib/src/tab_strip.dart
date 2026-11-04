import 'package:flutter/material.dart';

import 'tokens.dart';

/// A horizontally scrolling strip of pill-shaped tabs.
///
/// The selected tab is a filled pill; unselected tabs are transparent. Ported
/// from the Yokai design language. [onSelected] receives the index.
class BestTabStrip extends StatelessWidget {
  const BestTabStrip({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
    this.padding,
  });

  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding ?? const EdgeInsets.symmetric(horizontal: BestSpace.lg),
        itemCount: tabs.length,
        separatorBuilder: (BuildContext context, int index) =>
            const SizedBox(width: BestSpace.sm),
        itemBuilder: (BuildContext context, int index) {
          final selected = index == selectedIndex;
          return _BestTab(
            label: tabs[index],
            selected: selected,
            onTap: () => onSelected(index),
          );
        },
      ),
    );
  }
}

class _BestTab extends StatelessWidget {
  const _BestTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = selected
        ? scheme.primary.withValues(alpha: 0.16)
        : Colors.transparent;
    final fg = selected ? scheme.primary : scheme.onSurfaceVariant;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(BestRadius.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(BestRadius.pill),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minWidth: BestLayout.minTouch),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(
            horizontal: BestSpace.md,
            vertical: BestSpace.sm,
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: fg,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              fontFamily: BestFontFamily.heading,
            ),
          ),
        ),
      ),
    );
  }
}
