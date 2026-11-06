import 'dart:ui' show Rect;

import 'package:share_plus/share_plus.dart';

/// The system chooser decides where a person keeps their backup. Preparing a
/// file never uploads it on its own. Kept injectable for tests and platforms
/// where file sharing is unavailable.
class BackupFileSharer {
  const BackupFileSharer();

  Future<void> share(
    String path, {
    required String title,
    Rect? origin,
  }) async {
    await SharePlus.instance.share(ShareParams(
      files: [XFile(path, mimeType: 'application/json')],
      title: title,
      subject: title,
      sharePositionOrigin: origin,
    ));
  }
}
