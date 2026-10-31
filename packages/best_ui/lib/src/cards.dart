import 'package:flutter/material.dart';

import 'brand.dart';
import 'cover.dart';
import 'tokens.dart';

/// The editorial hero on Home. Unlike a poster card it carries a sentence, a
/// primary action and a quiet secondary action, so a fresh install has one
/// obvious place to start.
class SpotlightCard extends StatelessWidget {
  const SpotlightCard({
    super.key,
    required this.title,
    required this.badge,
    required this.meta,
    required this.actionLabel,
    required this.onOpen,
    this.nativeTitle,
    this.coverUrl,
    this.actionIcon = Icons.auto_stories_outlined,
  });

  final String title;
  final String? nativeTitle;
  final String badge;
  final String meta;
  final String actionLabel;
  final IconData actionIcon;
  final String? coverUrl;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: title,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(BestRadius.xl),
        child: AspectRatio(
          aspectRatio: 4 / 5,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onOpen,
            child: Stack(
              fit: StackFit.expand,
              children: [
                BestCover(title: title, url: coverUrl, radius: 0),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x22000000),
                        Color(0x66000000),
                        Color(0xF207080B),
                      ],
                      stops: [0.2, 0.55, 1],
                    ),
                  ),
                ),
                PositionedDirectional(
                  top: BestSpace.lg,
                  start: BestSpace.lg,
                  child: _GlassPill(label: badge),
                ),
                PositionedDirectional(
                  top: BestSpace.lg,
                  end: BestSpace.lg,
                  child: const BestMark(size: 34),
                ),
                PositionedDirectional(
                  start: BestSpace.xl,
                  end: BestSpace.xl,
                  bottom: BestSpace.xl,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 28,
                          letterSpacing: -0.8,
                          height: 1.02,
                        ),
                      ),
                      if (nativeTitle != null &&
                          nativeTitle!.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          nativeTitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white60,
                          ),
                        ),
                      ],
                      const SizedBox(height: BestSpace.sm),
                      Text(
                        meta,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: Colors.white70,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: BestSpace.lg),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: onOpen,
                              icon: Icon(actionIcon, size: 18),
                              label: Text(actionLabel),
                            ),
                          ),
                          const SizedBox(width: BestSpace.sm),
                          IconButton.filledTonal(
                            onPressed: onOpen,
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.14,
                              ),
                              foregroundColor: Colors.white,
                              fixedSize: const Size(52, 52),
                            ),
                            icon: const Icon(Icons.arrow_forward_rounded),
                          ),
                        ],
                      ),
                    ],
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

/// A wide "pick up where you left off" card. The cover is the background, the
/// progress bar is the foreground, and the whole card is one target.
class ContinueCard extends StatelessWidget {
  const ContinueCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.progress,
    required this.progressLabel,
    required this.onOpen,
    this.coverUrl,
    this.isVideo = false,
  });

  final String title;
  final String subtitle;
  final double progress;
  final String progressLabel;
  final String? coverUrl;
  final bool isVideo;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: title,
      child: SizedBox(
        width: 300,
        height: 172,
        child: Material(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(BestRadius.lg),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onOpen,
            child: Stack(
              fit: StackFit.expand,
              children: [
                BestCover(title: title, url: coverUrl, radius: 0),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x33000000), Color(0xF20A0B10)],
                      stops: [0.1, 0.92],
                    ),
                  ),
                ),
                PositionedDirectional(
                  top: BestSpace.md,
                  end: BestSpace.md,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(9),
                      child: Icon(
                        isVideo
                            ? Icons.play_arrow_rounded
                            : Icons.menu_book_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
                PositionedDirectional(
                  start: BestSpace.lg,
                  end: BestSpace.lg,
                  bottom: BestSpace.lg,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: BestSpace.md),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(BestRadius.pill),
                        child: LinearProgressIndicator(
                          value: progress.clamp(0.0, 1.0),
                          minHeight: 4,
                          backgroundColor: Colors.white24,
                          color: BestColors.jade,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        progressLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.white60,
                        ),
                      ),
                    ],
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

/// A small translucent label for artwork. It never takes the eye away from the
/// cover, which is the actual content.
class _GlassPill extends StatelessWidget {
  const _GlassPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(BestRadius.pill),
        border: Border.all(color: Colors.white24),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }
}
