// Pure curves for the reader's zoom and pan. No widgets or controllers here, so
// the resistance and the limits can be tested directly.

/// Slope at the edge. Right past a limit the content moves about 0.55 of the
/// finger's distance, and less the further out the finger is pulled.
const double _edgeSlope = 0.55;

/// The part of [overshoot] past a limit that still moves the content, for a
/// viewport of [extent]. It grows more slowly the further past the limit the
/// finger goes, and it never reaches [extent].
double rubberBand(double overshoot, double extent) {
  if (overshoot <= 0 || extent <= 0) return 0;
  return (1 - 1 / (overshoot * _edgeSlope / extent + 1)) * extent;
}

/// A pinch scale that stretches past [min] or [max] with resistance, instead of
/// stopping dead. The end of the gesture springs it back to the limit.
double elasticScale(double raw, {required double min, required double max}) {
  if (raw < min) return min - rubberBand(min - raw, min);
  if (raw > max) return max + rubberBand(raw - max, max);
  return raw;
}

/// A pan offset along one zoomed axis of [viewport] size. The resting range runs
/// from 0 at the leading edge down to -viewport * (scale - 1). Past either edge
/// the offset still follows the finger, with resistance.
double rubberPan(double raw, double viewport, double scale) {
  final lower = -viewport * (scale - 1);
  if (raw > 0) return rubberBand(raw, viewport);
  if (raw < lower) return lower - rubberBand(lower - raw, viewport);
  return raw;
}
