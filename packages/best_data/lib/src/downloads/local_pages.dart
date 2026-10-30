import 'dart:io';

import 'package:best_domain/best_domain.dart';
import 'package:path/path.dart' as p;

/// Reads the pages a finished download left on disk, in reading order.
///
/// The reader calls this instead of a source when a chapter is complete, so
/// opening a downloaded chapter never touches the network. Names are written
/// zero-padded by the manager, which is what makes a plain name sort correct.
Future<List<MediaResource>> downloadedPages(String directory) async {
  final folder = Directory(directory);
  if (!await folder.exists()) return const <MediaResource>[];

  final files = <File>[];
  await for (final entity in folder.list(followLinks: false)) {
    if (entity is! File) continue;
    final name = p.basename(entity.path);
    if (!name.startsWith('page_') || !name.endsWith('.img')) continue;
    files.add(entity);
  }
  files.sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
  return <MediaResource>[for (final file in files) FileResource(file.path)];
}
