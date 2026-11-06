import 'progress.dart';

/// The rules that turn a video position into library progress.
///
/// The player works in [Duration]s, the database stores whole seconds, and the
/// shelf shows a fraction. Keeping the conversion in one place means resume,
/// completion and "continue watching" cannot drift apart.
abstract final class PlaybackProgress {
  /// Below this, starting at zero is calmer than seeking a few seconds in.
  static const int minimumResumeSeconds = 3;

  /// A video this close to its end counts as watched, so the next episode is
  /// offered instead of a resume point nobody wants.
  static const int endingWindowSeconds = 5;

  /// `95%` of the runtime is the second completion rule. A long episode can
  /// lose its last seconds to a source that ends early; a short clip can be
  /// watched to the end without crossing the fixed window.
  static bool isFinished({
    required Duration position,
    required Duration duration,
  }) {
    if (duration <= Duration.zero) return false;
    if (position >= duration) return true;
    if (duration - position <= const Duration(seconds: endingWindowSeconds)) {
      return true;
    }
    return position.inMilliseconds >= duration.inMilliseconds * 0.95;
  }

  /// Where playback should begin.
  ///
  /// A finished unit restarts at zero: replaying is a deliberate act, not a
  /// resume. A position beyond the reported duration is treated the same way,
  /// because seeking past the end would leave a black screen.
  static Duration resumeAt({
    required int savedSeconds,
    required Duration duration,
  }) {
    if (savedSeconds < minimumResumeSeconds) return Duration.zero;
    final saved = Duration(seconds: savedSeconds);
    if (duration <= Duration.zero) return saved;
    if (saved >= duration) return Duration.zero;
    if (isFinished(position: saved, duration: duration)) return Duration.zero;
    return saved;
  }

  /// The row to persist, or `null` before the player knows its duration.
  static UnitProgress? toProgress({
    required String unitId,
    required Duration position,
    required Duration duration,
    required int updatedAt,
    bool completed = false,
  }) {
    if (duration <= Duration.zero) return null;
    final seconds = position.inSeconds.clamp(0, duration.inSeconds);
    return UnitProgress(
      unitId: unitId,
      position: seconds,
      total: duration.inSeconds,
      completed:
          completed || isFinished(position: position, duration: duration),
      started: true,
      updatedAt: updatedAt,
    );
  }
}
