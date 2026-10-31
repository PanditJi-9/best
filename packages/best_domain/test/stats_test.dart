import 'package:best_domain/best_domain.dart';
import 'package:test/test.dart';

void main() {
  final today = DateTime(2026, 10, 31);

  DailyActivity day(DateTime date, {int pages = 1, int minutes = 0}) {
    return DailyActivity(
      day: ReadingStats.dayKey(date),
      pages: pages,
      minutes: minutes,
    );
  }

  group('streak', () {
    test('counts consecutive days ending today', () {
      final activity = [
        day(today),
        day(today.subtract(const Duration(days: 1))),
        day(today.subtract(const Duration(days: 2))),
      ];
      expect(ReadingStats.streak(activity, today), 3);
    });

    test('survives a day that has not been read yet', () {
      final activity = [
        day(today.subtract(const Duration(days: 1))),
        day(today.subtract(const Duration(days: 2))),
      ];
      expect(ReadingStats.streak(activity, today), 2);
    });

    test('breaks on a missed day', () {
      final activity = [
        day(today),
        day(today.subtract(const Duration(days: 2))),
      ];
      expect(ReadingStats.streak(activity, today), 1);
    });

    test('is zero when the last read was two days ago', () {
      final activity = [day(today.subtract(const Duration(days: 2)))];
      expect(ReadingStats.streak(activity, today), 0);
    });

    test('ignores empty rows', () {
      final activity = [day(today, pages: 0, minutes: 0)];
      expect(ReadingStats.streak(activity, today), 0);
    });
  });

  group('from', () {
    test('always reports seven days, oldest first', () {
      final stats = ReadingStats.from(
        activity: [day(today, pages: 5)],
        works: 2,
        units: 10,
        completedUnits: 4,
        today: today,
      );
      expect(stats.week, hasLength(7));
      expect(stats.week.first.day, ReadingStats.dayKey(today.subtract(const Duration(days: 6))));
      expect(stats.week.last.day, ReadingStats.dayKey(today));
      expect(stats.week.last.pages, 5);
      expect(stats.weekPages, 5);
    });

    test('sums lifetime activity and keeps the peak usable', () {
      final stats = ReadingStats.from(
        activity: [
          day(today, pages: 3),
          day(today.subtract(const Duration(days: 10)), pages: 40),
        ],
        works: 1,
        units: 3,
        completedUnits: 1,
        today: today,
      );
      expect(stats.pages, 43);
      expect(stats.weekPages, 3, reason: 'a day outside the week still counts for life');
      expect(stats.weekPeak, greaterThan(0));
    });

    test('a day outside the week does not break the streak', () {
      final stats = ReadingStats.from(
        activity: [day(today, pages: 1)],
        works: 1,
        units: 1,
        completedUnits: 0,
        today: today,
      );
      expect(stats.streakDays, 1);
    });
  });
}
