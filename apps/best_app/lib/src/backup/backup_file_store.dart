import 'dart:io';

import 'package:path/path.dart' as p;

/// Each export owns a unique directory so a second backup cannot truncate the
/// previous copy, even if the device clock changes or two writes share a stamp.
class BackupFileStore {
  const BackupFileStore();

  Future<File> write(String document, Directory directory) async {
    await directory.create(recursive: true);
    final folder = await directory.createTemp('best-backup-');
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final file = File(p.join(folder.path, 'best-backup-$stamp.json'));
    await file.writeAsString(document, flush: true);
    return file;
  }
}
