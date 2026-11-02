import 'package:flutter/material.dart';

import 'brand.dart';
import 'cover.dart';
import 'tokens.dart';

/// The editorial cover story on Home: one work, one sentence, one obvious
/// action. The artwork is framed like a printed plate rather than a rounded
/// storefront tile.
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
        borderRadius: BorderRadius.circular(BestRadius.lg),
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
                        Color(0x1A000000),
                        Color(0x660B0A08),
                        Color(0xF20B0A08),
                      ],
                      stops: [0.18, 0.54, 1],
                    ),
                  ),
                ),
                PositionedDirectional(
                  top: BestSpace.lg,
                  start: BestSpace.lg,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: BestColors.cinnabar,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      child: Text(
                        badge,
                        maxLines: 1,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: BestColors.ink,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ),
                ),
                PositionedDirectional(
                  top: BestSpace.lg,
                  end: BestSpace.lg,
                  child: const BestMark(size: 32),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(BestRadius.lg),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.14),
                        ),
                      ),
                    ),
                  ),
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
                          fontSize: 31,
                          height: 1.12,
                        ),
                      ),
                      if (nativeTitle != null &&
                          nativeTitle!.trim().isNotEmpty) ...[
                        const SizedBox(height: 5),
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
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: BestSpace.lg),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              onPressed: onOpen,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(actionIcon, size: 18),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      actionLabel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: BestSpace.sm),
                          IconButton(
                            onPressed: onOpen,
                            tooltip: actionLabel,
                            style: IconButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.24),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  BestRadius.sm,
                                ),
                              ),
                              fixedSize: const Size(50, 50),
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

/// A wide "pick up where you left off" slip. The cover is the background, the
/// progress rule is the foreground, and the whole card is one target.
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
        width: 302,
        height: 164,
        child: Material(
          color: theme.colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(BestRadius.md),
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
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
                      colors: [Color(0x22000000), Color(0xF20B0A08)],
                      stops: [0.08, 0.92],
                    ),
                  ),
                ),
                PositionedDirectional(
                  top: BestSpace.md,
                  end: BestSpace.md,
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Icon(
                      isVideo
                          ? Icons.play_arrow_rounded
                          : Icons.menu_book_rounded,
                      color: Colors.white,
                      size: 18,
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
                          fontFamily: BestFonts.display,
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
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
                          minHeight: 3,
                          backgroundColor: Colors.white24,
                          color: BestColors.cinnabar,
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
