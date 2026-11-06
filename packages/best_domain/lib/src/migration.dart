import 'dart:math' as math;

import 'progress.dart';
import 'search_text.dart';
import 'unit_number.dart';
import 'units.dart';

/// One chapter that exists on both sides of a migration.
class MigrationPair {
  const MigrationPair({required this.from, required this.to});

  final MediaUnit from;
  final MediaUnit to;
}

/// Which chapters survive when a work moves to another source.
///
/// Sources do not share chapter ids, and their labels differ ("Chapter 12",
/// "12", "الفصل ١٢"). Matching is deliberately conservative: the same number
/// wins, a normalised title is the fallback, and nothing is paired twice. A
/// chapter that cannot be identified is reported as unmatched instead of being
/// guessed, because the wrong chapter is worse than a missing one.
class MigrationPlan {
  const MigrationPlan({
    required this.pairs,
    required this.unmatchedOld,
    required this.totalOld,
  });

  final List<MigrationPair> pairs;
  final List<MediaUnit> unmatchedOld;
  final int totalOld;

  bool get isEmpty => pairs.isEmpty;

  /// The share of the old chapter list that was found on the target,
  /// `0.0`–`1.0`. An old work with no chapters reports zero.
  double get coverage =>
      totalOld == 0 ? 0 : (pairs.length / totalOld).clamp(0.0, 1.0);

  static MigrationPlan between(
    Iterable<MediaUnit> from,
    Iterable<MediaUnit> to,
  ) {
    final oldUnits = from.toList()..sort(_byNumber);
    final available = to.toList()..sort(_byNumber);
    final pairs = <MigrationPair>[];
    final unmatched = <MediaUnit>[];

    for (final old in oldUnits) {
      final match = _takeByNumber(available, old) ?? _takeByTitle(available, old);
      if (match == null) {
        unmatched.add(old);
      } else {
        pairs.add(MigrationPair(from: old, to: match));
      }
    }

    return MigrationPlan(
      pairs: List.unmodifiable(pairs),
      unmatchedOld: List.unmodifiable(unmatched),
      totalOld: oldUnits.length,
    );
  }

  /// The stored positions of [progress] translated onto the target units.
  ///
  /// Only matched chapters travel. A page position is clamped to the target's
  /// page count when it knows one, and completion stays a fact: a chapter the
  /// person finished on the old source is finished here too. The timestamp is
  /// kept so a later merge can still tell which write is newer.
  List<UnitProgress> carryProgress(Map<String, UnitProgress> progress) {
    final carried = <UnitProgress>[];
    for (final pair in pairs) {
      final saved = progress[pair.from.id];
      if (saved == null) continue;
      final targetTotal = pair.to.pageCount;
      final total = targetTotal > 0 ? targetTotal : saved.total;
      var position = saved.position;
      if (total > 0 && position > total - 1) position = math.max(0, total - 1);
      carried.add(
        UnitProgress(
          unitId: pair.to.id,
          position: position,
          total: total,
          completed: saved.completed,
          updatedAt: saved.updatedAt,
        ),
      );
    }
    return List.unmodifiable(carried);
  }

  static int _byNumber(MediaUnit a, MediaUnit b) {
    final byNumber = a.number.compareTo(b.number);
    return byNumber != 0 ? byNumber : a.title.compareTo(b.title);
  }

  static MediaUnit? _takeByNumber(List<MediaUnit> available, MediaUnit old) {
    final wanted = _numberKey(old.number);
    if (wanted == null) return null;
    for (var i = 0; i < available.length; i++) {
      if (_numberKey(available[i].number) == wanted) {
        return available.removeAt(i);
      }
    }
    return null;
  }

  /// Sources disagree on whether a number of `0` means "unknown" or "chapter
  /// zero". A zero is therefore not trusted for matching; the label is.
  static String? _numberKey(double value) {
    if (value <= 0) return null;
    return value.toStringAsFixed(3);
  }

  static MediaUnit? _takeByTitle(List<MediaUnit> available, MediaUnit old) {
    final wanted = _titleKey(old);
    if (wanted.isEmpty) return null;
    for (var i = 0; i < available.length; i++) {
      if (_titleKey(available[i]) == wanted) return available.removeAt(i);
    }
    return null;
  }

  static String _titleKey(MediaUnit unit) {
    final title = unit.title.trim();
    if (title.isEmpty) return '';
    final normalized = _stripLabel(SearchText.normalize(title));
    if (normalized.length < 2) return '';
    return normalized;
  }

  /// "Chapter 12" and "12" must land on the same key, so the word around the
  /// number is dropped. Numbers themselves stay: they are the identity.
  static String _stripLabel(String text) {
    var result = text;
    for (final word in const [
      'chapter',
      'chap',
      'ch',
      'episode',
      'ep',
      'الفصل',
      'فصل',
      'الحلقه',
      'حلقه',
      'الحلقة',
      'حلقة',
      '話',
      '话',
    ]) {
      result = result.replaceAll(word, ' ');
    }
    result = result.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (result.isNotEmpty) return result;
    final number = parseUnitNumber(text);
    return number == null ? '' : number.toStringAsFixed(3);
  }
}
