import 'dart:async';

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
        inLibrary: existing.inLibrary || media.inLibrary,
        favorite: existing.favorite || media.favorite,
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
      if (progress.position <= 0) continue;
      final unit = _units[progress.unitId];
      if (unit == null) continue;
      final media = _media[unit.mediaId];
      if (media == null || !media.inLibrary) continue;
      entries.add(ContinueEntry(media: media, unit: unit, progress: progress));
    }
    entries
        .sort((a, b) => b.progress.updatedAt.compareTo(a.progress.updatedAt));
    return List.unmodifiable(entries.take(limit));
  }

  @override
  Future<void> removeFromLibrary(String mediaId) =>
      setInLibrary(mediaId, false);

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

  @override
  Future<void> close() async {
    await _changes.close();
  }
}
