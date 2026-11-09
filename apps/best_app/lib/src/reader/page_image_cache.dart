import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:best_domain/best_domain.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// A small disk + memory cache for page images.
///
/// Flutter's image cache lives in RAM only, so reopening a chapter used to
/// download every scan again. This keeps the bytes on disk, keyed by the URL
/// and the headers that authenticate it, and returns the same byte buffer for
/// a page so the decoded image cache can reuse it too.
///
/// Extension pages are deliberately excluded by the caller: those requests
/// must go through the extension's own signing client.
class PageImageCache {
  PageImageCache({
    required http.Client client,
    Directory? directory,
    this.maxBytes = 160 * 1024 * 1024,
    this.memoryEntries = 10,
  })  : _client = client,
        _directory = directory;

  final http.Client _client;
  final int maxBytes;
  final int memoryEntries;

  Directory? _directory;
  final Map<String, Uint8List> _memory = <String, Uint8List>{};
  final Map<String, Future<Uint8List?>> _inFlight =
      <String, Future<Uint8List?>>{};
  int _writesSincePrune = 0;
  bool _prunedOnOpen = false;

  /// Returns cached bytes, or fetches and stores them. A failed request is not
  /// cached, so the page's retry can ask the source again.
  Future<Uint8List?> load(ImageResource resource) {
    final key = _key(resource);
    final remembered = _memory[key];
    if (remembered != null) {
      _touchMemory(key, remembered);
      return Future<Uint8List?>.value(remembered);
    }
    return _inFlight.putIfAbsent(
      key,
      () => _load(key, resource).whenComplete(() => _inFlight.remove(key)),
    );
  }

  Future<Uint8List?> _load(String key, ImageResource resource) async {
    File file;
    try {
      file = await _fileFor(key);
    } catch (_) {
      return null;
    }
    try {
      if (await file.exists() && await file.length() > 0) {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) {
          await _touch(file);
          _remember(key, bytes);
          return bytes;
        }
      }
    } catch (_) {
      // A missing or unreadable cache entry is a miss, not a reading failure.
    }

    try {
      final response = await _client
          .get(
            Uri.parse(resource.url),
            headers: resource.headers.isEmpty ? null : resource.headers,
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        return null;
      }
      final bytes = response.bodyBytes;
      _remember(key, bytes);
      unawaited(_write(file, bytes));
      return bytes;
    } catch (_) {
      return null;
    }
  }

  /// Forgets one page. Called by a retry so a damaged file is not replayed.
  Future<void> evict(ImageResource resource) async {
    final key = _key(resource);
    _memory.remove(key);
    _inFlight.remove(key);
    try {
      final file = await _fileFor(key);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Best effort: the retry can still fetch from the source.
    }
  }

  Future<void> clear() async {
    _memory.clear();
    _inFlight.clear();
    try {
      final directory = await _cacheDirectory();
      await directory.delete(recursive: true);
      _directory = null;
    } catch (_) {
      // A cache that cannot be cleared is still a cache.
    }
  }

  Future<void> _write(File file, Uint8List bytes) async {
    try {
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsBytes(bytes, flush: false);
      await temporary.rename(file.path);
      _writesSincePrune++;
      if (_writesSincePrune >= 24) {
        _writesSincePrune = 0;
        unawaited(_prune());
      }
    } catch (_) {
      try {
        await File('${file.path}.tmp').delete();
      } catch (_) {
        // The temp file may never have been created.
      }
    }
  }

  Future<void> _touch(File file) async {
    try {
      await file.setLastModified(DateTime.now());
    } catch (_) {
      // Some filesystems do not support mtime updates; pruning still works.
    }
  }

  void _remember(String key, Uint8List bytes) {
    _memory.remove(key);
    _memory[key] = bytes;
    while (_memory.length > memoryEntries) {
      _memory.remove(_memory.keys.first);
    }
  }

  void _touchMemory(String key, Uint8List bytes) {
    _memory.remove(key);
    _memory[key] = bytes;
  }

  Future<Directory> _cacheDirectory() async {
    final existing = _directory;
    if (existing != null) return existing;
    Directory directory;
    try {
      final temporary = await getTemporaryDirectory();
      directory = Directory(p.join(temporary.path, 'best-reader-cache'));
    } catch (_) {
      directory = Directory(p.join(Directory.systemTemp.path, 'best-reader-cache'));
    }
    await directory.create(recursive: true);
    _directory = directory;
    if (!_prunedOnOpen) {
      _prunedOnOpen = true;
      // A previous session may have left the cache over its cap. Trim it in
      // the background so the first page still loads immediately.
      unawaited(_prune());
    }
    return directory;
  }

  Future<File> _fileFor(String key) async {
    final directory = await _cacheDirectory();
    return File(p.join(directory.path, '$key.img'));
  }

  String _key(ImageResource resource) {
    final headers = resource.headers.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final raw = <String>[
      resource.url,
      for (final header in headers) '${header.key}:${header.value}',
    ].join('\n');
    return sha256.convert(utf8.encode(raw)).toString();
  }

  /// Keeps the cache under [maxBytes], deleting the least recently read pages
  /// first. It leaves some headroom so pruning is not needed on every write.
  Future<void> _prune() async {
    try {
      final directory = await _cacheDirectory();
      final files = <File>[];
      await for (final entity in directory.list()) {
        if (entity is File && entity.path.endsWith('.img')) {
          files.add(entity);
        }
      }
      var total = 0;
      final entries = <({File file, int modified})>[];
      for (final file in files) {
        try {
          final stat = await file.stat();
          total += stat.size;
          entries.add((file: file, modified: stat.modified.millisecondsSinceEpoch));
        } catch (_) {
          // A file removed by another cleanup is simply skipped.
        }
      }
      if (total <= maxBytes) return;
      entries.sort((a, b) => a.modified.compareTo(b.modified));
      final target = (maxBytes * 0.8).round();
      for (final entry in entries) {
        if (total <= target) break;
        try {
          final size = await entry.file.length();
          await entry.file.delete();
          total -= size;
        } catch (_) {
          // Keep pruning the rest even if one file is locked.
        }
      }
    } catch (_) {
      // Cleanup is opportunistic and must never interrupt reading.
    }
  }
}
