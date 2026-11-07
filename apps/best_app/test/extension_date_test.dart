import 'package:best_app/src/extension_host.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeEpochMillis', () {
    const millis = 1754700000000; // 2025-08-09 UTC
    final year = DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true).year;

    test('keeps a Mihon millisecond timestamp', () {
      expect(normalizeEpochMillis(millis), millis);
      expect(
        DateTime.fromMillisecondsSinceEpoch(
          normalizeEpochMillis(millis),
          isUtc: true,
        ).year,
        year,
      );
    });

    test('scales seconds up', () {
      expect(normalizeEpochMillis(millis ~/ 1000), millis);
    });

    test('scales microseconds down', () {
      expect(normalizeEpochMillis(millis * 1000), millis);
    });

    test('recovers the old double-multiplied value', () {
      expect(normalizeEpochMillis(millis * 1000), millis);
      expect(
        DateTime.fromMillisecondsSinceEpoch(
          normalizeEpochMillis(millis * 1000),
          isUtc: true,
        ).year,
        year,
      );
    });

    test('missing and zero timestamps stay unknown', () {
      expect(normalizeEpochMillis(null), 0);
      expect(normalizeEpochMillis(0), 0);
      expect(normalizeEpochMillis(-1), 0);
    });
  });
}
