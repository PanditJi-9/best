import 'dart:async';
import 'dart:math' as math;

import 'package:best_ui/best_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';

import '../reader/zoom_physics.dart';

/// Geometry shared by the page renderer and its scroll views.
class ReaderViewportGeometry {
  const ReaderViewportGeometry({
    required this.scale,
    required this.inputLocked,
    required this.focalPoint,
    required this.manualScroll,
  });

  final double scale;
  final bool inputLocked;
  final Offset focalPoint;
  final double manualScroll;

  bool get zoomed => scale > 1.001;
}

class ReaderZoomChange {
  const ReaderZoomChange({
    required this.oldScale,
    required this.scale,
    required this.beforeFocal,
    required this.focalPoint,
    required this.preserveContent,
  });

  final double oldScale;
  final double scale;
  final Offset beforeFocal;
  final Offset focalPoint;
  final bool preserveContent;
}

/// Owns pinch and zoomed panning without stealing ordinary reading swipes.
///
/// Pinch is tracked at the viewport, outside the transformed scroll view. A
/// second pointer locks native dragging for the rest of that pointer sequence,
/// including the finger left behind after a pinch. This also handles a pinch
/// that starts after a pager has already claimed the first finger.
class ReaderGestureViewport extends StatefulWidget {
  const ReaderGestureViewport({
    super.key,
    required this.contentKey,
    required this.scrollableContent,
    required this.builder,
    required this.onTap,
    required this.onReadingDrag,
    required this.onInputLock,
    required this.onZoom,
    required this.onZoomEnd,
    this.onManualScroll,
  });

  final Object contentKey;
  final bool scrollableContent;
  final Widget Function(BuildContext, ReaderViewportGeometry) builder;
  final ValueChanged<Offset> onTap;
  final VoidCallback onReadingDrag;
  final ValueChanged<bool> onInputLock;
  final ValueChanged<ReaderZoomChange> onZoom;
  final VoidCallback onZoomEnd;
  final ValueChanged<double>? onManualScroll;

  @override
  ReaderGestureViewportState createState() => ReaderGestureViewportState();
}

class ReaderGestureViewportState extends State<ReaderGestureViewport>
    with TickerProviderStateMixin {
  final Map<int, Offset> _pointers = {};
  final Map<int, Offset> _starts = {};
  late final AnimationController _animation;
  Timer? _scrollCooldown;
  Size _size = Size.zero;
  double _scale = 1;
  Offset _offset = Offset.zero;
  Offset _focalPoint = Offset.zero;
  double _manualScroll = 0;
  double _pinchDistance = 1;
  double _pinchScale = 1;
  Offset _pinchFocal = Offset.zero;
  Offset _pinchOffset = Offset.zero;
  Offset? _lastPinchFocal;
  double _animationStartScale = 1;
  double _animationEndScale = 1;
  Offset _animationStartOffset = Offset.zero;
  Offset _animationEndOffset = Offset.zero;
  bool _hadMultiplePointers = false;
  bool _moved = false;
  bool _dragReported = false;
  bool _tapBlocked = false;
  bool _scrolling = false;
  bool _cooling = false;
  bool _inputLocked = false;
  bool _quickScaleEligible = false;
  bool _doubleTapDownPending = false;
  bool _quickScaling = false;
  Offset _quickStart = Offset.zero;
  Offset _quickOffset = Offset.zero;
  double _quickScale = 1;
  Duration _downTime = Duration.zero;
  bool _longHeld = false;
  // The raw pan before the rubber band, so a drag past an edge keeps its place.
  Offset _rawOffset = Offset.zero;
  VelocityTracker? _velocityTracker;
  late final Ticker _flingTicker;
  FrictionSimulation? _flingX;
  FrictionSimulation? _flingY;
  bool _settling = false;

  static const double _minScale = 0.5;
  static const double _maxScale = 4.0;
  static const double _flingDrag = 0.135;
  static const double _minFlingSpeed = 300;

  bool get zoomed => _scale > 1.001;
  double get scale => _scale;
  Size get viewportSize => _size;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(vsync: this, duration: BestMotion.normal)
      ..addListener(_animateTick)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          widget.onZoomEnd();
        }
      });
    _flingTicker = createTicker(_flingTick);
  }

  @override
  void didUpdateWidget(ReaderGestureViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contentKey != widget.contentKey) {
      _animation.stop();
      _scale = 1;
      _offset = Offset.zero;
      _rawOffset = Offset.zero;
      // Do not forget a held pointer: its release must not become a menu tap.
      _tapBlocked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.onZoom(
          ReaderZoomChange(
            oldScale: 1,
            scale: 1,
            beforeFocal: Offset.zero,
            focalPoint: Offset.zero,
            preserveContent: false,
          ),
        );
      });
    }
  }

  @override
  void dispose() {
    _scrollCooldown?.cancel();
    _flingTicker.dispose();
    _animation.dispose();
    super.dispose();
  }

  Offset _bounded(Offset offset, double scale) => scale <= 1
      ? Offset(
          _size.width * (1 - scale) / 2,
          widget.scrollableContent ? 0 : _size.height * (1 - scale) / 2,
        )
      : Offset(
          offset.dx.clamp(-_size.width * (scale - 1), 0).toDouble(),
          widget.scrollableContent
              ? 0
              : offset.dy.clamp(-_size.height * (scale - 1), 0).toDouble(),
        );

  /// Pan offset with resistance past the edges. The content still follows the
  /// finger but moves less the further it is pulled, and [_settle] brings it back
  /// on release. At or below fit the content stays centred.
  Offset _rubberOffset(Offset raw, double scale) {
    if (scale <= 1) return _bounded(raw, scale);
    return Offset(
      rubberPan(raw.dx, _size.width, scale),
      widget.scrollableContent ? 0 : rubberPan(raw.dy, _size.height, scale),
    );
  }

  /// [elastic] lets a pinch stretch past a limit until [_settle] springs it back.
  /// [exact] is for settle steps, which must not clamp the values they pass
  /// through, or the content would snap instead of easing.
  void _setZoom(
    double scale,
    Offset offset,
    Offset focal, {
    bool preserveContent = true,
    bool elastic = false,
    bool exact = false,
  }) {
    final next = elastic || exact
        ? scale
        : scale.clamp(_minScale, _maxScale).toDouble();
    final old = _scale;
    final beforeFocal = _focalPoint;
    setState(() {
      _scale = next;
      _offset = exact ? offset : _bounded(offset, next);
      _rawOffset = _offset;
      _focalPoint = focal;
    });
    if ((old - next).abs() > 0.00001 || !preserveContent) {
      widget.onZoom(
        ReaderZoomChange(
          oldScale: old,
          scale: next,
          beforeFocal: beforeFocal,
          focalPoint: focal,
          preserveContent: preserveContent,
        ),
      );
    }
  }

  void reset({bool preserveContent = false}) {
    _animation.stop();
    _setZoom(1, Offset.zero, _focalPoint, preserveContent: preserveContent);
  }

  void panBy(Offset delta) {
    if (!zoomed) return;
    _readingDrag();
    setState(() {
      _offset = _bounded(_offset + delta, _scale);
      _rawOffset = _offset;
    });
    if (widget.scrollableContent && delta.dy != 0) {
      final scroll = -delta.dy / _scale;
      setState(() => _manualScroll += scroll);
      widget.onManualScroll?.call(scroll);
    }
  }

  void _lock(bool locked) {
    if (_inputLocked == locked) return;
    _inputLocked = locked;
    widget.onInputLock(locked);
  }

  void _readingDrag() {
    if (_dragReported) return;
    _dragReported = true;
    widget.onReadingDrag();
  }

  void _pointerDown(PointerDownEvent event) {
    if (_pointers.isEmpty) {
      _hadMultiplePointers = false;
      _moved = false;
      _dragReported = false;
      // A child's recognizer can report the second tap while addPointer is
      // running, before this outer listener receives that same pointer down.
      _quickScaleEligible = _doubleTapDownPending;
      _doubleTapDownPending = false;
      _quickScaling = false;
      _downTime = event.timeStamp;
      _longHeld = false;
      _tapBlocked = _scrolling || _cooling || _animation.isAnimating;
      _animation.stop();
      _flingTicker.stop();
      _rawOffset = _offset;
      _velocityTracker = VelocityTracker.withKind(event.kind)
        ..addPosition(event.timeStamp, event.localPosition);
    }
    _pointers[event.pointer] = event.localPosition;
    _starts[event.pointer] = event.localPosition;
    if (_pointers.length >= 2) {
      _velocityTracker = null;
      _hadMultiplePointers = true;
      _tapBlocked = true;
      _lock(true);
      _beginPinch();
      setState(() {});
    }
  }

  void _beginPinch() {
    final points = _pointers.values.take(2).toList();
    _pinchDistance = math.max((points[0] - points[1]).distance, 1.0);
    _pinchFocal = (points[0] + points[1]) / 2;
    _lastPinchFocal = _pinchFocal;
    _pinchOffset = _offset;
    _pinchScale = _scale;
    _focalPoint = _pinchFocal;
  }

  void _pointerMove(PointerMoveEvent event) {
    final previous = _pointers[event.pointer];
    if (previous == null) return;
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length == 1) {
      _velocityTracker?.addPosition(event.timeStamp, event.localPosition);
    }
    final distance = (event.localPosition - _starts[event.pointer]!).distance;
    if (distance > 8) {
      _moved = true;
      _tapBlocked = true;
    }
    if (distance > kTouchSlop) {
      _readingDrag();
    }
    if (_pointers.length == 1 && _quickScaleEligible && distance > 8) {
      _quickScaling = true;
      _readingDrag();
      final next =
          (_quickScale *
                  math.exp(-((event.localPosition.dy - _quickStart.dy) / 200)))
              .clamp(_minScale, _maxScale)
              .toDouble();
      final content = (_quickStart - _quickOffset) / _quickScale;
      _setZoom(next, _quickStart - content * next, _quickStart);
    } else if (_pointers.length >= 2) {
      final points = _pointers.values.take(2).toList();
      final focal = (points[0] + points[1]) / 2;
      final next = elasticScale(
        _pinchScale * (points[0] - points[1]).distance / _pinchDistance,
        min: _minScale,
        max: _maxScale,
      );
      if ((next - _scale).abs() > 0.005) _readingDrag();
      // Fingers that move together without changing their spread leave the
      // scale alone, so no zoom anchor follows them. Scroll the strip by that
      // movement, the same way a single finger scrolls it while input is locked.
      final previousFocal = _lastPinchFocal;
      _lastPinchFocal = focal;
      if (widget.scrollableContent &&
          previousFocal != null &&
          (next - _scale).abs() <= 0.00001) {
        final scroll = -(focal.dy - previousFocal.dy) / _scale;
        if (scroll != 0) {
          setState(() => _manualScroll += scroll);
          widget.onManualScroll?.call(scroll);
        }
      }
      final content = (_pinchFocal - _pinchOffset) / _pinchScale;
      _setZoom(next, focal - content * next, focal, elastic: true);
    } else if (zoomed || _inputLocked) {
      final delta = event.localPosition - previous;
      _rawOffset += delta;
      setState(() => _offset = _rubberOffset(_rawOffset, _scale));
      if (widget.scrollableContent && _inputLocked && delta.dy != 0) {
        final scroll = -delta.dy / _scale;
        setState(() => _manualScroll += scroll);
        widget.onManualScroll?.call(scroll);
      }
    }
  }

  void _pointerEnd(PointerEvent event) {
    _pointers.remove(event.pointer);
    _starts.remove(event.pointer);
    if (event is PointerCancelEvent) _tapBlocked = true;
    if (_pointers.length >= 2) _beginPinch();
    if (_pointers.isEmpty) {
      _longHeld = event.timeStamp - _downTime > kLongPressTimeout;
      if (_longHeld) _tapBlocked = true;
      _lock(false);
      // Rebuild once after releasing the pinch so children receive
      // inputLocked=false and can take scroll handoff immediately.
      setState(() {});
      final tracker = _velocityTracker;
      _velocityTracker = null;
      final flick =
          tracker == null || _quickScaling || event is PointerCancelEvent
          ? Velocity.zero
          : tracker.getVelocity();
      if (!_startFling(flick)) _settle();
      widget.onZoomEnd();
    }
  }

  bool _scrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification) _scrolling = true;
    if (notification is ScrollUpdateNotification &&
        (notification.scrollDelta ?? 0).abs() > 0.5) {
      _cooling = true;
      _scrollCooldown?.cancel();
      _scrollCooldown = Timer(const Duration(milliseconds: 150), () {
        _cooling = false;
      });
      if (notification.dragDetails != null) _readingDrag();
    }
    if (notification is ScrollEndNotification) _scrolling = false;
    return false;
  }

  void _tap(TapUpDetails details) {
    if (_tapBlocked ||
        _moved ||
        _hadMultiplePointers ||
        _inputLocked ||
        _pointers.isNotEmpty) {
      return;
    }
    widget.onTap(details.localPosition);
  }

  void _doubleTap(TapDownDetails details) {
    _doubleTapDownPending = _pointers.isEmpty;
    _focalPoint = details.localPosition;
    _quickStart = _focalPoint;
    _quickOffset = _offset;
    _quickScale = _scale;
    _quickScaleEligible = true;
    _lock(true);
    setState(() {});
  }

  void _zoomDoubleTap() {
    if (_hadMultiplePointers || _moved || _quickScaling || _longHeld) return;
    _tapBlocked = true;
    _readingDrag();
    _animationStartScale = _scale;
    _animationEndScale = (_scale - 1).abs() > 0.001 ? 1 : 2;
    _animationStartOffset = _offset;
    final point = (_focalPoint - _offset) / _scale;
    _animationEndOffset = _bounded(
      _focalPoint - point * _animationEndScale,
      _animationEndScale,
    );
    _settling = false;
    _animation.forward(from: 0);
  }

  /// Springs the content back inside its limits on release. A scale stretched
  /// past 0.5x or 4x returns to that limit, and a pan past an edge returns to
  /// the edge. The anchor is the last pinch point, so what the fingers were on
  /// stays under them while the scale settles.
  void _settle() {
    final target = _scale.clamp(_minScale, _maxScale).toDouble();
    final point = (_focalPoint - _offset) / _scale;
    final targetOffset = _bounded(_focalPoint - point * target, target);
    final scaleMoves = (target - _scale).abs() > 0.0005;
    final offsetMoves = (targetOffset - _offset).distance > 0.5;
    if (!scaleMoves && !offsetMoves) return;
    _settling = true;
    _animationStartScale = _scale;
    _animationEndScale = target;
    _animationStartOffset = _offset;
    _animationEndOffset = targetOffset;
    _animation.forward(from: 0);
  }

  /// A flick while zoomed keeps the pan moving with friction. Strip scrolling is
  /// not flung here: the list's clamped physics would report overscroll on the
  /// way past the chapter end, and that can advance the chapter.
  bool _startFling(Velocity velocity) {
    if (!zoomed || widget.scrollableContent) return false;
    if ((_bounded(_offset, _scale) - _offset).distance > 0.5) return false;
    var speed = velocity.pixelsPerSecond;
    if (speed.distance < _minFlingSpeed) return false;
    if (speed.distance > kMaxFlingVelocity) {
      speed = speed * (kMaxFlingVelocity / speed.distance);
    }
    _flingX = FrictionSimulation(_flingDrag, _offset.dx, speed.dx);
    _flingY = FrictionSimulation(_flingDrag, _offset.dy, speed.dy);
    _flingTicker.stop();
    _flingTicker.start();
    return true;
  }

  void _flingTick(Duration elapsed) {
    final t = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    final fx = _flingX;
    final fy = _flingY;
    if (fx == null || fy == null) {
      _flingTicker.stop();
      return;
    }
    setState(() {
      _offset = _bounded(Offset(fx.x(t), fy.x(t)), _scale);
      _rawOffset = _offset;
    });
    if (fx.isDone(t) && fy.isDone(t)) {
      _flingTicker.stop();
      widget.onZoomEnd();
    }
  }

  void _animateTick() {
    final t = BestMotion.curve.transform(_animation.value);
    final next =
        _animationStartScale + (_animationEndScale - _animationStartScale) * t;
    _setZoom(
      next,
      Offset.lerp(_animationStartOffset, _animationEndOffset, t)!,
      _focalPoint,
      exact: _settling,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (_size != size) {
          _size = size;
          _offset = _bounded(_offset, _scale);
          _rawOffset = _offset;
        }
        final geometry = ReaderViewportGeometry(
          scale: _scale,
          inputLocked: _inputLocked,
          focalPoint: _focalPoint,
          manualScroll: _manualScroll,
        );
        final height = widget.scrollableContent
            ? size.height / _scale
            : size.height;
        return NotificationListener<ScrollNotification>(
          onNotification: _scrollNotification,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _pointerDown,
            onPointerMove: _pointerMove,
            onPointerUp: _pointerEnd,
            onPointerCancel: _pointerEnd,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: _tap,
              onDoubleTapDown: _doubleTap,
              onDoubleTap: _zoomDoubleTap,
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  minWidth: size.width,
                  maxWidth: size.width,
                  minHeight: height,
                  maxHeight: height,
                  child: Transform(
                    key: const ValueKey('reader-zoom-transform'),
                    alignment: Alignment.topLeft,
                    transform: Matrix4.diagonal3Values(_scale, _scale, 1)
                      ..setTranslationRaw(_offset.dx, _offset.dy, 0),
                    child: SizedBox(
                      width: size.width,
                      height: height,
                      child: widget.builder(context, geometry),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
