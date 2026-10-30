import 'dart:async';
import 'dart:io';

import 'package:best_domain/best_domain.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'local_pages.dart';

/// A failure worth showing under a download row, without a stack trace.
class DownloadException implements Exception {
  const DownloadException(this.message);

  final String message;

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

  /// A cancelled unit can still be mid-request. The set closes the window
  /// between deleting the row and the request returning, so a late page can
  /// never recreate the row it was deleted from.
  final Set<String> _cancelled = {};

  /// Called once per app launch: anything the process left `running` becomes
  /// queued again, and the queue starts where it stopped.
  Future<void> restore() async {
    final tasks = await _repository.downloads();
    final now = _now();
    for (final task in tasks) {
      if (task.isFinished && task.bytes == 0 && task.directory != null) {
        final bytes = await directoryBytes(task.directory!);
        if (bytes > 0) {
          await _repository.saveDownload(task.copyWith(bytes: bytes));
        }
        continue;
      }
      if (task.status == DownloadStatus.running ||
          task.status == DownloadStatus.queued) {
        await _repository.saveDownload(
          task.copyWith(status: DownloadStatus.queued, updatedAt: now),
        );
      }
    }
    await pump();
  }

  /// Queues a unit and returns immediately. The row is written before the first
  /// request, so the Downloads screen can show it without waiting for bytes.
  Future<DownloadTask> enqueue(Media media, MediaUnit unit) async {
    _cancelled.remove(unit.id);
    final existing = await _repository.downloadFor(unit.id);
    if (existing != null && (existing.isFinished || existing.isActive)) {
      return existing;
    }

    final task = DownloadTask(
      unitId: unit.id,
      mediaId: media.id,
      sourceId: media.ref.sourceId,
      mediaUrl: media.ref.url,
      unitUrl: unit.url,
      mediaTitle: media.displayTitle,
      unitTitle: unit.displayTitle,
      total: unit.pageCount > 0 ? unit.pageCount : (existing?.total ?? 0),
      completed: existing?.completed ?? 0,
      bytes: existing?.bytes ?? 0,
      status: DownloadStatus.queued,
      directory: existing?.directory,
      updatedAt: _now(),
    );
    await _repository.saveDownload(task);
    _schedule();
    return task;
  }

  Future<void> pause(String unitId) async {
    final task = await _repository.downloadFor(unitId);
    if (task == null || task.isFinished) return;
    await _repository.saveDownload(
      task.copyWith(status: DownloadStatus.paused, updatedAt: _now()),
    );
  }

  Future<void> resume(String unitId) async {
    final task = await _repository.downloadFor(unitId);
    if (task == null || task.isFinished || task.isActive) return;
    await _repository.saveDownload(
      task.copyWith(
        status: DownloadStatus.queued,
        clearError: true,
        updatedAt: _now(),
      ),
    );
    _schedule();
  }

  Future<void> retry(String unitId) => resume(unitId);

  /// Removes the row first and the bytes second: a half-deleted directory is
  /// recoverable, a row pointing at missing pages is not.
  Future<void> cancel(String unitId) async {
    final task = await _repository.downloadFor(unitId);
    if (task == null) return;
    _cancelled.add(unitId);
    await _repository.deleteDownload(unitId);
    final directory = task.directory;
    if (directory != null) await _deleteDirectory(Directory(directory));
  }

  /// Drains the queue. Safe to call at any time; concurrent callers share one
  /// drain instead of starting a second writer.
  Future<void> pump() {
    final active = _active;
    if (active != null) return active;
    final future = _drain().whenComplete(() => _active = null);
    _active = future;
    return future;
  }

  void dispose() {
    _disposed = true;
  }

  void _schedule() {
    // A failed queue is reported per task; it must not become an unhandled
    // async error in a screen that already moved on.
    unawaited(pump().catchError((Object _) {}));
  }

  Future<void> _drain() async {
    while (!_disposed) {
      final tasks = await _repository.downloads();
      DownloadTask? next;
      for (final task in tasks) {
        if (task.status != DownloadStatus.queued) continue;
        if (next == null || task.updatedAt < next.updatedAt) next = task;
      }
      if (next == null) return;
      await _run(next.unitId);
    }
  }

  Future<void> _run(String unitId) async {
    if (_cancelled.contains(unitId)) return;
    var task = await _repository.downloadFor(unitId);
    if (task == null || task.status != DownloadStatus.queued) return;

    task = task.copyWith(
      status: DownloadStatus.running,
      clearError: true,
      updatedAt: _now(),
    );
    await _repository.saveDownload(task);

    Directory? directory;
    try {
      final source = _registry.byId(task.sourceId);
      if (source == null) {
        throw const DownloadException(
            'The source for this download is not installed.');
      }

      final unit = await _unitFor(task);
      final resources = await source.resources(unit);
      final pages = <ImageResource>[];
      for (final resource in resources) {
        if (resource is ImageResource) pages.add(resource);
      }
      if (pages.isEmpty) {
        throw const DownloadException('This unit has no downloadable pages.');
      }

      if (_cancelled.contains(unitId)) return;
      final beforePages = await _repository.downloadFor(unitId);
      if (beforePages == null) return;
      if (beforePages.status == DownloadStatus.paused ||
          beforePages.status == DownloadStatus.failed) {
        return;
      }

      directory = Directory(p.join(_root.path, _folderName(unitId)));
      await directory.create(recursive: true);

      task = task.copyWith(
        total: pages.length,
        directory: directory.path,
        updatedAt: _now(),
      );
      await _repository.saveDownload(task);

      var completed = 0;
      var written = await directoryBytes(directory.path);
      for (var index = 0; index < pages.length; index++) {
        if (_disposed) return;
        if (_cancelled.contains(unitId)) return;
        var current = await _repository.downloadFor(unitId);
        if (current == null) {
          await _deleteDirectory(directory);
          return;
        }
        if (current.status == DownloadStatus.paused ||
            current.status == DownloadStatus.failed) {
          return;
        }

        final file = File(p.join(directory.path, _pageName(index)));
        if (await file.exists() && await file.length() > 0) {
          completed++;
          continue;
        }

        final bytes = await _fetch(pages[index]);
        if (_cancelled.contains(unitId)) return;
        current = await _repository.downloadFor(unitId);
        if (current == null) {
          await _deleteDirectory(directory);
          return;
        }
        if (current.status == DownloadStatus.paused) {
          // The request cannot be cancelled mid-flight, so the page that just
          // arrived is kept and counted. Resuming skips it.
          await _write(file, bytes);
          await _repository.saveDownload(
            current.copyWith(
              completed: completed + 1,
              total: pages.length,
              bytes: written + bytes.length,
              directory: directory.path,
              updatedAt: _now(),
            ),
          );
          return;
        }
        if (current.status == DownloadStatus.failed) return;

        await _write(file, bytes);
        completed++;
        written += bytes.length;
        await _repository.saveDownload(
          current.copyWith(
            completed: completed,
            total: pages.length,
            bytes: written,
            status: DownloadStatus.running,
            directory: directory.path,
            updatedAt: _now(),
          ),
        );
      }

      if (_cancelled.contains(unitId)) return;
      final current = await _repository.downloadFor(unitId);
      if (current == null) return;
      await _repository.saveDownload(
        current.copyWith(
          total: pages.length,
          completed: pages.length,
          bytes: written,
          status: DownloadStatus.done,
          clearError: true,
          directory: directory.path,
          updatedAt: _now(),
        ),
      );
    } catch (error) {
      if (_cancelled.contains(unitId)) return;
      final current = await _repository.downloadFor(unitId);
      if (current == null || current.status == DownloadStatus.paused) return;
      await _repository.saveDownload(
        current.copyWith(
          status: DownloadStatus.failed,
          error: _describe(error),
          updatedAt: _now(),
        ),
      );
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

  Future<List<int>> _fetch(ImageResource resource) async {
    final uri = Uri.tryParse(resource.url);
    if (uri == null || !uri.hasScheme) {
      throw const DownloadException('The page address is not valid.');
    }

    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
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
        if (attempt == 0) {
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

  static String _pageName(int index) =>
      'page_${(index + 1).toString().padLeft(4, '0')}.img';
}
