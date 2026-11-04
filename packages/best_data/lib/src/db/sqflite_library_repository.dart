import 'dart:async';
import 'dart:convert';

import 'package:best_domain/best_domain.dart';
import 'package:sqflite_common/sqlite_api.dart';

/// SQLite implementation of [LibraryRepository].
///
/// Writes are explicit and merge-safe: a refresh can add metadata but never
/// erase history, a favorite, or a later reading position. Every successful
/// write emits on [changes] so the UI re-runs its query instead of patching a
/// list in place.
class SqfliteLibraryRepository implements LibraryRepository {
  SqfliteLibraryRepository(this._db);

  final Database _db;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => _changes.stream;

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  @override
  Future<List<LibraryEntry>> library([LibraryQuery? query]) async {
    final rows = await _db.rawQuery('''
      SELECT m.*,
             COUNT(DISTINCT u.id) AS total_units,
             COUNT(DISTINCT CASE WHEN p.completed = 1 THEN u.id END) AS completed_units,
             COUNT(DISTINCT CASE WHEN d.status = 'done' THEN d.unit_id END) AS offline_units
      FROM media m
      LEFT JOIN unit u ON u.media_id = m.id
      LEFT JOIN progress p ON p.unit_id = u.id
      LEFT JOIN downloads d ON d.media_id = m.id
      WHERE m.in_library = 1
      GROUP BY m.id
    ''');

    final entries = rows.map((row) {
      return LibraryEntry(
        media: _mediaFromRow(row),
        totalUnits: (row['total_units'] as int?) ?? 0,
        completedUnits: (row['completed_units'] as int?) ?? 0,
        offlineUnits: (row['offline_units'] as int?) ?? 0,
      );
    });

    return LibraryPolicy.apply(entries, query ?? const LibraryQuery());
  }

  @override
  Future<Media?> mediaById(String id) async {
    final rows =
        await _db.query('media', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : _mediaFromRow(rows.first);
  }

  @override
  Future<List<Media>> recent({int limit = 20}) async {
    final rows = await _db.query(
      'media',
      where: 'last_opened_at > 0',
      orderBy: 'last_opened_at DESC',
      limit: limit,
    );
    return rows.map(_mediaFromRow).toList(growable: false);
  }

  @override
  Future<void> saveMedia(Media media) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final addedAt =
        media.addedAt > 0 ? media.addedAt : (media.inLibrary ? now : 0);

    await _db.rawInsert(
      '''
      INSERT INTO media (
        id, source_id, url, title, native_title, cover_url, synopsis, author,
        kind, status, year, genres, rating, memo, in_library, favorite, state,
        tags, added_at, last_opened_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        title = excluded.title,
        native_title = COALESCE(excluded.native_title, media.native_title),
        cover_url = COALESCE(excluded.cover_url, media.cover_url),
        synopsis = COALESCE(excluded.synopsis, media.synopsis),
        author = COALESCE(excluded.author, media.author),
        kind = excluded.kind,
        status = excluded.status,
        year = COALESCE(excluded.year, media.year),
        genres = CASE WHEN excluded.genres = '[]' THEN media.genres ELSE excluded.genres END,
        rating = COALESCE(excluded.rating, media.rating),
        memo = CASE WHEN excluded.memo = '' THEN media.memo ELSE excluded.memo END,
        in_library = MAX(media.in_library, excluded.in_library),
        favorite = MAX(media.favorite, excluded.favorite),
        -- A catalogue refresh must not clear the person's plan or lists; only
        -- setReadingState/setTags are allowed to change them.
        state = CASE WHEN excluded.state = 'none' THEN media.state ELSE excluded.state END,
        tags = CASE WHEN excluded.tags = '[]' THEN media.tags ELSE excluded.tags END,
        added_at = CASE WHEN media.added_at > 0 THEN media.added_at ELSE excluded.added_at END,
        last_opened_at = MAX(media.last_opened_at, excluded.last_opened_at)
      ''',
      [
        media.id,
        media.ref.sourceId,
        media.ref.url,
        media.title,
        media.nativeTitle,
        media.coverUrl,
        media.synopsis,
        media.author,
        media.kind.name,
        media.status.name,
        media.year,
        jsonEncode(media.genres),
        media.rating,
        media.memo,
        media.inLibrary ? 1 : 0,
        media.favorite ? 1 : 0,
        media.state.name,
        jsonEncode(media.tags),
        addedAt,
        media.lastOpenedAt,
      ],
    );
    _notify();
  }

  @override
  Future<void> setInLibrary(String mediaId, bool value) async {
    if (value) {
      final now = DateTime.now().millisecondsSinceEpoch;
      await _db.rawUpdate(
        'UPDATE media SET in_library = 1, added_at = CASE WHEN added_at = 0 THEN ? ELSE added_at END WHERE id = ?',
        [now, mediaId],
      );
    } else {
      await _db
          .rawUpdate('UPDATE media SET in_library = 0 WHERE id = ?', [mediaId]);
    }
    _notify();
  }

  @override
  Future<void> setFavorite(String mediaId, bool value) async {
    await _db.rawUpdate(
      'UPDATE media SET favorite = ? WHERE id = ?',
      [value ? 1 : 0, mediaId],
    );
    _notify();
  }

  @override
  Future<void> setReadingState(String mediaId, ReadingState state) async {
    await _db.rawUpdate(
      'UPDATE media SET state = ? WHERE id = ?',
      [state.name, mediaId],
    );
    _notify();
  }

  @override
  Future<void> setTags(String mediaId, List<String> tags) async {
    await _db.rawUpdate(
      'UPDATE media SET tags = ? WHERE id = ?',
      [jsonEncode(tags), mediaId],
    );
    _notify();
  }

  @override
  Future<List<Media>> allMedia() async {
    final rows = await _db.query('media', orderBy: 'last_opened_at DESC');
    return rows.map(_mediaFromRow).toList(growable: false);
  }

  @override
  Future<List<MediaUnit>> allUnits() async {
    final rows = await _db.query('unit', orderBy: 'media_id, number');
    return rows.map(_unitFromRow).toList(growable: false);
  }

  @override
  Future<List<UnitProgress>> allProgress() async {
    final rows = await _db.query('progress');
    return rows
        .map(
          (row) => UnitProgress(
            unitId: row['unit_id'] as String,
            position: (row['position'] as int?) ?? 0,
            total: (row['total'] as int?) ?? 0,
            completed: ((row['completed'] as int?) ?? 0) == 1,
            updatedAt: (row['updated_at'] as int?) ?? 0,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<DailyActivity>> activity({int days = 400}) async {
    final rows = await _db.query('activity', orderBy: 'day DESC', limit: days);
    final result = rows.map(_activityFromRow).toList()
      ..sort((a, b) => a.day.compareTo(b.day));
    return List.unmodifiable(result);
  }

  @override
  Future<void> recordActivity({
    int pages = 0,
    int minutes = 0,
    int units = 0,
  }) async {
    if (pages == 0 && minutes == 0 && units == 0) return;
    await _db.rawInsert(
      '''
      INSERT INTO activity (day, pages, minutes, units) VALUES (?, ?, ?, ?)
      ON CONFLICT(day) DO UPDATE SET
        pages = activity.pages + excluded.pages,
        minutes = activity.minutes + excluded.minutes,
        units = activity.units + excluded.units
      ''',
      [ReadingStats.dayKey(DateTime.now()), pages, minutes, units],
    );
    _notify();
  }

  @override
  Future<void> mergeActivity(Iterable<DailyActivity> days) async {
    final batch = _db.batch();
    var wrote = false;
    for (final day in days) {
      if (day.isEmpty) continue;
      wrote = true;
      batch.rawInsert(
        '''
        INSERT INTO activity (day, pages, minutes, units) VALUES (?, ?, ?, ?)
        ON CONFLICT(day) DO UPDATE SET
          pages = MAX(activity.pages, excluded.pages),
          minutes = MAX(activity.minutes, excluded.minutes),
          units = MAX(activity.units, excluded.units)
        ''',
        [day.day, day.pages, day.minutes, day.units],
      );
    }
    if (!wrote) return;
    await batch.commit(noResult: true);
    _notify();
  }

  @override
  Future<void> saveUnits(Iterable<MediaUnit> units) async {
    final batch = _db.batch();
    var wrote = false;
    for (final unit in units) {
      wrote = true;
      batch.rawInsert(
        '''
        INSERT INTO unit (id, media_id, url, kind, number, title, published_at, page_count, memo)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          number = excluded.number,
          title = CASE WHEN excluded.title = '' THEN unit.title ELSE excluded.title END,
          published_at = MAX(unit.published_at, excluded.published_at),
          page_count = MAX(unit.page_count, excluded.page_count),
          memo = CASE WHEN excluded.memo = '' THEN unit.memo ELSE excluded.memo END
        ''',
        [
          unit.id,
          unit.mediaId,
          unit.url,
          unit.kind.name,
          unit.number,
          unit.title,
          unit.publishedAt,
          unit.pageCount,
          unit.memo,
        ],
      );
    }
    if (!wrote) return;
    await batch.commit(noResult: true);
    _notify();
  }

  @override
  Future<List<MediaUnit>> unitsFor(String mediaId) async {
    final rows = await _db.query(
      'unit',
      where: 'media_id = ?',
      whereArgs: [mediaId],
      orderBy: 'number ASC',
    );
    return rows.map(_unitFromRow).toList(growable: false);
  }

  @override
  Future<UnitProgress?> progressFor(String unitId) async {
    final rows = await _db.query(
      'progress',
      where: 'unit_id = ?',
      whereArgs: [unitId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return UnitProgress(
      unitId: unitId,
      position: (row['position'] as int?) ?? 0,
      total: (row['total'] as int?) ?? 0,
      completed: ((row['completed'] as int?) ?? 0) == 1,
      updatedAt: (row['updated_at'] as int?) ?? 0,
    );
  }

  @override
  Future<void> saveProgress(UnitProgress progress) async {
    final existing = await progressFor(progress.unitId);
    final merged = existing == null ? progress : existing.merge(progress);
    await _db.insert(
      'progress',
      {
        'unit_id': merged.unitId,
        'position': merged.position,
        'total': merged.total,
        'completed': merged.completed ? 1 : 0,
        'updated_at': merged.updatedAt,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _notify();
  }

  @override
  Future<List<ContinueEntry>> continueReading({int limit = 6}) async {
    final rows = await _db.rawQuery('''
      SELECT m.*,
             u.id AS unit_id, u.url AS unit_url, u.kind AS unit_kind,
             u.number AS unit_number, u.title AS unit_title,
             u.published_at AS unit_published_at, u.page_count AS unit_page_count,
             u.memo AS unit_memo,
             p.position AS progress_position, p.total AS progress_total,
             p.completed AS progress_completed, p.updated_at AS progress_updated_at
      FROM progress p
      JOIN unit u ON u.id = p.unit_id
      JOIN media m ON m.id = u.media_id
      WHERE (p.position > 0 OR p.completed = 1) AND m.in_library = 1
        AND NOT EXISTS (
          SELECT 1 FROM progress newer
          JOIN unit other ON other.id = newer.unit_id
          WHERE other.media_id = m.id
            AND (newer.position > 0 OR newer.completed = 1)
            AND (newer.updated_at > p.updated_at
              OR (newer.updated_at = p.updated_at AND newer.unit_id > p.unit_id))
        )
      ORDER BY p.updated_at DESC, p.unit_id DESC
      LIMIT ?
    ''', [limit]);

    final entries = rows.map((row) {
      final media = _mediaFromRow(row);
      final unit = MediaUnit(
        mediaId: media.id,
        url: row['unit_url'] as String,
        number: (row['unit_number'] as num).toDouble(),
        title: row['unit_title'] as String,
        kind: UnitKind.values.byName(row['unit_kind'] as String),
        publishedAt: (row['unit_published_at'] as int?) ?? 0,
        pageCount: (row['unit_page_count'] as int?) ?? 0,
        memo: (row['unit_memo'] as String?) ?? '',
      );
      final progress = UnitProgress(
        unitId: unit.id,
        position: (row['progress_position'] as int?) ?? 0,
        total: (row['progress_total'] as int?) ?? 0,
        completed: ((row['progress_completed'] as int?) ?? 0) == 1,
        updatedAt: (row['progress_updated_at'] as int?) ?? 0,
      );
      return ContinueEntry(media: media, unit: unit, progress: progress);
    });

    return entries.toList(growable: false);
  }

  @override
  Future<void> removeFromLibrary(String mediaId) =>
      setInLibrary(mediaId, false);

  @override
  Future<List<DownloadTask>> downloads() async {
    final rows = await _db.query('downloads', orderBy: 'updated_at DESC');
    return rows.map(_downloadFromRow).toList(growable: false);
  }

  @override
  Future<DownloadTask?> downloadFor(String unitId) async {
    final rows = await _db.query(
      'downloads',
      where: 'unit_id = ?',
      whereArgs: [unitId],
      limit: 1,
    );
    return rows.isEmpty ? null : _downloadFromRow(rows.first);
  }

  @override
  Future<void> saveDownload(DownloadTask task) async {
    await _db.insert(
      'downloads',
      {
        'unit_id': task.unitId,
        'media_id': task.mediaId,
        'source_id': task.sourceId,
        'media_url': task.mediaUrl,
        'unit_url': task.unitUrl,
        'media_title': task.mediaTitle,
        'unit_title': task.unitTitle,
        'total': task.total,
        'completed': task.completed,
        'bytes': task.bytes,
        'status': task.status.name,
        'error': task.error,
        'directory': task.directory,
        'updated_at': task.updatedAt,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _notify();
  }

  @override
  Future<void> deleteDownload(String unitId) async {
    await _db.delete('downloads', where: 'unit_id = ?', whereArgs: [unitId]);
    _notify();
  }

  @override
  Future<void> close() async {
    await _changes.close();
    await _db.close();
  }

  static DownloadTask _downloadFromRow(Map<String, Object?> row) {
    return DownloadTask(
      unitId: row['unit_id'] as String,
      mediaId: row['media_id'] as String,
      sourceId: row['source_id'] as String,
      mediaUrl: row['media_url'] as String,
      unitUrl: row['unit_url'] as String,
      mediaTitle: row['media_title'] as String,
      unitTitle: row['unit_title'] as String,
      total: (row['total'] as int?) ?? 0,
      completed: (row['completed'] as int?) ?? 0,
      bytes: (row['bytes'] as int?) ?? 0,
      status: DownloadStatus.values.byName(row['status'] as String),
      error: row['error'] as String?,
      directory: row['directory'] as String?,
      updatedAt: (row['updated_at'] as int?) ?? 0,
    );
  }

  static Media _mediaFromRow(Map<String, Object?> row) {
    return Media(
      ref: SourceRef(row['source_id'] as String, row['url'] as String),
      title: row['title'] as String,
      kind: MediaKind.values.byName(row['kind'] as String),
      nativeTitle: row['native_title'] as String?,
      coverUrl: row['cover_url'] as String?,
      synopsis: row['synopsis'] as String?,
      author: row['author'] as String?,
      year: row['year'] as int?,
      status: MediaStatus.values.byName(row['status'] as String),
      genres: _genres(row['genres'] as String?),
      rating: (row['rating'] as num?)?.toDouble(),
      memo: (row['memo'] as String?) ?? '',
      inLibrary: ((row['in_library'] as int?) ?? 0) == 1,
      favorite: ((row['favorite'] as int?) ?? 0) == 1,
      state: _state(row['state'] as String?),
      tags: _tags(row['tags'] as String?),
      addedAt: (row['added_at'] as int?) ?? 0,
      lastOpenedAt: (row['last_opened_at'] as int?) ?? 0,
    );
  }

  static MediaUnit _unitFromRow(Map<String, Object?> row) {
    return MediaUnit(
      mediaId: row['media_id'] as String,
      url: row['url'] as String,
      number: (row['number'] as num).toDouble(),
      title: row['title'] as String,
      kind: UnitKind.values.byName(row['kind'] as String),
      publishedAt: (row['published_at'] as int?) ?? 0,
      pageCount: (row['page_count'] as int?) ?? 0,
      memo: (row['memo'] as String?) ?? '',
    );
  }

  static ReadingState _state(String? raw) {
    for (final state in ReadingState.values) {
      if (state.name == raw) return state;
    }
    return ReadingState.none;
  }

  static List<String> _tags(String? raw) => _stringList(raw);

  static DailyActivity _activityFromRow(Map<String, Object?> row) {
    return DailyActivity(
      day: row['day'] as String,
      pages: (row['pages'] as int?) ?? 0,
      minutes: (row['minutes'] as int?) ?? 0,
      units: (row['units'] as int?) ?? 0,
    );
  }

  static List<String> _genres(String? raw) => _stringList(raw);

  static List<String> _stringList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.whereType<String>().toList(growable: false);
      }
    } on FormatException {
      // A row written by a future schema should not take the shelf down.
    }
    return const [];
  }
}
