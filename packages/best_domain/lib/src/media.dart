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

/// Where a work sits in the person's own plan.
///
/// This is intent, not progress: finishing the last chapter does not flip it to
/// [none], because a shelf filter that moves works around on its own is a shelf
/// nobody can trust. `none` means "not sorted yet", which is the honest default
/// for something opened from Browse.
enum ReadingState { none, reading, planned, paused }

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
    this.rating,
    this.memo = '',
    this.inLibrary = false,
    this.favorite = false,
    this.state = ReadingState.none,
    this.tags = const [],
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

  /// The source's own score for this work, on a 0–10 scale.
  ///
  /// Only sources that publish a score fill it (MangaDex does). It is never
  /// invented: `null` means "this source does not rate works".
  final double? rating;

  /// Opaque JSON the source attached to this work (extensions-lib `memo`).
  ///
  /// Madara-derived extensions keep the canonical manga path here and build
  /// chapter URLs from it, so it has to survive from the catalogue card to the
  /// chapter list. Empty means "the source said nothing".
  final String memo;

  final bool inLibrary;
  final bool favorite;

  /// The person's own plan for this work.
  final ReadingState state;

  /// Free-form lists. A "list" is a tag with a nicer name: one storage shape,
  /// one editor, and a work can sit in as many as the person wants.
  final List<String> tags;

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
    double? rating,
    String? memo,
    bool? inLibrary,
    bool? favorite,
    ReadingState? state,
    List<String>? tags,
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
      rating: rating ?? this.rating,
      memo: memo ?? this.memo,
      inLibrary: inLibrary ?? this.inLibrary,
      favorite: favorite ?? this.favorite,
      state: state ?? this.state,
      tags: tags ?? this.tags,
      addedAt: addedAt ?? this.addedAt,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
    );
  }

  @override
  String toString() => 'Media($id, $title)';
}
