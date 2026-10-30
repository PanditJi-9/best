import 'dart:math' as math;

/// Where a person stopped inside one unit.
///
/// [position] is a zero-based page for reading and a second for video. [total]
/// is `0` when the source has not reported a page count yet, so the UI must not
/// divide by it.
class UnitProgress {
  const UnitProgress({
    required this.unitId,
    required this.updatedAt,
    this.position = 0,
    this.total = 0,
    this.completed = false,
  });

  final String unitId;
  final int position;
  final int total;
  final bool completed;

  /// Epoch milliseconds of the last write. The tie-breaker for every merge.
  final int updatedAt;

  double get fraction {
    if (total <= 0) return completed ? 1 : 0;
    return (position / total).clamp(0.0, 1.0);
  }

  /// Merges two writes of the same unit from two devices.
  ///
  /// The later write wins the position; completion is a union because finishing
  /// a chapter is a fact that a stale backup must not erase; the page count is
  /// the largest ever reported because sources only grow more accurate.
  ///
  /// A write with an older timestamp can never move the reader backwards, even
  /// if it arrives later over the network.
  UnitProgress merge(UnitProgress other) {
    assert(unitId == other.unitId, 'Progress for two different units cannot merge.');
    final newer = updatedAt >= other.updatedAt ? this : other;
    final merged = UnitProgress(
      unitId: unitId,
      position: newer.position,
      total: math.max(total, other.total),
      completed: completed || other.completed,
      updatedAt: math.max(updatedAt, other.updatedAt),
    );

    // A position can never point past the last page. A position without a total
    // is kept as-is: guessing a bound would lose real progress.
    if (merged.total > 0 && merged.position > merged.total - 1) {
      return UnitProgress(
        unitId: merged.unitId,
        position: merged.total - 1,
        total: merged.total,
        completed: merged.completed,
        updatedAt: merged.updatedAt,
      );
    }
    return merged;
  }

  @override
  String toString() => 'UnitProgress($unitId, $position/$total, done=$completed)';
}
