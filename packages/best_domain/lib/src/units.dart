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
    );
  }

  @override
  String toString() => 'MediaUnit($id, $number)';
}
