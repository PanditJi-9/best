import 'dart:async';
import 'dart:io';

import 'package:best_domain/best_domain.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'integrity.dart';
import 'local_pages.dart';

/// A failure worth showing under a download row, without a stack trace.
class DownloadException implements Exception {
  const DownloadException(this.message);

  final String message;

  static const storedPagesChanged =
      'Stored pages are missing, empty or changed.';
  static const sourceIncomplete =
      'The source returned fewer pages than the stored chapter.';
  static const sourceMissing = 'The source for this download is not installed.';
  static const countUnknown = 'The expected page count is unknown.';
  static const removedMessage = 'This download was removed.';

  @override
  String toString() => message;
}

/// Runs the offline queue: one chapter at a time, one page at a time.
///
/// Every transition is written through [LibraryRepository] before the next
/// request starts, so closing the app mid-chapter loses at most the page that
/// was in flight. The manager has no Flutter dependency: a plain Dart test can
/// drive the whole queue against a mock HTTP client and a temp directory.
class DownloadManager {
  DownloadManager({
    required LibraryRepository repository,
    required SourceRegistry registry,
    required http.Client client,
    required Directory root,
  })  : _repository = repository,
        _registry = registry,
        _client = client,
        _root = root;

  final LibraryRepository _repository;
  final SourceRegistry _registry;
  final http.Client _client;
  final Directory _root;

  Future<void>? _active;
  bool _disposed = false;
  bool _needsDrain = false;

  /// Includes an in-flight request finishing after a pause. Android must keep
  /// the engine alive until that request has committed or stopped safely.
  bool get isDraining => _active != null;
  void Function()? onDrainChanged;

  void _signalDrain() {
    try {
      onDrainChanged?.call();
    } catch (_) {
      // Display/lifetime observers cannot break the queue's writer.
    }
  }

  /// The app's network rule (for example "Wi-Fi only"). The queue asks before
  /// starting a unit, so a metered connection pauses instead of burning data;
  /// pages already in flight finish rather than leaving a half-written chapter.
  bool Function() mayDownload = () => true;

  /// The app's storage cap in bytes, `0` for none. Checked after a unit
  /// finishes, so the offline store never grows past the limit a person set.
  int Function() storageCap = () => 0;

  /// How many chapters may fetch pages at once. One is the polite default; a
  /// person who chooses more accepts the extra load on the source.
  int Function() maxConcurrent = () => 1;

  /// Android may need to warm its installed extension catalogue before a cold
  /// worker can resolve a saved source. No second manager or writer is created.
  Future<void> Function() prepareSources = () async {};

  /// Mutations and file commits for one chapter are serialized. A generation
  /// changes immediately on cancellation, before waiting for IO: an old request
  /// cannot recreate a deleted row, or delete/write a newly requeued chapter.
  final Map<String, Future<void>> _locks = {};
  final Map<String, int> _generations = {};

  int _generation(String unitId) => _generations[unitId] ?? 0;

  bool _isCurrent(String unitId, int generation) =>
      !_disposed && _generation(unitId) == generation;

  Future<T> _exclusive<T>(String unitId, Future<T> Function() action) async {
    final previous = _locks[unitId];
    final release = Completer<void>();
    _locks[unitId] = release.future;
    try {
      if (previous != null) await previous;
      return await action();
    } finally {
      release.complete();
      if (identical(_locks[unitId], release.future)) {
        unawaited(
            _locks.remove(unitId)); // Already completed; release this key.
      }
    }
  }

  /// Called once per app launch: anything the process left `running` becomes
  /// queued again, and the queue starts where it stopped.
  Future<void> restore() async {
    final tasks = await _repository.downloads();
    final now = _now();
    for (final task in tasks) {
      final generation = _generation(task.unitId);
      await _exclusive<void>(task.unitId, () async {
        if (!_isCurrent(task.unitId, generation)) return;
        final current = await _repository.downloadFor(task.unitId);
        if (current == null) return;
        if (current.isFinished &&
            current.bytes == 0 &&
            current.directory != null) {
          final bytes = await directoryBytes(current.directory!);
          if (_isCurrent(task.unitId, generation) && bytes > 0) {
            await _repository.saveDownload(current.copyWith(bytes: bytes));
          }
        } else if (current.isActive) {
          await _repository.saveDownload(
            current.copyWith(status: DownloadStatus.queued, updatedAt: now),
          );
        }
      });
    }
    await pump();
  }

  /// Queues a unit and returns immediately. The row is written before the first
  /// request, so the Downloads screen can show it without waiting for bytes.
  Future<DownloadTask> enqueue(Media media, MediaUnit unit) async {
    final generation = _generation(unit.id);
    final task = await _exclusive<DownloadTask>(unit.id, () async {
      if (!_isCurrent(unit.id, generation)) {
        throw const DownloadException('This download was removed.');
      }
      var existing = await _repository.downloadFor(unit.id);
      if (existing != null && existing.isActive) return existing;
      if (existing != null && existing.isFinished) {
        final check = await inspectStoredDownload(
          existing,
          verifyHashes: false,
          shouldContinue: () => _isCurrent(unit.id, generation),
        );
        if (check.isComplete) return existing;
        existing = existing.copyWith(completed: check.available);
      }
      if (!_isCurrent(unit.id, generation)) {
        throw const DownloadException('This download was removed.');
      }
      final task = DownloadTask(
        unitId: unit.id,
        mediaId: media.id,
        sourceId: media.ref.sourceId,
        mediaUrl: media.ref.url,
        unitUrl: unit.url,
        mediaTitle: media.displayTitle,
        unitTitle: unit.displayTitle,
        total: existing?.directory != null
            ? existing!.total
            : (unit.pageCount > 0 ? unit.pageCount : (existing?.total ?? 0)),
        completed: existing?.completed ?? 0,
        bytes: existing?.bytes ?? 0,
        status: DownloadStatus.queued,
        directory: existing?.directory,
        updatedAt: _now(),
      );
      await _repository.saveDownload(task);
      return task;
    });
    if (task.isActive) _schedule();
    return task;
  }

  Future<void> pause(String unitId) async {
    final generation = _generation(unitId);
    await _exclusive<void>(unitId, () async {
      if (!_isCurrent(unitId, generation)) return;
      final task = await _repository.downloadFor(unitId);
      if (task == null || task.isFinished || task.isPaused) return;
      await _repository.saveDownload(
        task.copyWith(status: DownloadStatus.paused, updatedAt: _now()),
      );
    });
  }

  Future<void> resume(String unitId) async {
    final generation = _generation(unitId);
    final queued = await _exclusive<bool>(unitId, () async {
      if (!_isCurrent(unitId, generation)) return false;
      final task = await _repository.downloadFor(unitId);
      if (task == null || task.isFinished || task.isActive) return false;
      await _repository.saveDownload(task.copyWith(
        status: DownloadStatus.queued,
        clearError: true,
        updatedAt: _now(),
      ));
      return true;
    });
    if (queued) _schedule();
  }

  Future<void> retry(String unitId) => resume(unitId);

  Future<DownloadIntegrityReport> checkStored(String unitId) async {
    final generation = _generation(unitId);
    return _exclusive<DownloadIntegrityReport>(unitId, () async {
      final task = await _repository.downloadFor(unitId);
      if (task == null || !_isCurrent(unitId, generation)) {
        throw const DownloadException('This download was removed.');
      }
      final report = await inspectStoredDownload(
        task,
        shouldContinue: () => _isCurrent(unitId, generation),
      );
      if (!_isCurrent(unitId, generation)) {
        throw const DownloadException('This download was removed.');
      }
      if (!report.busy && task.isFinished && !report.isComplete) {
        final bytes =
            task.directory == null ? 0 : await directoryBytes(task.directory!);
        if (_isCurrent(unitId, generation)) {
          await _repository.saveDownload(task.copyWith(
            status: DownloadStatus.failed,
            error: report.total <= 0
                ? DownloadException.countUnknown
                : DownloadException.storedPagesChanged,
            completed: report.available,
            bytes: bytes,
            updatedAt: _now(),
          ));
        }
      }
      if (!_isCurrent(unitId, generation)) {
        throw const DownloadException('This download was removed.');
      }
      return report;
    });
  }

  /// A repair queues the existing directory. Good pages stay; only absent,
  /// empty or checksum-mismatched pages are fetched again. Network/storage
  /// policy is the same as any user-initiated download.
  Future<DownloadIntegrityReport> repair(String unitId) async {
    final generation = _generation(unitId);
    var queued = false;
    final report = await _exclusive<DownloadIntegrityReport>(unitId, () async {
      final task = await _repository.downloadFor(unitId);
      if (task == null || !_isCurrent(unitId, generation)) {
        throw const DownloadException('This download was removed.');
      }
      final report = await inspectStoredDownload(
        task,
        shouldContinue: () => _isCurrent(unitId, generation),
      );
      if (!_isCurrent(unitId, generation)) {
        throw const DownloadException('This download was removed.');
      }
      if (report.busy || (report.isComplete && task.isFinished)) return report;
      if (!report.isComplete && _registry.byId(task.sourceId) == null) {
        throw SourceNotInstalled(task.sourceId);
      }
      final bytes =
          task.directory == null ? 0 : await directoryBytes(task.directory!);
      if (!_isCurrent(unitId, generation)) {
        throw const DownloadException('This download was removed.');
      }
      queued = !report.isComplete;
      await _repository.saveDownload(task.copyWith(
        status: queued ? DownloadStatus.queued : DownloadStatus.done,
        clearError: true,
        completed: report.available,
        bytes: bytes,
        updatedAt: _now(),
      ));
      return report;
    });
    if (queued) _schedule();
    return report;
  }

  /// Removes the row first and the bytes second: a half-deleted directory is
  /// recoverable, a row pointing at missing pages is not.
  Future<void> cancel(String unitId) async {
    _generations[unitId] = _generation(unitId) + 1;
    await _exclusive<void>(unitId, () async {
      final task = await _repository.downloadFor(unitId);
      if (task == null) return;
      await _repository.deleteDownload(unitId);
      final directory = task.directory;
      if (directory != null) await _deleteDirectory(Directory(directory));
    });
  }

  /// Bytes stored per work, finished downloads only. The Downloads screen
  /// groups by work, and the cap below evicts by work age.
  Future<Map<String, int>> bytesByMedia() async {
    final tasks = await _repository.downloads();
    final result = <String, int>{};
    for (final task in tasks) {
      if (!task.isFinished) continue;
      result[task.mediaId] = (result[task.mediaId] ?? 0) + task.bytes;
    }
    return result;
  }

  /// Keeps the offline store under [capBytes], oldest work first.
  ///
  /// `0` means "no cap". Only finished downloads are evicted: deleting a
  /// chapter that is still downloading would undo a person's tap. Returns the
  /// number of units removed so the caller can say what happened.
  Future<int> evictIfNeeded({required int capBytes}) async {
    if (capBytes <= 0) return 0;
    final finished = (await _repository.downloads())
        .where((task) => task.isFinished)
        .toList()
      ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    var total = finished.fold<int>(0, (sum, task) => sum + task.bytes);
    if (total <= capBytes) return 0;

    var removed = 0;
    for (final task in finished) {
      if (total <= capBytes) break;
      final bytes = await _exclusive<int?>(task.unitId, () async {
        final current = await _repository.downloadFor(task.unitId);
        if (current == null || !current.isFinished) return null;
        _generations[task.unitId] = _generation(task.unitId) + 1;
        await _repository.deleteDownload(task.unitId);
        if (current.directory != null) {
          await _deleteDirectory(Directory(current.directory!));
        }
        return current.bytes;
      });
      if (bytes != null) {
        total -= bytes;
        removed++;
      }
    }
    return removed;
  }

  /// Drains the queue. Safe to call at any time; concurrent callers share one
  /// drain instead of starting a second writer.
  Future<void> pump() {
    final active = _active;
    if (active != null) return active;
    _needsDrain = false;
    final future = _drain().whenComplete(() {
      _active = null;
      _signalDrain();
      // Enqueue can overlap the drain's last empty-queue read. Do not lose that
      // wakeup simply because a caller shared the drain that just ended.
      if (_needsDrain && !_disposed && mayDownload()) _schedule();
    });
    _active = future;
    _signalDrain();
    return future;
  }

  void dispose() {
    _disposed = true;
  }

  void _schedule() {
    _needsDrain = true;
    if (!mayDownload()) return;
    // A failed queue is reported per task; it must not become an unhandled
    // async error in a screen that already moved on.
    unawaited(pump().catchError((Object _) {}));
  }

  Future<void> _drain() async {
    if (_disposed || !mayDownload()) return;
    if (!(await _repository.downloads()).any(
        (task) => task.status == DownloadStatus.queued)) return;
    await prepareSources();

    final inFlight = <String, Future<void>>{};
    while (!_disposed) {
      if (!mayDownload()) break;
      final tasks = await _repository.downloads();
      final queued = tasks
          .where((task) =>
              task.status == DownloadStatus.queued &&
              !inFlight.containsKey(task.unitId))
          .toList()
        ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));

      final limit = maxConcurrent().clamp(1, 8);
      var launched = false;
      for (final task in queued) {
        if (inFlight.length >= limit) break;
        launched = true;
        inFlight[task.unitId] = _run(task.unitId).whenComplete(() {
          inFlight.remove(task.unitId);
        });
      }
      if (inFlight.isEmpty) {
        // A worker can finish before the next check; re-read the queue instead
        // of ending the drain while more chapters are still queued.
        if (!launched) break;
        continue;
      }
      await Future.any(inFlight.values.toList(growable: false));
    }
    if (inFlight.isNotEmpty) await Future.wait(inFlight.values);
  }

  Future<void> _run(String unitId) async {
    final generation = _generation(unitId);
    final task = await _exclusive<DownloadTask?>(unitId, () async {
      if (!_isCurrent(unitId, generation)) return null;
      final current = await _repository.downloadFor(unitId);
      if (current == null || current.status != DownloadStatus.queued) {
        return null;
      }
      final running = current.copyWith(
        status: DownloadStatus.running,
        clearError: true,
        updatedAt: _now(),
      );
      await _repository.saveDownload(running);
      return running;
    });
    if (task == null) return;

    try {
      final source = _registry.byId(task.sourceId);
      if (source == null) throw SourceNotInstalled(task.sourceId);

      final unit = await _unitFor(task);
      final resources =
          await source.resources(unit).timeout(const Duration(seconds: 30));
      final pages = <ImageResource>[];
      for (final resource in resources) {
        if (resource is ImageResource) pages.add(resource);
      }
      if (pages.isEmpty) {
        throw const DownloadException('This unit has no downloadable pages.');
      }

      final stored = await _exclusive<_StoredDownload?>(unitId, () async {
        if (!_isCurrent(unitId, generation)) return null;
        final current = await _repository.downloadFor(unitId);
        if (current == null || current.isPaused || current.isFailed) {
          return null;
        }
        // Once a source supplied a count and directory, a short later response
        // cannot turn an interrupted/repairing chapter into a smaller "done" one.
        final total = current.directory != null && current.total > pages.length
            ? current.total
            : pages.length;
        final directory = Directory(
          current.directory ?? p.join(_root.path, _folderName(unitId)),
        );
        await directory.create(recursive: true);
        final snapshot = current.copyWith(
          status: DownloadStatus.paused,
          total: total,
          directory: directory.path,
        );
        final report = await inspectStoredDownload(
          snapshot,
          shouldContinue: () => _isCurrent(unitId, generation),
        );
        if (!_isCurrent(unitId, generation)) return null;
        final damaged = {...report.missing, ...report.changed};
        for (var index = 0; index < total; index++) {
          if (!_isCurrent(unitId, generation)) return null;
          if (damaged.contains(index)) continue;
          final file = File(p.join(directory.path, downloadedPageName(index)));
          if (!await File('${file.path}.sha256').exists()) {
            // Adopt a baseline for legacy bytes, without redownloading or
            // claiming that their content was ever authenticated by the source.
            await writePageChecksum(file);
          }
        }
        final bytes = await directoryBytes(directory.path);
        if (!_isCurrent(unitId, generation)) return null;
        await _repository.saveDownload(
          current.copyWith(
            total: total,
            completed: report.available,
            bytes: bytes,
            status: DownloadStatus.running,
            directory: directory.path,
            updatedAt: _now(),
          ),
        );
        return _StoredDownload(directory, report, bytes);
      });
      if (stored == null) return;

      var completed = stored.report.available;
      var written = stored.bytes;
      final repairIndexes = [...stored.report.missing, ...stored.report.changed]
        ..sort();
      for (final index in repairIndexes) {
        final mayFetch = await _exclusive<bool>(unitId, () async {
          if (!_isCurrent(unitId, generation)) return false;
          final current = await _repository.downloadFor(unitId);
          return current != null && current.isActive;
        });
        if (!mayFetch) return;
        if (index >= pages.length) {
          throw const DownloadException(DownloadException.sourceIncomplete);
        }
        final bytes = await _fetch(
          pages[index],
          source: source,
          shouldContinue: () => _isCurrent(unitId, generation),
        );
        final keepRunning = await _exclusive<bool>(unitId, () async {
          if (!_isCurrent(unitId, generation)) return false;
          final current = await _repository.downloadFor(unitId);
          if (current == null || current.isFailed) return false;
          final file =
              File(p.join(stored.directory.path, downloadedPageName(index)));
          final oldSize = await file.exists() ? await file.length() : 0;
          await _write(file, bytes);
          await writePageChecksum(file, bytes: bytes);
          if (!_isCurrent(unitId, generation)) return false;
          completed++;
          written += bytes.length - oldSize;
          // A pause during the request keeps its finished page. Never overwrite
          // that pause using the task snapshot taken before awaiting the bytes.
          await _repository.saveDownload(current.copyWith(
            completed: completed,
            total: stored.report.total,
            bytes: written,
            status: current.isPaused
                ? DownloadStatus.paused
                : DownloadStatus.running,
            directory: stored.directory.path,
            updatedAt: _now(),
          ));
          return !current.isPaused;
        });
        if (!keepRunning) return;
      }

      final done = await _exclusive<bool>(unitId, () async {
        if (!_isCurrent(unitId, generation)) return false;
        final current = await _repository.downloadFor(unitId);
        if (current == null || !current.isActive) return false;
        final report = await inspectStoredDownload(
          current.copyWith(status: DownloadStatus.paused),
          shouldContinue: () => _isCurrent(unitId, generation),
        );
        final bytes = await directoryBytes(stored.directory.path);
        if (!_isCurrent(unitId, generation)) return false;
        await _repository.saveDownload(current.copyWith(
          completed: report.available,
          bytes: bytes,
          status:
              report.isComplete ? DownloadStatus.done : DownloadStatus.failed,
          clearError: report.isComplete,
          error:
              report.isComplete ? null : DownloadException.storedPagesChanged,
          updatedAt: _now(),
        ));
        return report.isComplete;
      });
      final cap = storageCap();
      if (done && cap > 0 && !_disposed) {
        unawaited(evictIfNeeded(capBytes: cap).catchError((Object _) => 0));
      }
    } catch (error) {
      await _exclusive<void>(unitId, () async {
        if (!_isCurrent(unitId, generation)) return;
        final current = await _repository.downloadFor(unitId);
        if (current == null || !current.isActive) return;
        await _repository.saveDownload(current.copyWith(
          status: DownloadStatus.failed,
          error: _describe(error),
          updatedAt: _now(),
        ));
      });
    }
  }

  Future<MediaUnit> _unitFor(DownloadTask task) async {
    final units = await _repository.unitsFor(task.mediaId);
    for (final unit in units) {
      if (unit.url == task.unitUrl) return unit;
    }
    // The catalogue can be refreshed while a download is queued. The URL is the
    // only field a source actually needs, so a minimal unit still works.
    return MediaUnit(
      mediaId: task.mediaId,
      url: task.unitUrl,
      number: 0,
      title: task.unitTitle,
      kind: UnitKind.chapter,
    );
  }

  Future<List<int>> _fetch(
    ImageResource resource, {
    SourceAdapter? source,
    bool Function()? shouldContinue,
  }) async {
    final uri = Uri.tryParse(resource.url);
    if (uri == null || !uri.hasScheme) {
      throw const DownloadException('The page address is not valid.');
    }

    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      if (shouldContinue != null && !shouldContinue()) {
        throw const DownloadException('This download was removed.');
      }
      try {
        if (source case final PageBytesSource byteSource) {
          final bytes = await byteSource
              .pageBytes(resource)
              .timeout(const Duration(seconds: 25));
          if (bytes != null) {
            if (bytes.isEmpty) {
              throw const DownloadException('The page came back empty.');
            }
            return bytes;
          }
        }
        final response = await _client
            .get(uri, headers: resource.headers)
            .timeout(const Duration(seconds: 25));
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw DownloadException('HTTP ${response.statusCode}');
        }
        if (response.bodyBytes.isEmpty) {
          throw const DownloadException('The page came back empty.');
        }
        return response.bodyBytes;
      } catch (error) {
        lastError = error;
        if (attempt == 0 && (shouldContinue == null || shouldContinue())) {
          await Future<void>.delayed(const Duration(milliseconds: 400));
        }
      }
    }
    throw lastError ??
        const DownloadException('The page could not be fetched.');
  }

  Future<void> _write(File file, List<int> bytes) async {
    await file.parent.create(recursive: true);
    final part = File('${file.path}.part');
    await part.writeAsBytes(bytes, flush: true);
    await part.rename(file.path);
  }

  Future<void> _deleteDirectory(Directory directory) async {
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
    } catch (_) {
      // Best effort: an orphaned directory is invisible to the queue.
    }
  }

  static int _now() => DateTime.now().millisecondsSinceEpoch;

  static String _describe(Object error) {
    if (error is DownloadException) return error.message;
    if (error is SourceNotInstalled) return DownloadException.sourceMissing;
    if (error is HttpException) return error.message;
    return 'The download stopped: $error';
  }

  /// Stable across launches and platforms, unlike [String.hashCode]. Two
  /// FNV-1a rounds make an accidental collision between chapter URLs
  /// vanishingly unlikely without pulling in a crypto dependency.
  static String _folderName(String unitId) {
    final first = _hash32(unitId, 0x811C9DC5);
    final second = _hash32(unitId, 0x9E3779B9);
    return '${first.toRadixString(16).padLeft(8, '0')}'
        '${second.toRadixString(16).padLeft(8, '0')}';
  }

  static int _hash32(String value, int seed) {
    var hash = seed;
    for (final code in value.codeUnits) {
      hash ^= code;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }
}

class _StoredDownload {
  const _StoredDownload(this.directory, this.report, this.bytes);

  final Directory directory;
  final DownloadIntegrityReport report;
  final int bytes;
}
