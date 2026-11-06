import 'reader_preferences.dart';

/// Portable reading choices, never device credentials, protection settings or
/// paths to downloaded files. Merge is additive: marks are unioned and local
/// work preferences take precedence over an imported copy.
class ReaderStateSnapshot {
  const ReaderStateSnapshot({
    this.defaults,
    this.profiles = const {},
    this.bookmarks = const {},
  });

  final ReaderPreferences? defaults;
  final Map<String, ReaderPreferences> profiles;
  final Map<String, List<int>> bookmarks;

  bool get isEmpty => defaults == null && profiles.isEmpty && bookmarks.isEmpty;
  int get bookmarkCount =>
      bookmarks.values.fold(0, (sum, pages) => sum + pages.length);

  ReaderStateSnapshot merge(ReaderStateSnapshot imported) {
    final marks = <String, List<int>>{};
    for (final id in {...bookmarks.keys, ...imported.bookmarks.keys}) {
      final pages = <int>{
        ...bookmarks[id] ?? const [],
        ...imported.bookmarks[id] ?? const [],
      }.toList()
        ..sort();
      if (pages.isNotEmpty) marks[id] = List.unmodifiable(pages);
    }
    return ReaderStateSnapshot(
      defaults: defaults ?? imported.defaults,
      profiles: Map.unmodifiable({...imported.profiles, ...profiles}),
      bookmarks: Map.unmodifiable(marks),
    );
  }

  Map<String, Object> toJson() => {
        if (defaults != null) 'defaults': defaults!.toJson(),
        'profiles': profiles
            .map((id, preferences) => MapEntry(id, preferences.toJson())),
        'bookmarks': bookmarks,
      };

  factory ReaderStateSnapshot.fromJson(Object? raw) {
    if (raw == null) return const ReaderStateSnapshot();
    if (raw is! Map<String, Object?>) {
      throw const FormatException('Reader preferences must be an object.');
    }
    final profiles = <String, ReaderPreferences>{};
    final marks = <String, List<int>>{};
    final defaults = raw['defaults'];
    if (defaults != null && defaults is! Map<String, Object?>) {
      throw const FormatException('Reader defaults must be an object.');
    }
    final storedProfiles = raw['profiles'];
    if (storedProfiles != null) {
      if (storedProfiles is! Map<String, Object?>) {
        throw const FormatException('Work preferences must be an object.');
      }
      for (final entry in storedProfiles.entries) {
        final value = entry.value;
        if (entry.key.isEmpty || value is! Map<String, Object?>) {
          throw const FormatException('A work preference is invalid.');
        }
        profiles[entry.key] = ReaderPreferences.fromJson(value);
      }
    }
    final storedMarks = raw['bookmarks'];
    if (storedMarks != null) {
      if (storedMarks is! Map<String, Object?>) {
        throw const FormatException('Bookmarks must be an object.');
      }
      for (final entry in storedMarks.entries) {
        final value = entry.value;
        if (entry.key.isEmpty || value is! List<Object?>) {
          throw const FormatException('A bookmark entry is invalid.');
        }
        final pages = <int>{};
        for (final page in value) {
          if (page is! int || page < 0) {
            throw const FormatException(
                'A bookmark page must be a non-negative integer.');
          }
          pages.add(page);
        }
        final sorted = pages.toList()..sort();
        if (sorted.isNotEmpty) marks[entry.key] = List.unmodifiable(sorted);
      }
    }
    return ReaderStateSnapshot(
      defaults: defaults is Map<String, Object?>
          ? ReaderPreferences.fromJson(defaults)
          : null,
      profiles: Map.unmodifiable(profiles),
      bookmarks: Map.unmodifiable(marks),
    );
  }
}
