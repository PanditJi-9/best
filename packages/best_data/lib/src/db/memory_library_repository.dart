import 'dart:async';
import 'dart:math' as math;

import 'package:best_domain/best_domain.dart';

/// An in-memory [LibraryRepository] with the same merge rules as the SQLite one.
///
/// It exists for three reasons: widget tests need a repository without a
/// platform channel, the app can still start if opening the database fails, and
/// the merge behaviour is readable in one file instead of inferred from SQL.
class MemoryLibraryRepository implements LibraryRepository {
  MemoryLibraryRepository({Iterable<Media> seed = const []}) {
    for (final media in seed) {
      _media[media.id] = media;
    }
  }

  final Map<String, Media> _media = {};
  final Map<String, MediaUnit> _units = {};
  final Map<String, UnitProgress> _progress = {};
  final Map<String, DownloadTask> _downloads = {};
  final Map<String, DailyActivity> _activity = {};
  final StreamController<void> _changes = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => _changes.stream;

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  @override
  Future<List<LibraryEntry>> library([LibraryQuery? query]) async {
    final entries = <LibraryEntry>[];
    for (final media in _media.values) {
      if (!media.inLibrary) continue;
      final units = _units.values.where((unit) => unit.mediaId == media.id);
      final total = units.length;
      var completed = 0;
      for (final unit in units) {
        if (_progress[unit.id]?.completed ?? false) completed++;
      }
      entries.add(
        LibraryEntry(
          media: media,
          totalUnits: total,
          completedUnits: completed,
          offlineUnits: _downloads.values
              .where((task) => task.mediaId == media.id && task.isFinished)
              .length,
        ),
      );
    }
    return LibraryPolicy.apply(entries, query ?? const LibraryQuery());
  }

  @override
  Future<Media?> mediaById(String id) async => _media[id];

  @override
  Future<List<Media>> recent({int limit = 20}) async {
    final rows = _media.values.where((media) => media.lastOpenedAt > 0).toList()
      ..sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));
    return List.unmodifiable(rows.take(limit));
  }

  @override
  Future<void> forgetOpened(String mediaId) async {
    final media = _media[mediaId];
    if (media == null) return;
    _media[mediaId] = media.copyWith(lastOpenedAt: 0);
    _notify();
  }

  @override
  Future<void> saveMedia(Media media) async {
    final existing = _media[media.id];
    if (existing == null) {
      _media[media.id] = media;
    } else {
      _media[media.id] = Media(
        ref: media.ref,
        title: media.title,
        kind: media.kind,
        nativeTitle: media.nativeTitle ?? existing.nativeTitle,
        coverUrl: media.coverUrl ?? existing.coverUrl,
        synopsis: media.synopsis ?? existing.synopsis,
        author: media.author ?? existing.author,
        year: media.year ?? existing.year,
        status: media.status,
        genres: media.genres.isEmpty ? existing.genres : media.genres,
        rating: media.rating ?? existing.rating,
        memo: media.memo.isEmpty ? existing.memo : media.memo,
        inLibrary: existing.inLibrary || media.inLibrary,
        favorite: existing.favorite || media.favorite,
        state: media.state == ReadingState.none ? existing.state : media.state,
        tags: media.tags.isEmpty ? existing.tags : media.tags,
        addedAt: existing.addedAt > 0 ? existing.addedAt : media.addedAt,
        lastOpenedAt: existing.lastOpenedAt > media.lastOpenedAt
            ? existing.lastOpenedAt
            : media.lastOpenedAt,
      );
    }
    _notify();
  }

  @override
  Future<void> setInLibrary(String mediaId, bool value) async {
    final media = _media[mediaId];
    if (media == null) return;
    _media[mediaId] = media.copyWith(
      inLibrary: value,
      addedAt: value && media.addedAt == 0
          ? DateTime.now().millisecondsSinceEpoch
          : media.addedAt,
    );
    _notify();
  }

  @override
  Future<void> setFavorite(String mediaId, bool value) async {
    final media = _media[mediaId];
    if (media == null) return;
    _media[mediaId] = media.copyWith(favorite: value);
    _notify();
  }

  @override
  Future<void> setReadingState(String mediaId, ReadingState state) async {
    final media = _media[mediaId];
    if (media == null) return;
    _media[mediaId] = media.copyWith(state: state);
    _notify();
  }

  @override
  Future<void> setTags(String mediaId, List<String> tags) async {
    final media = _media[mediaId];
    if (media == null) return;
    _media[mediaId] = media.copyWith(tags: List.unmodifiable(tags));
    _notify();
  }

  @override
  Future<List<Media>> allMedia() async {
    final rows = _media.values.toList()
      ..sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));
    return List.unmodifiable(rows);
  }

  @override
  Future<List<MediaUnit>> allUnits() async {
    final rows = _units.values.toList()
      ..sort((a, b) {
        final byMedia = a.mediaId.compareTo(b.mediaId);
        return byMedia != 0 ? byMedia : a.number.compareTo(b.number);
      });
    return List.unmodifiable(rows);
  }

  @override
  Future<List<UnitProgress>> allProgress() async =>
      List.unmodifiable(_progress.values);

  @override
  Future<List<DailyActivity>> activity({int days = 400}) async {
    final rows = _activity.values.toList()
      ..sort((a, b) => a.day.compareTo(b.day));
    return List.unmodifiable(
        rows.skip(rows.length > days ? rows.length - days : 0));
  }

  @override
  Future<void> recordActivity({
    int pages = 0,
    int minutes = 0,
    int units = 0,
  }) async {
    if (pages == 0 && minutes == 0 && units == 0) return;
    final key = ReadingStats.dayKey(DateTime.now());
    final existing = _activity[key];
    _activity[key] = existing == null
        ? DailyActivity(day: key, pages: pages, minutes: minutes, units: units)
        : existing.plus(pages: pages, minutes: minutes, units: units);
    _notify();
  }

  @override
  Future<void> mergeActivity(Iterable<DailyActivity> days) async {
    var wrote = false;
    for (final day in days) {
      if (day.isEmpty) continue;
      wrote = true;
      final existing = _activity[day.day];
      _activity[day.day] = existing == null
          ? day
          : DailyActivity(
              day: day.day,
              pages: math.max(existing.pages, day.pages),
              minutes: math.max(existing.minutes, day.minutes),
              units: math.max(existing.units, day.units),
            );
    }
    if (wrote) _notify();
  }

  @override
  Future<void> saveUnits(Iterable<MediaUnit> units) async {
    var wrote = false;
    for (final unit in units) {
      wrote = true;
      final existing = _units[unit.id];
      _units[unit.id] = existing == null
          ? unit
          : unit.copyWith(
              title: unit.title.isEmpty ? existing.title : unit.title,
              publishedAt: unit.publishedAt > existing.publishedAt
                  ? unit.publishedAt
                  : existing.publishedAt,
              pageCount: unit.pageCount > existing.pageCount
                  ? unit.pageCount
                  : existing.pageCount,
              memo: unit.memo.isEmpty ? existing.memo : unit.memo,
            );
    }
    if (wrote) _notify();
  }

  @override
  Future<List<MediaUnit>> unitsFor(String mediaId) async {
    final rows = _units.values.where((unit) => unit.mediaId == mediaId).toList()
      ..sort((a, b) => a.number.compareTo(b.number));
    return List.unmodifiable(rows);
  }

  @override
  Future<UnitProgress?> progressFor(String unitId) async => _progress[unitId];

  @override
  Future<void> saveProgress(UnitProgress progress) async {
    final existing = _progress[progress.unitId];
    _progress[progress.unitId] =
        existing == null ? progress : existing.merge(progress);
    _notify();
  }

  @override
  Future<List<ContinueEntry>> continueReading({int limit = 6}) async {
    final entries = <ContinueEntry>[];
    for (final progress in _progress.values) {
      if (!UnitNavigation.hasStarted(progress)) continue;
      final unit = _units[progress.unitId];
      if (unit == null) continue;
      final media = _media[unit.mediaId];
      if (media == null || !media.inLibrary) continue;
      entries.add(ContinueEntry(media: media, unit: unit, progress: progress));
    }
    entries.sort((a, b) {
      final time = b.progress.updatedAt.compareTo(a.progress.updatedAt);
      return time != 0 ? time : b.unit.id.compareTo(a.unit.id);
    });
    final seen = <String>{};
    return List.unmodifiable(
      entries.where((entry) => seen.add(entry.media.id)).take(limit),
    );
  }

  @override
  Future<void> removeFromLibrary(String mediaId) =>
      setInLibrary(mediaId, false);

  @override
  Future<void> migrateMedia({
    required String fromMediaId,
    required Media target,
    required List<UnitProgress> carriedProgress,
    bool removeOldFromLibrary = true,
  }) async {
    final old = _media[fromMediaId];
    if (old == null) {
      throw StateError('The work being migrated is not stored.');
    }
    if (old.id == target.id) return;

    // Both sides may already carry categories: keep the union, target first,
    // so moving a work never drops a label from either row.
    final existingTarget = _media[target.id];
    final tags = <String>[];
    for (final tag in [
      ...?existingTarget?.tags,
      ...target.tags,
      ...old.tags,
    ]) {
      final clean = tag.trim();
      if (clean.isNotEmpty && !tags.contains(clean)) tags.add(clean);
    }
    final merged = target.copyWith(
      inLibrary: old.inLibrary || target.inLibrary,
      favorite: old.favorite || target.favorite,
      state: target.state == ReadingState.none ? old.state : target.state,
      tags: tags,
      addedAt: target.addedAt > 0 ? target.addedAt : old.addedAt,
      lastOpenedAt: math.max(old.lastOpenedAt, target.lastOpenedAt),
    );
    await saveMedia(merged);
    for (final progress in carriedProgress) {
      await saveProgress(progress);
    }
    if (removeOldFromLibrary) await setInLibrary(fromMediaId, false);
  }

  @override
  Future<List<DownloadTask>> downloads() async {
    final rows = _downloads.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return List.unmodifiable(rows);
  }

  @override
  Future<DownloadTask?> downloadFor(String unitId) async => _downloads[unitId];

  @override
  Future<void> saveDownload(DownloadTask task) async {
    _downloads[task.unitId] = task;
    _notify();
  }

  @override
  Future<void> deleteDownload(String unitId) async {
    _downloads.remove(unitId);
    _notify();
  }

  final Map<String, PageOcrResult> _ocrCache = {};

  @override
  Future<PageOcrResult?> getPageOcr(String unitId, int pageIndex) async {
    return _ocrCache['$unitId:$pageIndex'];
  }

  @override
  Future<void> savePageOcr(String unitId, PageOcrResult result) async {
    _ocrCache['$unitId:${result.pageIndex}'] = result;
  }

  @override
  Future<void> close() async {
    await _changes.close();
  }
}
