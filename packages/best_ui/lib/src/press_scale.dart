import 'package:flutter/material.dart';

import 'tokens.dart';

/// A tappable surface that sinks very slightly while it is pressed.
///
/// The scale is driven by [InkWell.onHighlightChanged], not by raw pointer
/// events, so it is scroll-aware: when a finger lands on a card and then drags
/// a rail, the gesture arena rejects the tap and the card never shrinks. The
/// ripple stays; the scale only adds weight to the press.
///
/// It animates a single `Transform`, takes no shader and no layer, and does
/// nothing at all when system animations are off.
class BestTapScale extends StatefulWidget {
  const BestTapScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.borderRadius,
    this.scale = 0.97,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final BorderRadius? borderRadius;

  /// The scale at the bottom of the press. 1 disables the effect.
  final double scale;

  @override
  State<BestTapScale> createState() => _BestTapScaleState();
}

class _BestTapScaleState extends State<BestTapScale> {
  bool _pressed = false;

  void _onHighlight(bool value) {
    if (_pressed == value || !mounted) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final active = _pressed &&
        widget.onTap != null &&
        !BestMotionPolicy.reduced(context);
    return InkWell(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      borderRadius: widget.borderRadius,
      onHighlightChanged: _onHighlight,
      child: AnimatedScale(
        scale: active ? widget.scale : 1,
        duration: BestMotion.fast,
        curve: BestMotion.curve,
        child: widget.child,
      ),
    );
  }
}

/// A one-shot entrance: the child fades in while it rises a few pixels.
///
/// It plays once when first built and never again, so scrolling a list back
/// and forth does not replay it. [delay] staggers siblings; keep it under
/// ~300 ms in total so nothing ever makes the reader wait for content. The
/// delay is part of the controller's own timeline (an `Interval`), not a
/// `Timer`, so nothing is left pending when the widget is disposed.
class BestReveal extends StatefulWidget {
  const BestReveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = 14,
  });

  final Widget child;
  final Duration delay;

  /// How far, in logical pixels, the child travels upward while appearing.
  final double offset;

  @override
  State<BestReveal> createState() => _BestRevealState();
}

class _BestRevealState extends State<BestReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _curve;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    final total = widget.delay + BestMotion.slow;
    _controller = AnimationController(vsync: this, duration: total);
    _curve = CurvedAnimation(
      parent: _controller,
      curve: Interval(
        widget.delay.inMilliseconds / total.inMilliseconds,
        1,
        curve: BestMotion.emphasized,
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (BestMotionPolicy.reduced(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      child: widget.child,
      builder: (BuildContext context, Widget? child) {
        // Same widget structure at every frame: swapping it out at the end
        // would remount the child and reset any scroll position inside it.
        final t = _curve.value;
        return Opacity(
          opacity: t.clamp(0.0, 1.0).toDouble(),
          child: Transform.translate(
            offset: Offset(0, (1 - t) * widget.offset),
            child: child,
          ),
        );
      },
    );
  }
}
