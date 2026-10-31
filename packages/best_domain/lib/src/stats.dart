/// Local reading activity, one row per day.
///
/// It is deliberately tiny and boring: pages, minutes and finished units for a
/// calendar day in the device's own timezone. Anything richer (a per-work log)
/// costs storage and privacy for numbers nobody reads; a streak and a week of
/// bars are what a person actually looks at.
class DailyActivity {
  const DailyActivity({
    required this.day,
    this.pages = 0,
    this.minutes = 0,
    this.units = 0,
  });

  /// Local calendar day as `yyyy-MM-dd`. A string sorts and compares correctly
  /// in SQLite without a date type, and survives a timezone change as "the day
  /// it felt like at the time".
  final String day;
  final int pages;
  final int minutes;
  final int units;

  bool get isEmpty => pages == 0 && minutes == 0 && units == 0;

  DailyActivity plus({int pages = 0, int minutes = 0, int units = 0}) {
    return DailyActivity(
      day: day,
      pages: this.pages + pages,
      minutes: this.minutes + minutes,
      units: this.units + units,
    );
  }

  @override
  String toString() => 'DailyActivity($day, pages=$pages, min=$minutes)';
}

/// The numbers on the profile card and the statistics screen.
class ReadingStats {
  const ReadingStats({
    this.works = 0,
    this.units = 0,
    this.completedUnits = 0,
    this.pages = 0,
    this.minutes = 0,
    this.streakDays = 0,
    this.week = const [],
  });

  /// Works on the shelf.
  final int works;

  /// Units known for those works.
  final int units;

  /// Units marked finished.
  final int completedUnits;

  /// Lifetime page turns, from local activity only.
  final int pages;

  /// Lifetime minutes of video, from local activity only.
  final int minutes;

  /// Consecutive days with any activity, ending today or yesterday.
  final int streakDays;

  /// The last seven days, oldest first. Always seven entries when built by
  /// [from], so a chart can draw empty days without special cases.
  final List<DailyActivity> week;

  int get weekPages => week.fold(0, (sum, day) => sum + day.pages);

  int get weekMinutes => week.fold(0, (sum, day) => sum + day.minutes);

  /// The busiest day of the week, used as the chart's scale. Never `0`, so a
  /// caller can divide by it.
  int get weekPeak {
    var peak = 0;
    for (final day in week) {
      final load = day.pages + day.minutes;
      if (load > peak) peak = load;
    }
    return peak == 0 ? 1 : peak;
  }

  /// Builds the derived numbers from a day log.
  ///
  /// [today] is injected rather than read from the clock so the streak rule is
  /// testable. A day with nothing on it never counts; today without activity
  /// does not break a streak that ended yesterday, because a person who read
  /// last night has not lost anything at breakfast.
  static ReadingStats from({
    required Iterable<DailyActivity> activity,
    required int works,
    required int units,
    required int completedUnits,
    required DateTime today,
  }) {
    final byDay = <String, DailyActivity>{};
    var pages = 0;
    var minutes = 0;
    for (final day in activity) {
      pages += day.pages;
      minutes += day.minutes;
      final existing = byDay[day.day];
      byDay[day.day] = existing == null
          ? day
          : existing.plus(
              pages: day.pages,
              minutes: day.minutes,
              units: day.units,
            );
    }

    final week = <DailyActivity>[];
    for (var offset = 6; offset >= 0; offset--) {
      final date = today.subtract(Duration(days: offset));
      final key = dayKey(date);
      week.add(byDay[key] ?? DailyActivity(day: key));
    }

    return ReadingStats(
      works: works,
      units: units,
      completedUnits: completedUnits,
      pages: pages,
      minutes: minutes,
      streakDays: streak(activity, today),
      week: List.unmodifiable(week),
    );
  }

  /// Consecutive active days ending today, or yesterday when today is empty.
  static int streak(Iterable<DailyActivity> activity, DateTime today) {
    final active = {
      for (final day in activity)
        if (!day.isEmpty) day.day,
    };
    if (active.isEmpty) return 0;

    var cursor = today;
    if (!active.contains(dayKey(cursor))) {
      cursor = cursor.subtract(const Duration(days: 1));
      if (!active.contains(dayKey(cursor))) return 0;
    }

    var streak = 0;
    while (active.contains(dayKey(cursor))) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  /// `yyyy-MM-dd` for a local date.
  static String dayKey(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
