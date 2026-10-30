/// One chapter or episode being stored on the device.
///
/// A download is a first-class state machine, not a spinner: it can be queued,
/// paused, resumed, failed and retried, and every transition survives a restart
/// because the row is written before the next page is fetched.
enum DownloadStatus { queued, running, paused, done, failed }

class DownloadTask {
  const DownloadTask({
    required this.unitId,
    required this.mediaId,
    required this.sourceId,
    required this.mediaUrl,
    required this.unitUrl,
    required this.mediaTitle,
    required this.unitTitle,
    required this.total,
    this.completed = 0,
    this.bytes = 0,
    this.status = DownloadStatus.queued,
    this.error,
    this.directory,
    this.updatedAt = 0,
  });

  final String unitId;
  final String mediaId;
  final String sourceId;

  /// The source addresses, kept so a finished download can open its reader
  /// without re-parsing an id or asking the catalogue.
  final String mediaUrl;
  final String unitUrl;

  /// Titles are copied, not joined: a download must stay readable after the
  /// catalogue row is refreshed or the work leaves the library.
  final String mediaTitle;
  final String unitTitle;

  /// Pages known so far. The manager replaces it with the real count as soon as
  /// the source answers, which is why it is not `final` in the database sense.
  final int total;
  final int completed;

  /// Bytes written for this unit so far. Storage accounting and the Downloads
  /// screen read this; it is not derived from the page count because pages
  /// differ in size and a resumed download must not double-count.
  final int bytes;

  final DownloadStatus status;

  /// Human-readable failure. Cleared on resume.
  final String? error;

  /// Absolute directory once the first page is written; null before that.
  final String? directory;
  final int updatedAt;

  bool get isActive =>
      status == DownloadStatus.queued || status == DownloadStatus.running;

  bool get isFinished => status == DownloadStatus.done;

  bool get isFailed => status == DownloadStatus.failed;

  bool get isPaused => status == DownloadStatus.paused;

  double get progress {
    if (total <= 0) return 0;
    return (completed / total).clamp(0, 1);
  }

  DownloadTask copyWith({
    int? total,
    int? completed,
    int? bytes,
    DownloadStatus? status,
    String? error,
    bool clearError = false,
    String? directory,
    int? updatedAt,
  }) {
    return DownloadTask(
      unitId: unitId,
      mediaId: mediaId,
      sourceId: sourceId,
      mediaUrl: mediaUrl,
      unitUrl: unitUrl,
      mediaTitle: mediaTitle,
      unitTitle: unitTitle,
      total: total ?? this.total,
      completed: completed ?? this.completed,
      bytes: bytes ?? this.bytes,
      status: status ?? this.status,
      error: clearError ? null : (error ?? this.error),
      directory: directory ?? this.directory,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
