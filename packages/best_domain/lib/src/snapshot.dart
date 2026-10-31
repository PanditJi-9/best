import 'media.dart';
import 'repository.dart';
import 'progress.dart';
import 'stats.dart';
import 'units.dart';

/// Everything a backup needs, and nothing a backup must not carry.
///
/// Download rows are deliberately absent: the files they point at are not in
/// the document, so restoring them would produce rows that claim a chapter is
/// offline while the reader has nothing to show. A new phone re-downloads.
class LibrarySnapshot {
  const LibrarySnapshot({
    required this.media,
    required this.units,
    required this.progress,
    this.activity = const [],
    this.exportedAt = 0,
  });

  final List<Media> media;
  final List<MediaUnit> units;
  final List<UnitProgress> progress;
  final List<DailyActivity> activity;

  /// Epoch milliseconds; `0` when the document did not say.
  final int exportedAt;

  bool get isEmpty => media.isEmpty && progress.isEmpty;

  int get libraryCount => media.where((work) => work.inLibrary).length;
}

/// What a restore actually changed.
class RestoreReport {
  const RestoreReport({
    this.media = 0,
    this.units = 0,
    this.progress = 0,
  });

  final int media;
  final int units;
  final int progress;

  int get total => media + units + progress;

  @override
  String toString() =>
      'RestoreReport(media=$media, units=$units, progress=$progress)';
}

/// Reads everything a backup needs in one pass.
Future<LibrarySnapshot> snapshotOf(LibraryRepository repository) async {
  final media = await repository.allMedia();
  final units = await repository.allUnits();
  final progress = await repository.allProgress();
  final activity = await repository.activity();
  return LibrarySnapshot(
    media: media,
    units: units,
    progress: progress,
    activity: activity,
    exportedAt: DateTime.now().millisecondsSinceEpoch,
  );
}

/// Restores a snapshot through the public repository surface.
/// Every write goes through the same merge rules a normal save uses, so a
/// restore can only add: a stale backup never erases a newer page position or a
/// favorite, and activity days are summed rather than replaced.
Future<RestoreReport> restoreInto(
  LibraryRepository repository,
  LibrarySnapshot snapshot,
) async {
  var media = 0;
  var units = 0;
  var progress = 0;

  for (final work in snapshot.media) {
    await repository.saveMedia(work);
    media++;
  }
  for (final unit in snapshot.units) {
    await repository.saveUnits([unit]);
    units++;
  }
  for (final row in snapshot.progress) {
    await repository.saveProgress(row);
    progress++;
  }
  if (snapshot.activity.isNotEmpty) {
    await repository.mergeActivity(snapshot.activity);
  }

  return RestoreReport(media: media, units: units, progress: progress);
}
