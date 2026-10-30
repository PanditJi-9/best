import 'ids.dart';

/// The shape of a work. A single library holds all of them; the kind only
/// changes which verbs the UI uses (read, watch) and which player opens.
enum MediaKind {
  manga,
  manhwa,
  manhua,
  webtoon,
  anime,
  drama,
  film;

  bool get isReading => switch (this) {
        MediaKind.manga ||
        MediaKind.manhwa ||
        MediaKind.manhua ||
        MediaKind.webtoon =>
          true,
        _ => false,
      };

  bool get isWatching => !isReading;

  /// Arabic and English labels live in the presentation layer; this is the
  /// stable key a translation file is allowed to depend on.
  String get key => name;
}

enum MediaStatus { ongoing, completed, hiatus, cancelled, unknown }

/// Where a work came from. `sourceId` is stable across installs; `url` is the
/// source's own key and is never shown to a person.
class SourceRef {
  const SourceRef(this.sourceId, this.url);

  final String sourceId;
  final String url;

  @override
  bool operator ==(Object other) =>
      other is SourceRef && other.sourceId == sourceId && other.url == url;

  @override
  int get hashCode => Object.hash(sourceId, url);

  @override
  String toString() => '$sourceId($url)';
}

/// A work in the catalogue, independent of how it is read or watched.
class Media {
  const Media({
    required this.ref,
    required this.title,
    required this.kind,
    this.nativeTitle,
    this.coverUrl,
    this.synopsis,
    this.author,
    this.year,
    this.status = MediaStatus.unknown,
    this.genres = const [],
    this.inLibrary = false,
    this.favorite = false,
    this.addedAt = 0,
    this.lastOpenedAt = 0,
  });

  final SourceRef ref;
  final String title;
  final MediaKind kind;
  final String? nativeTitle;
  final String? coverUrl;
  final String? synopsis;
  final String? author;
  final int? year;
  final MediaStatus status;
  final List<String> genres;
  final bool inLibrary;
  final bool favorite;

  /// Epoch milliseconds. `0` means "unknown", never "1970".
  final int addedAt;
  final int lastOpenedAt;

  String get id => mediaIdOf(ref.sourceId, ref.url);

  String get displayTitle =>
      title.trim().isNotEmpty ? title : (nativeTitle ?? ref.url);

  Media copyWith({
    String? title,
    String? nativeTitle,
    String? coverUrl,
    String? synopsis,
    String? author,
    int? year,
    MediaStatus? status,
    List<String>? genres,
    bool? inLibrary,
    bool? favorite,
    int? addedAt,
    int? lastOpenedAt,
  }) {
    return Media(
      ref: ref,
      title: title ?? this.title,
      kind: kind,
      nativeTitle: nativeTitle ?? this.nativeTitle,
      coverUrl: coverUrl ?? this.coverUrl,
      synopsis: synopsis ?? this.synopsis,
      author: author ?? this.author,
      year: year ?? this.year,
      status: status ?? this.status,
      genres: genres ?? this.genres,
      inLibrary: inLibrary ?? this.inLibrary,
      favorite: favorite ?? this.favorite,
      addedAt: addedAt ?? this.addedAt,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
    );
  }

  @override
  String toString() => 'Media($id, $title)';
}
