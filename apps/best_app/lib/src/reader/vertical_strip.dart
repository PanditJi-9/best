// Pure rules for the vertical (webtoon) strip and its auto-scroll control.
//
// Free of widgets and scroll controllers, so the reading math can be unit
// tested without a device or a frame.

/// Speeds the auto-scroll control steps through on long-press, starting at 1x.
const List<double> autoScrollSpeeds = [1.0, 2.0, 3.0, 0.5];

/// The speed after [current] in [autoScrollSpeeds]. An unknown speed resets to
/// 1x, so a stale value can never leave the control stuck.
double nextAutoScrollSpeed(double current) {
  final index = autoScrollSpeeds.indexOf(current);
  return autoScrollSpeeds[(index + 1) % autoScrollSpeeds.length];
}

/// Badge text for a speed other than 1x, such as `×2` or `×0.5`. Null at 1x,
/// where the control shows no badge.
String? autoScrollSpeedLabel(double speed) {
  if (speed == 1) return null;
  final text = speed % 1 == 0 ? speed.toInt().toString() : speed.toString();
  return '×$text';
}

/// Where the reading line sits, as a fraction of the viewport height.
const double _readingLine = 0.5;

/// Float noise allowed when deciding that the bottom edge is on screen.
const double _endTolerance = 0.002;

/// Whether the strip cannot scroll any further: its last item is the final one
/// and its bottom edge is on screen. [trailing] is that edge as a fraction of
/// the viewport height, counted from the top.
bool isAtVerticalStripEnd({
  required int lastIndex,
  required int itemCount,
  required double trailing,
}) {
  return itemCount > 0 &&
      lastIndex == itemCount - 1 &&
      trailing <= 1 + _endTolerance;
}

/// Share of the strip above the reading line, from 0 to 1.
///
/// [pageCount] counts real pages. A chapter-end card, when shown, sits at
/// index [pageCount] and reads as complete. [leading] and [trailing] are the
/// current item's edges as fractions of the viewport height. Once [atStripEnd]
/// the strip reads complete, since the reading line sits mid-screen and would
/// otherwise stop short of 100% at the bottom.
double verticalStripProgress({
  required int pageCount,
  required int index,
  required double leading,
  required double trailing,
  required bool atStripEnd,
}) {
  if (pageCount <= 0) return 0.0;
  if (atStripEnd) return 1.0;
  final extent = trailing - leading;
  final within = extent <= 0
      ? 0.0
      : ((_readingLine - leading) / extent).clamp(0.0, 1.0).toDouble();
  final page = index.clamp(0, pageCount).toInt();
  return ((page + within) / pageCount).clamp(0.0, 1.0).toDouble();
}
