import 'dart:io';

import 'package:best_domain/best_domain.dart';
import 'package:path/path.dart' as p;

import 'integrity.dart';

/// Reads a contiguous prefix without changing any source-page identities.
///
/// The reader calls this instead of a source when a chapter is complete, so
/// A gap or an empty file ends the prefix: a later page must never become the
/// missing page's number or inherit its bookmarks. Extra pages beyond a known
/// total stay on disk, but are not exposed as part of this chapter.
Future<List<MediaResource>> downloadedPages(
  String directory, {
  int? expectedCount,
}) async {
  final pages = <MediaResource>[];
  for (var index = 0; expectedCount == null || index < expectedCount; index++) {
    final file = File(p.join(directory, downloadedPageName(index)));
    try {
      if (!await file.exists() || await file.length() == 0) break;
      pages.add(FileResource(file.path));
    } on FileSystemException {
      // Deletion can race a reader opening the chapter. Keep the prefix that
      // was actually available rather than throwing from a directory scan.
      break;
    }
  }
  return pages;
}

/// Bytes of finished pages in [directory]. Used by storage accounting and to
/// backfill rows written before byte tracking existed.
Future<int> directoryBytes(String directory) async {
  var total = 0;
  for (final file in await _pageFiles(directory)) {
    try {
      total += await file.length();
    } on FileSystemException {
      // A cancelled download may have removed this file after enumeration.
    }
  }
  return total;
}

Future<List<File>> _pageFiles(String directory) async {
  final folder = Directory(directory);
  if (!await folder.exists()) return const <File>[];

  final files = <File>[];
  try {
    await for (final entity in folder.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (!RegExp(r'^page_[0-9]{4,}\.img$').hasMatch(name)) continue;
      if (int.tryParse(name.substring(5, name.length - 4)) == 0) continue;
      files.add(entity);
    }
  } on FileSystemException {
    // The row is deleted before its directory; an opening scan can overlap it.
  }
  files.sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
  return files;
}
