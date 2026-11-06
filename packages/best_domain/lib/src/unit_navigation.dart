import 'downloads.dart';
import 'progress.dart';
import 'search_text.dart';
import 'units.dart';

enum UnitFilter { all, unread, inProgress, downloaded }

enum UnitSort { oldest, newest }

enum UnitContinuationKind { start, resume, next, catchUp, replay }

class UnitContinuation {
  const UnitContinuation(this.unit, this.kind, {this.progress});

  final MediaUnit unit;
  final UnitContinuationKind kind;
  final UnitProgress? progress;
}

/// Presentation filters never replace the chapter sequence used by the reader.
/// All navigation decisions use the full source list in stable reading order.
class UnitNavigation {
  const UnitNavigation._();

  static bool hasChronologicalOrder(Iterable<MediaUnit> units) {
    final list = units.toList();
    if (list.isEmpty) return false;
    return (list.every((u) => u.number.isFinite && u.number >= 0) &&
            list.any((u) => u.number > 0)) ||
        list.every((u) => u.publishedAt > 0);
  }

  static List<MediaUnit> readingOrder(Iterable<MediaUnit> units) {
    final byId = <String, MediaUnit>{};
    for (final unit in units) {
      final previous = byId[unit.id];
      byId[unit.id] = previous == null
          ? unit
          : unit.copyWith(
              title: unit.title.trim().isEmpty ? previous.title : unit.title,
              memo: unit.memo.isEmpty ? previous.memo : unit.memo,
              pageCount:
                  unit.pageCount <= 0 ? previous.pageCount : unit.pageCount,
              publishedAt: unit.publishedAt <= 0
                  ? previous.publishedAt
                  : unit.publishedAt,
            );
    }
    final list = byId.values.toList();
    final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
    final numbered = list.every((u) => u.number.isFinite && u.number >= 0) &&
        list.any((u) => u.number > 0);
    final dated = list.isNotEmpty && list.every((u) => u.publishedAt > 0);
    if (numbered || dated) {
      indexed.sort((a, b) {
        final order = numbered
            ? a.$2.number.compareTo(b.$2.number)
            : a.$2.publishedAt.compareTo(b.$2.publishedAt);
        return order == 0 ? a.$1.compareTo(b.$1) : order;
      });
    }
    return List.unmodifiable(indexed.map((entry) => entry.$2));
  }

  static bool hasStarted(UnitProgress? progress) =>
      progress != null &&
      (progress.position > 0 || progress.started || progress.completed);

  static UnitContinuation? continuation(
    Iterable<MediaUnit> sourceUnits,
    Map<String, UnitProgress> progress, {
    bool allowReplay = true,
  }) {
    final units = readingOrder(sourceUnits);
    if (units.isEmpty) return null;
    var latestIndex = -1;
    UnitProgress? latest;
    for (var i = 0; i < units.length; i++) {
      final saved = progress[units[i].id];
      if (!hasStarted(saved)) continue;
      if (latest == null || saved!.updatedAt >= latest.updatedAt) {
        latest = saved;
        latestIndex = i;
      }
    }
    if (latest == null) {
      return UnitContinuation(units.first, UnitContinuationKind.start);
    }
    if (!latest.completed) {
      return UnitContinuation(units[latestIndex], UnitContinuationKind.resume,
          progress: latest);
    }
    for (var i = latestIndex + 1; i < units.length; i++) {
      final saved = progress[units[i].id];
      if (saved?.completed ?? false) continue;
      return UnitContinuation(
        units[i],
        hasStarted(saved)
            ? UnitContinuationKind.resume
            : UnitContinuationKind.next,
        progress: saved,
      );
    }
    for (final unit in units) {
      if (!(progress[unit.id]?.completed ?? false)) {
        return UnitContinuation(unit, UnitContinuationKind.catchUp,
            progress: progress[unit.id]);
      }
    }
    return allowReplay
        ? UnitContinuation(units.first, UnitContinuationKind.replay)
        : null;
  }

  static List<MediaUnit> visible(
    Iterable<MediaUnit> units, {
    String query = '',
    UnitFilter filter = UnitFilter.all,
    UnitSort sort = UnitSort.oldest,
    Map<String, UnitProgress> progress = const {},
    Map<String, DownloadTask> downloads = const {},
  }) {
    final text = SearchText.normalize(query).trim();
    final numberQuery = text.replaceFirst(
      RegExp(
          r'^(?:chapter|chap\.?|ch\.?|episode|ep\.?|الفصل|فصل|الحلقه|حلقه)\s*'),
      '',
    );
    final result = readingOrder(units).where((unit) {
      final number = unit.number.isFinite
          ? (unit.number == unit.number.roundToDouble()
              ? unit.number.toInt().toString()
              : unit.number.toString())
          : '';
      final matches = text.isEmpty ||
          SearchText.matches(unit.displayTitle, text) ||
          (numberQuery.isNotEmpty && SearchText.matches(number, numberQuery));
      if (!matches) return false;
      final saved = progress[unit.id];
      return switch (filter) {
        UnitFilter.all => true,
        UnitFilter.unread => !(saved?.completed ?? false),
        UnitFilter.inProgress =>
          hasStarted(saved) && !(saved?.completed ?? false),
        UnitFilter.downloaded => downloads[unit.id]?.isFinished ?? false,
      };
    }).toList();
    return List.unmodifiable(
        sort == UnitSort.newest ? result.reversed : result);
  }
}
