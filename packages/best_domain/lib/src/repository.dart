import 'downloads.dart';
import 'library.dart';
import 'media.dart';
import 'progress.dart';
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

  /// Inserts or refreshes a work. A refresh never erases local history.
  Future<void> saveMedia(Media media);

  Future<void> setInLibrary(String mediaId, bool value);

  Future<void> setFavorite(String mediaId, bool value);

  Future<void> saveUnits(Iterable<MediaUnit> units);

  Future<List<MediaUnit>> unitsFor(String mediaId);

  Future<UnitProgress?> progressFor(String unitId);

  /// Merges with the stored progress; see [UnitProgress.merge].
  Future<void> saveProgress(UnitProgress progress);

  Future<List<ContinueEntry>> continueReading({int limit = 6});

  Future<void> removeFromLibrary(String mediaId);

  /// Every download, newest first. The manager owns transitions; the UI only
  /// reads and asks for pause/resume/cancel.
  Future<List<DownloadTask>> downloads();

  Future<DownloadTask?> downloadFor(String unitId);

  Future<void> saveDownload(DownloadTask task);

  Future<void> deleteDownload(String unitId);

  Future<void> close();
}
