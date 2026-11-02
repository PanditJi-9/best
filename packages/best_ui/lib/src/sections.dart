import 'package:flutter/material.dart';

import 'tokens.dart';

/// A numbered editorial section: index, title, one quiet action, and a
/// hairline that closes the band.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.index,
    this.trailing,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? index;
  final Widget? trailing;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: BestSpace.xl),
      child: Column(
        children: [
          Row(
            children: [
              if (index != null) ...[
                Text(
                  index!.padLeft(2, '0'),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: BestColors.brass,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(fontSize: 21),
                ),
              ),
              if (actionLabel != null && onAction != null)
                TextButton(
                  onPressed: onAction,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: BestSpace.sm,
                    ),
                    textStyle: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.7,
                    ),
                  ),
                  child: Text(actionLabel!.toUpperCase()),
                )
              else if (trailing != null)
                trailing!,
            ],
          ),
          const SizedBox(height: BestSpace.sm),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
        ],
      ),
    );
  }
}

/// The masthead for a whole page. It replaces four hand-built screen headers
/// so the index, the display face and the hairline cannot drift between tabs.
class PageMasthead extends StatelessWidget {
  const PageMasthead({
    super.key,
    required this.index,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String index;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              index.padLeft(2, '0'),
              style: theme.textTheme.labelSmall?.copyWith(
                color: BestColors.brass,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                height: 1,
                color: theme.colorScheme.outlineVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.displaySmall?.copyWith(
                  fontSize: 34,
                  height: 1,
                ),
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 10), trailing!],
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0.2,
            ),
          ),
        ],
        const SizedBox(height: 14),
        Divider(height: 1, color: theme.colorScheme.outlineVariant),
      ],
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    this.eyebrow,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;
  final String? eyebrow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: BestSpace.xl,
        vertical: BestSpace.xxl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(BestRadius.md),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.38),
              ),
            ),
            child: Icon(icon, size: 30, color: theme.colorScheme.primary),
          ),
          if (eyebrow != null) ...[
            const SizedBox(height: BestSpace.lg),
            Text(
              eyebrow!,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                color: BestColors.brass,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: BestSpace.lg),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(fontSize: 24),
          ),
          const SizedBox(height: BestSpace.sm),
          Text(
            body,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.65,
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: BestSpace.xl),
            action!,
          ],
        ],
      ),
    );
  }
}
