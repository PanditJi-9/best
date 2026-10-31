import 'package:best_domain/best_domain.dart';
import 'package:test/test.dart';

void main() {
  group('resume', () {
    const tenMinutes = Duration(minutes: 10);

    test('starts at zero when the saved point is noise', () {
      expect(
        PlaybackProgress.resumeAt(savedSeconds: 0, duration: tenMinutes),
        Duration.zero,
      );
      expect(
        PlaybackProgress.resumeAt(savedSeconds: 2, duration: tenMinutes),
        Duration.zero,
      );
    });

    test('returns a real position inside the video', () {
      expect(
        PlaybackProgress.resumeAt(savedSeconds: 90, duration: tenMinutes),
        const Duration(seconds: 90),
      );
    });

    test('restarts a finished or out-of-range unit', () {
      expect(
        PlaybackProgress.resumeAt(savedSeconds: 599, duration: tenMinutes),
        Duration.zero,
      );
      expect(
        PlaybackProgress.resumeAt(savedSeconds: 900, duration: tenMinutes),
        Duration.zero,
      );
    });

    test('keeps a saved point when the duration is unknown', () {
      expect(
        PlaybackProgress.resumeAt(savedSeconds: 45, duration: Duration.zero),
        const Duration(seconds: 45),
      );
    });
  });

  group('completion', () {
    const tenMinutes = Duration(minutes: 10);

    test('the ending window counts as watched', () {
      expect(
        PlaybackProgress.isFinished(
          position: tenMinutes - const Duration(seconds: 4),
          duration: tenMinutes,
        ),
        isTrue,
      );
    });

    test('95 percent counts as watched', () {
      expect(
        PlaybackProgress.isFinished(
          position: const Duration(seconds: 570),
          duration: tenMinutes,
        ),
        isTrue,
      );
    });

    test('halfway is not finished', () {
      expect(
        PlaybackProgress.isFinished(
          position: const Duration(minutes: 5),
          duration: tenMinutes,
        ),
        isFalse,
      );
    });

    test('an unknown duration is never finished', () {
      expect(
        PlaybackProgress.isFinished(
          position: const Duration(minutes: 5),
          duration: Duration.zero,
        ),
        isFalse,
      );
    });
  });

  group('persistence', () {
    const tenMinutes = Duration(minutes: 10);

    test('stores seconds, the runtime and the completion flag', () {
      final row = PlaybackProgress.toProgress(
        unitId: 'u',
        position: const Duration(minutes: 3, seconds: 20),
        duration: tenMinutes,
        updatedAt: 42,
      );

      expect(row, isNotNull);
      expect(row!.unitId, 'u');
      expect(row.position, 200);
      expect(row.total, 600);
      expect(row.completed, isFalse);
      expect(row.updatedAt, 42);
      expect(row.fraction, closeTo(1 / 3, 0.001));
    });

    test('clamps a position past the end and marks it complete', () {
      final row = PlaybackProgress.toProgress(
        unitId: 'u',
        position: const Duration(minutes: 11),
        duration: tenMinutes,
        updatedAt: 43,
      );

      expect(row!.position, 600);
      expect(row.completed, isTrue);
      expect(row.fraction, 1);
    });

    test('returns nothing before the duration is known', () {
      expect(
        PlaybackProgress.toProgress(
          unitId: 'u',
          position: const Duration(seconds: 10),
          duration: Duration.zero,
          updatedAt: 44,
        ),
        isNull,
      );
    });
  });
}
