import 'dart:io';

import 'package:best_domain/best_domain.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

String downloadedPageName(int index) =>
    'page_${(index + 1).toString().padLeft(4, '0')}.img';

final _digestPattern = RegExp(r'^[a-fA-F0-9]{64}$');

Future<String> _digest(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

/// Legacy pages without a checksum are usable, but not claimed as verified.
/// A malformed checksum is an integrity problem, not silently a legacy file.
Future<bool> storedPageIsIntact(File file) async {
  try {
    if (!await file.exists() || await file.length() == 0) return false;
    final reference = File('${file.path}.sha256');
    if (!await reference.exists()) return true;
    final expected = (await reference.readAsString()).trim().toLowerCase();
    if (!_digestPattern.hasMatch(expected)) return false;
    return expected == await _digest(file);
  } on FileSystemException {
    return false;
  }
}

Future<void> writePageChecksum(File file, {List<int>? bytes}) async {
  final digest =
      bytes == null ? await _digest(file) : sha256.convert(bytes).toString();
  final target = File('${file.path}.sha256');
  final part = File('${target.path}.part');
  await part.writeAsString(digest, flush: true);
  await part.rename(target.path);
}

Future<DownloadIntegrityReport> inspectStoredDownload(
  DownloadTask task, {
  bool verifyHashes = true,
  bool Function()? shouldContinue,
}) async {
  if (task.isActive) {
    return DownloadIntegrityReport(
        total: task.total, available: task.completed, busy: true);
  }
  final missing = <int>[];
  final changed = <int>[];
  var available = 0;
  var verified = 0;
  final total = task.total > 0 ? task.total : 0;
  for (var index = 0; index < total; index++) {
    if (shouldContinue != null && !shouldContinue()) {
      return DownloadIntegrityReport(
        total: total,
        available: available,
        verified: verified,
        busy: true,
      );
    }
    if (task.directory == null) {
      missing.add(index);
      continue;
    }
    final file = File(p.join(task.directory!, downloadedPageName(index)));
    try {
      if (!await file.exists()) {
        missing.add(index);
        continue;
      }
      if (await file.length() == 0) {
        changed.add(index);
        continue;
      }
      if (verifyHashes) {
        final reference = File('${file.path}.sha256');
        if (await reference.exists()) {
          if (!await storedPageIsIntact(file)) {
            changed.add(index);
            continue;
          }
          verified++;
        }
      }
      available++;
    } on FileSystemException {
      changed.add(index);
    }
  }
  return DownloadIntegrityReport(
    total: total,
    available: available,
    verified: verified,
    missing: List.unmodifiable(missing),
    changed: List.unmodifiable(changed),
  );
}
