import 'package:flutter/material.dart';

import 'tokens.dart';

/// A section heading: an accent tick, the title, and one quiet action.
///
/// The old build closed every band with a hairline; with six sections on Home
/// that read as a form, not as a shelf. The accent tick and the whitespace now
/// do the separating, and the optional [index] keeps the numbered editorial
/// voice for screens that want it.
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
    final hasAction = actionLabel != null && onAction != null;
    return Padding(
      padding: const EdgeInsets.only(
        top: BestSectionSpec.spaceBefore,
        bottom: BestSectionSpec.spaceAfter - BestSpace.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const _AccentTick(),
          const SizedBox(width: BestSpace.sm + 2),
          if (index != null) ...[
            Text(
              index!.padLeft(2, '0'),
              style: theme.textTheme.labelSmall?.copyWith(
                color: BestColors.brass,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(width: BestSpace.sm),
          ],
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: BestType.sectionTitle(context).copyWith(fontSize: 19),
              ),
            ),
          ),
          if (hasAction)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsetsDirectional.only(
                  start: BestSpace.md,
                  end: BestSpace.xs,
                ),
                minimumSize: const Size(0, 40),
                textStyle: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      actionLabel!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(Icons.chevron_right_rounded, size: 18),
                ],
              ),
            )
          else if (trailing != null)
            trailing!,
        ],
      ),
    );
  }
}

class _AccentTick extends StatelessWidget {
  const _AccentTick();

  @override
  Widget build(BuildContext context) {
    return const ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: BestColors.aurora,
          ),
          borderRadius: BorderRadius.all(Radius.circular(BestRadius.pill)),
        ),
        child: SizedBox(width: 4, height: 20),
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
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontSize: 32,
                    height: 1.12,
                    letterSpacing: BestType.tracking(context, -0.6),
                  ),
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
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
        ],
        const SizedBox(height: 14),
        Divider(height: 1, color: theme.colorScheme.outlineVariant),
      ],
    );
  }
}

/// An empty, error or "nothing yet" state.
///
/// A soft glow sits behind the icon plate, the whole block eases in once, and
/// the copy column is capped so it stays readable on a tablet. Nothing here
/// loops: an empty screen should be calm.
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
    final primary = theme.colorScheme.primary;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: BestSpace.xl,
            vertical: BestSpace.xxl,
          ),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: 1),
            duration: BestMotionPolicy.of(context, BestMotion.slow),
            curve: BestMotion.emphasized,
            builder: (BuildContext context, double t, Widget? child) {
              return Opacity(
                opacity: t,
                child: Transform.translate(
                  offset: Offset(0, (1 - t) * 10),
                  child: child,
                ),
              );
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        primary.withValues(alpha: 0.20),
                        primary.withValues(alpha: 0),
                      ],
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(BestSpace.lg),
                    child: Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(BestRadius.lg),
                        border: Border.all(
                          color: primary.withValues(alpha: 0.38),
                        ),
                      ),
                      child: Icon(icon, size: 30, color: primary),
                    ),
                  ),
                ),
                if (eyebrow != null) ...[
                  const SizedBox(height: BestSpace.md),
                  Text(
                    eyebrow!,
                    textAlign: TextAlign.center,
                    style: BestType.eyebrow(context).copyWith(
                      color: BestColors.brass,
                    ),
                  ),
                ],
                const SizedBox(height: BestSpace.md),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(fontSize: 22),
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
          ),
        ),
      ),
    );
  }
}
