import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SliverConstraints;

import 'tokens.dart';

/// One shared breathing pulse for a group of skeleton shapes.
///
/// A single controller drives a single [FadeTransition], so a rail of six
/// placeholders costs one animation, not six. The pulse is opacity only: no
/// shader, no gradient sweep, nothing that re-rasterises a list. With system
/// animations turned off the shapes simply stay still.
///
/// Wrap the whole placeholder (a rail, a grid, a hero) once and put plain
/// [BestSkeletonBox] children inside it.
class BestPulse extends StatefulWidget {
  const BestPulse({super.key, required this.child}) : sliver = false;

  /// The same pulse around a sliver, for skeleton grids inside a
  /// `CustomScrollView`.
  const BestPulse.sliver({super.key, required Widget sliver})
      : child = sliver,
        sliver = true;

  final Widget child;
  final bool sliver;

  @override
  State<BestPulse> createState() => _BestPulseState();
}

class _BestPulseState extends State<BestPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  late final Animation<double> _opacity = Tween<double>(begin: 0.55, end: 1)
      .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  bool _running = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = BestMotionPolicy.reduced(context);
    if (reduced && _running) {
      _controller
        ..stop()
        ..value = 1;
      _running = false;
    } else if (!reduced && !_running) {
      _controller.repeat(reverse: true);
      _running = true;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.sliver) {
      return SliverFadeTransition(opacity: _opacity, sliver: widget.child);
    }
    return ExcludeSemantics(
      child: FadeTransition(opacity: _opacity, child: widget.child),
    );
  }
}

/// A flat rounded rectangle in the sunken surface colour.
class BestSkeletonBox extends StatelessWidget {
  const BestSkeletonBox({
    super.key,
    this.width,
    this.height,
    this.radius = BestRadius.sm,
  });

  final double? width;
  final double? height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: SizedBox(width: width ?? double.infinity, height: height),
    );
  }
}

/// A poster card placeholder: a 2:3 cover plus two lines of text.
class PosterSkeleton extends StatelessWidget {
  const PosterSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          aspectRatio: 2 / 3,
          child: BestSkeletonBox(radius: BestRadius.md),
        ),
        SizedBox(height: BestSpace.sm),
        BestSkeletonBox(height: 12, radius: 4),
        SizedBox(height: 6),
        BestSkeletonBox(height: 12, radius: 4),
        SizedBox(height: 6),
        FractionallySizedBox(
          widthFactor: 0.55,
          child: BestSkeletonBox(height: 10, radius: 4),
        ),
      ],
    );
  }
}

/// A horizontal rail of poster placeholders that lines up with `WorkCard`
/// rails: same card width rule, same gutter, bleeding to the screen edge.
class PosterRailSkeleton extends StatelessWidget {
  const PosterRailSkeleton({super.key, this.count = 5});

  final int count;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final cardWidth = (screenWidth * 0.36).clamp(132.0, 162.0).toDouble();
    return BestPulse(
      child: SizedBox(
        height: cardWidth * 1.5 + 78,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: BestLayout.gutter),
          itemCount: count,
          separatorBuilder: (BuildContext context, int index) =>
              const SizedBox(width: BestSpace.md),
          itemBuilder: (BuildContext context, int index) =>
              SizedBox(width: cardWidth, child: const PosterSkeleton()),
        ),
      ),
    );
  }
}

/// A grid of poster placeholders sized from the real available width, so the
/// skeleton and the loaded shelf have the same column count.
class SliverPosterGridSkeleton extends StatelessWidget {
  const SliverPosterGridSkeleton({super.key, this.count = 9});

  final int count;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (BuildContext context, SliverConstraints constraints) {
        final width = constraints.crossAxisExtent;
        final columns = (width / 170).floor().clamp(2, 6).toInt();
        final tileWidth =
            (width - BestLayout.gutter * 2 - (columns - 1) * 12) / columns;
        return BestPulse.sliver(
          sliver: SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: BestLayout.gutter),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                mainAxisExtent: tileWidth * 1.5 + 80,
              ),
              delegate: SliverChildBuilderDelegate(
                (BuildContext context, int index) => const PosterSkeleton(),
                childCount: count,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A wide hero placeholder (the "continue" card on Home).
class HeroSkeleton extends StatelessWidget {
  const HeroSkeleton({super.key, this.height = 260});

  final double height;

  @override
  Widget build(BuildContext context) {
    return BestSkeletonBox(height: height, radius: BestRadius.xl);
  }
}

/// A list-row placeholder: 52×76 cover plus three lines.
class RowSkeleton extends StatelessWidget {
  const RowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(BestRadius.md),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: const Padding(
        padding: EdgeInsets.all(BestSpace.md),
        child: Row(
          children: [
            BestSkeletonBox(width: 52, height: 76),
            SizedBox(width: BestSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BestSkeletonBox(height: 13, radius: 4),
                  SizedBox(height: 8),
                  FractionallySizedBox(
                    widthFactor: 0.6,
                    child: BestSkeletonBox(height: 11, radius: 4),
                  ),
                  SizedBox(height: 14),
                  BestSkeletonBox(height: 4, radius: 2),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A stack of [RowSkeleton]s for list screens.
class RowListSkeleton extends StatelessWidget {
  const RowListSkeleton({super.key, this.count = 6});

  final int count;

  @override
  Widget build(BuildContext context) {
    return BestPulse(
      child: Column(
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            const RowSkeleton(),
          ],
        ],
      ),
    );
  }
}
