import 'ids.dart';

enum UnitKind { chapter, episode }

/// One readable or watchable unit: a chapter or an episode.
///
/// A unit keeps the source's own `url` because that is the only key a source
/// understands, and a stable [id] because progress must survive a source that
/// renames its labels.
class MediaUnit {
  const MediaUnit({
    required this.mediaId,
    required this.url,
    required this.number,
    required this.title,
    required this.kind,
    this.publishedAt = 0,
    this.pageCount = 0,
    this.memo = '',
    this.firstSeenAt = 0,
  });

  final String mediaId;
  final String url;

  /// Source order. Fractional values are legal (`12.5`).
  final double number;
  final String title;
  final UnitKind kind;

  /// Epoch milliseconds, `0` when the source does not report one.
  final int publishedAt;

  /// Pages for a chapter, `0` when unknown. Unused for episodes.
  final int pageCount;

  /// Opaque JSON the source attached to this unit (extensions-lib `memo`).
  ///
  /// Madara-derived extensions keep the manga path here and refuse to build a
  /// page list without it, so the reader has to send it back when it asks for
  /// pages. Stored as the source wrote it; Best never interprets the contents.
  final String memo;

  /// When this unit first appeared on a work that was already on the shelf.
  /// `0` means "not an update": the unit was part of the first chapter list,
  /// so adding a work never floods the updates feed with its back catalogue.
  final int firstSeenAt;

  String get id => unitIdOf(mediaId, url);

  String get displayTitle => title.trim().isNotEmpty ? title : _fallbackTitle;

  String get _fallbackTitle {
    final rounded = number == number.roundToDouble()
        ? number.toInt().toString()
        : number.toString();
    return kind == UnitKind.chapter ? 'Chapter $rounded' : 'Episode $rounded';
  }

  MediaUnit copyWith({
    double? number,
    String? title,
    int? pageCount,
    int? publishedAt,
    String? memo,
    int? firstSeenAt,
  }) {
    return MediaUnit(
      mediaId: mediaId,
      url: url,
      number: number ?? this.number,
      title: title ?? this.title,
      kind: kind,
      publishedAt: publishedAt ?? this.publishedAt,
      pageCount: pageCount ?? this.pageCount,
      memo: memo ?? this.memo,
      firstSeenAt: firstSeenAt ?? this.firstSeenAt,
    );
  }

  @override
  String toString() => 'MediaUnit($id, $number)';
}
