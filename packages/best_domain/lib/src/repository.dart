import 'downloads.dart';
import 'library.dart';
import 'media.dart';
import 'ocr/ocr_models.dart';
import 'progress.dart';
import 'stats.dart';
import 'units.dart';

/// The only storage contract the UI knows about.
///
/// Implementations may be SQLite on a phone, IndexedDB on the web, or an
/// in-memory fake in a test. Nothing above this line knows which one is in use.
abstract interface class LibraryRepository {
  /// Emits after every successful write. The UI re-reads its current query
  /// instead of trying to patch a list by hand.
  Stream<void> get changes;

  /// Shelf rows, filtered and sorted by [query]. A null query means the default
  /// (everything, most recently read first).
  Future<List<LibraryEntry>> library([LibraryQuery? query]);

  Future<Media?> mediaById(String id);

  Future<List<Media>> recent({int limit = 20});

  /// Takes a work off the recently opened list. Its progress and shelf stay.
  Future<void> forgetOpened(String mediaId);

  /// Inserts or refreshes a work. A refresh never erases local history.
  Future<void> saveMedia(Media media);

  Future<void> setInLibrary(String mediaId, bool value);

  Future<void> setFavorite(String mediaId, bool value);

  /// The person's plan for a work: reading, planned or paused.
  Future<void> setReadingState(String mediaId, ReadingState state);

  /// Replaces the work's own lists. Order is the person's, so it is kept.
  Future<void> setTags(String mediaId, List<String> tags);

  /// Every work the catalogue knows, not only the shelf. A backup needs the
  /// works a reader opened but never added.
  Future<List<Media>> allMedia();

  /// Every unit of every work, for the same reason.
  Future<List<MediaUnit>> allUnits();

  Future<List<UnitProgress>> allProgress();

  /// Local activity, oldest day first.
  Future<List<DailyActivity>> activity({int days = 400});

  /// Adds to today's row. Never replaces: two readers' days sum.
  Future<void> recordActivity({int pages = 0, int minutes = 0, int units = 0});

  /// Merges imported days into the local log.
  ///
  /// A day is a total, not a delta, so the merge takes the larger number per
  /// field: restoring the same backup twice changes nothing, and restoring an
  /// older backup cannot shrink a day.
  Future<void> mergeActivity(Iterable<DailyActivity> days);

  Future<void> saveUnits(Iterable<MediaUnit> units);

  Future<List<MediaUnit>> unitsFor(String mediaId);

  Future<UnitProgress?> progressFor(String unitId);

  /// Merges with the stored progress; see [UnitProgress.merge].
  Future<void> saveProgress(UnitProgress progress);

  /// The newest started unit per saved work, newest work first. The limit
  /// counts works, so many chapters from one work cannot crowd out another.
  Future<List<ContinueEntry>> continueReading({int limit = 6});

  Future<void> removeFromLibrary(String mediaId);

  /// Moves a work to another source without losing the person's place.
  ///
  /// [target] is the work on the new source; its units must already be stored.
  /// [carriedProgress] are positions translated onto the target's unit ids (see
  /// `MigrationPlan.carryProgress`). The old row, its downloads and its history
  /// are kept: only its shelf membership is cleared when
  /// [removeOldFromLibrary] is true, so a migration can never destroy data.
  Future<void> migrateMedia({
    required String fromMediaId,
    required Media target,
    required List<UnitProgress> carriedProgress,
    bool removeOldFromLibrary = true,
  });

  /// Every download, newest first. The manager owns transitions; the UI only
  /// reads and asks for pause/resume/cancel.
  Future<List<DownloadTask>> downloads();

  Future<DownloadTask?> downloadFor(String unitId);

  Future<void> saveDownload(DownloadTask task);

  Future<void> deleteDownload(String unitId);

  /// Cached OCR and translation results for a chapter page.
  Future<PageOcrResult?> getPageOcr(String unitId, int pageIndex);

  Future<void> savePageOcr(String unitId, PageOcrResult result);

  Future<void> close();
}
