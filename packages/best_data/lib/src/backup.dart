import 'dart:convert';

import 'package:best_domain/best_domain.dart';

/// A backup that a person can read, copy and paste.
///
/// JSON, not SQLite: a backup has to survive a phone that is gone, so it must be
/// a document a person can keep in a chat, a mail draft or a cloud drive, and
/// that a future version can still parse. The format carries a version number
/// so a later schema can migrate instead of guessing.
class LibraryBackup {
  const LibraryBackup._();

  static const String format = 'best.library';

  /// Format 2 adds the installed source packs. Format 1 documents still restore:
  /// a missing section is an empty section.
  static const int version = 2;

  /// A backup plus the source packs that make it useful.
  ///
  /// Packs are carried as their canonical documents, not as objects, so the
  /// backup format does not depend on the pack parser in this package and an
  /// older Best can still read the rest of the file.
  static String encode(
    LibrarySnapshot snapshot, {
    List<String> sources = const [],
  }) {
    final document = <String, Object?>{
      'format': format,
      'version': version,
      'exportedAt':
          snapshot.exportedAt > 0 ? snapshot.exportedAt : DateTime.now().millisecondsSinceEpoch,
      'media': [
        for (final work in snapshot.media)
          <String, Object?>{
            'sourceId': work.ref.sourceId,
            'url': work.ref.url,
            'title': work.title,
            'kind': work.kind.name,
            'nativeTitle': work.nativeTitle,
            'coverUrl': work.coverUrl,
            'synopsis': work.synopsis,
            'author': work.author,
            'year': work.year,
            'status': work.status.name,
            'genres': work.genres,
            'memo': work.memo,
            'inLibrary': work.inLibrary,
            'favorite': work.favorite,
            'state': work.state.name,
            'tags': work.tags,
            'addedAt': work.addedAt,
            'lastOpenedAt': work.lastOpenedAt,
          },
      ],
      'units': [
        for (final unit in snapshot.units)
          <String, Object?>{
            'mediaId': unit.mediaId,
            'url': unit.url,
            'number': unit.number,
            'title': unit.title,
            'kind': unit.kind.name,
            'publishedAt': unit.publishedAt,
            'pageCount': unit.pageCount,
            'memo': unit.memo,
          },
      ],
      'progress': [
        for (final row in snapshot.progress)
          <String, Object?>{
            'unitId': row.unitId,
            'position': row.position,
            'total': row.total,
            'completed': row.completed,
            'updatedAt': row.updatedAt,
          },
      ],
      'activity': [
        for (final day in snapshot.activity)
          <String, Object?>{
            'day': day.day,
            'pages': day.pages,
            'minutes': day.minutes,
            'units': day.units,
          },
      ],
      'sources': sources,
    };
    return const JsonEncoder.withIndent('  ').convert(document);
  }

  /// Parses a document, or throws [BackupException] with a message worth
  /// showing. Unknown extra keys are ignored so a newer backup still restores.
  static LibrarySnapshot decode(String raw) => decodeDocument(raw).snapshot;

  /// Like [decode], but keeps the source packs so a restore can reinstall them.
  static BackupDocument decodeDocument(String raw) {
    final Object? parsed;
    try {
      parsed = jsonDecode(raw.trim());
    } on FormatException {
      throw const BackupException('This is not JSON.');
    }
    if (parsed is! Map<String, Object?>) {
      throw const BackupException('A backup is a JSON object.');
    }
    if (parsed['format'] != format) {
      throw const BackupException('This file is not a Best backup.');
    }
    final version = parsed['version'];
    if (version is! int || version < 1 || version > LibraryBackup.version) {
      throw BackupException(
        'This backup was written by a newer Best (format $version).',
      );
    }

    final snapshot = LibrarySnapshot(
      exportedAt: _int(parsed['exportedAt']),
      media: _rows(parsed['media'], _media),
      units: _rows(parsed['units'], _unit),
      progress: _rows(parsed['progress'], _progress),
      activity: _rows(parsed['activity'], _activity),
    );
    return BackupDocument(
      snapshot: snapshot,
      sources: _strings(parsed['sources']),
    );
  }

  /// One line for the restore confirmation, e.g. `12 works · 84 chapters`.
  static String describe(LibrarySnapshot snapshot) {
    return '${snapshot.libraryCount} works · ${snapshot.units.length} units · '
        '${snapshot.progress.length} positions';
  }

  static List<T> _rows<T>(Object? raw, T Function(Map<String, Object?>) parse) {
    if (raw == null) return const [];
    if (raw is! List) throw const BackupException('A backup section is not a list.');
    final result = <T>[];
    for (final row in raw) {
      if (row is! Map<String, Object?>) {
        throw const BackupException('A backup row is not an object.');
      }
      result.add(parse(row));
    }
    return List.unmodifiable(result);
  }

  static Media _media(Map<String, Object?> row) {
    final sourceId = _string(row['sourceId'], 'sourceId');
    final url = _string(row['url'], 'url');
    return Media(
      ref: SourceRef(sourceId, url),
      title: _string(row['title'], 'title'),
      kind: _kind(row['kind']),
      nativeTitle: _optionalString(row['nativeTitle']),
      coverUrl: _optionalString(row['coverUrl']),
      synopsis: _optionalString(row['synopsis']),
      author: _optionalString(row['author']),
      year: row['year'] == null ? null : _int(row['year']),
      status: _status(row['status']),
      genres: _strings(row['genres']),
      memo: _optionalString(row['memo']) ?? '',
      inLibrary: row['inLibrary'] == true,
      favorite: row['favorite'] == true,
      state: _state(row['state']),
      tags: _strings(row['tags']),
      addedAt: _int(row['addedAt']),
      lastOpenedAt: _int(row['lastOpenedAt']),
    );
  }

  static MediaUnit _unit(Map<String, Object?> row) {
    return MediaUnit(
      mediaId: _string(row['mediaId'], 'mediaId'),
      url: _string(row['url'], 'url'),
      number: _number(row['number']),
      title: _string(row['title'], 'title'),
      kind: row['kind'] == UnitKind.episode.name
          ? UnitKind.episode
          : UnitKind.chapter,
      publishedAt: _int(row['publishedAt']),
      pageCount: _int(row['pageCount']),
      memo: _optionalString(row['memo']) ?? '',
    );
  }

  static UnitProgress _progress(Map<String, Object?> row) {
    return UnitProgress(
      unitId: _string(row['unitId'], 'unitId'),
      position: _int(row['position']),
      total: _int(row['total']),
      completed: row['completed'] == true,
      updatedAt: _int(row['updatedAt']),
    );
  }

  static DailyActivity _activity(Map<String, Object?> row) {
    return DailyActivity(
      day: _string(row['day'], 'day'),
      pages: _int(row['pages']),
      minutes: _int(row['minutes']),
      units: _int(row['units']),
    );
  }

  static String _string(Object? raw, String field) {
    if (raw is String && raw.trim().isNotEmpty) return raw;
    throw BackupException('A row is missing "$field".');
  }

  static String? _optionalString(Object? raw) =>
      raw is String && raw.trim().isNotEmpty ? raw : null;

  static int _int(Object? raw) => raw is int ? raw : (raw is num ? raw.toInt() : 0);

  static double _number(Object? raw) =>
      raw is num ? raw.toDouble() : (raw is String ? double.tryParse(raw) ?? 0 : 0);

  static List<String> _strings(Object? raw) {
    if (raw is! List) return const [];
    return raw.whereType<String>().toList(growable: false);
  }

  static MediaKind _kind(Object? raw) {
    for (final kind in MediaKind.values) {
      if (kind.name == raw) return kind;
    }
    return MediaKind.manga;
  }

  static MediaStatus _status(Object? raw) {
    for (final status in MediaStatus.values) {
      if (status.name == raw) return status;
    }
    return MediaStatus.unknown;
  }

  static ReadingState _state(Object? raw) {
    for (final state in ReadingState.values) {
      if (state.name == raw) return state;
    }
    return ReadingState.none;
  }
}

/// A parsed backup: the shelf, plus the packs the shelf was built with.
class BackupDocument {
  const BackupDocument({required this.snapshot, this.sources = const []});

  final LibrarySnapshot snapshot;
  final List<String> sources;

  bool get isEmpty => snapshot.isEmpty && sources.isEmpty;
}

class BackupException implements Exception {
  const BackupException(this.message);

  final String message;

  @override
  String toString() => message;
}
