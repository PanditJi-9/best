import 'dart:convert';

/// A shelf we curate by hand: a short list of works, named by their source and
/// that source's own id.
///
/// The list ships inside the app so the first launch is never empty, and the
/// app refreshes it from the project's repository. That means the front page can
/// change without a store release — the one thing a demo shelf cannot do — while
/// every entry still points at a real catalogue instead of copied pages.
class CuratedException implements Exception {
  const CuratedException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A curated document is a shelf, not a database.
const int kMaxCuratedPicks = 40;

/// Larger than this and the file is not a shelf any more.
const int kMaxCuratedBytes = 128 * 1024;

class CuratedPick {
  const CuratedPick({required this.sourceId, required this.id});

  final String sourceId;
  final String id;
}

class CuratedList {
  const CuratedList({
    required this.version,
    required this.picks,
    this.updated,
  });

  static const CuratedList empty = CuratedList(version: 1, picks: []);

  final int version;

  /// ISO date of the last hand edit, for the "updated" line if we ever show it.
  final String? updated;

  final List<CuratedPick> picks;

  static CuratedList parse(String raw) {
    if (raw.trim().isEmpty) {
      throw const CuratedException('The curated list is empty.');
    }
    if (raw.length > kMaxCuratedBytes) {
      throw const CuratedException('The curated list is larger than 128 KB.');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw const CuratedException('The curated list is not valid JSON.');
    }
    if (decoded is! Map<String, Object?>) {
      throw const CuratedException('The curated list must be a JSON object.');
    }

    final version = decoded['version'];
    if (version is! int || version < 1) {
      throw const CuratedException('The curated list needs a version.');
    }
    if (version > 1) {
      throw CuratedException(
        'This list uses format $version; this Best reads up to 1.',
      );
    }

    final rawPicks = decoded['picks'];
    if (rawPicks is! List) {
      throw const CuratedException('The curated list needs a picks array.');
    }

    final picks = <CuratedPick>[];
    final seen = <String>{};
    for (final entry in rawPicks.whereType<Map<String, Object?>>()) {
      final sourceId = entry['sourceId'];
      final id = entry['id'];
      if (sourceId is! String || id is! String) continue;
      final source = sourceId.trim();
      final work = id.trim();
      if (source.isEmpty || work.isEmpty) continue;
      if (!seen.add('$source::$work')) continue;
      picks.add(CuratedPick(sourceId: source, id: work));
      if (picks.length == kMaxCuratedPicks) break;
    }

    final updated = decoded['updated'];
    return CuratedList(
      version: version,
      updated: updated is String ? updated : null,
      picks: List.unmodifiable(picks),
    );
  }
}
