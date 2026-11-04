import 'dart:convert';
import 'package:flutter/services.dart';

/// Client to trigger and manage Android WorkManager background foreground downloads.
/// Matches HikariManga 1.4.2 WorkManager download architecture.
class BackgroundDownloadClient {
  const BackgroundDownloadClient();

  static const MethodChannel _channel =
      MethodChannel('app.best/background_download');

  /// Enqueues a chapter download with native Android WorkManager,
  /// creating a persistent foreground notification with Pause/Cancel actions.
  Future<bool> enqueue({
    required String chapterId,
    required String mangaTitle,
    required String chapterTitle,
    required int totalPages,
    required List<Map<String, dynamic>> pages,
  }) async {
    try {
      final res = await _channel.invokeMethod<bool>('enqueueBackgroundDownload', {
        'chapterId': chapterId,
        'mangaTitle': mangaTitle,
        'chapterTitle': chapterTitle,
        'totalPages': totalPages,
        'pagesJson': jsonEncode(pages),
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> cancel(String chapterId) async {
    try {
      await _channel.invokeMethod('cancelDownload', {'chapterId': chapterId});
    } catch (_) {}
  }

  Future<void> pause(String chapterId) async {
    try {
      await _channel.invokeMethod('pauseDownload', {'chapterId': chapterId});
    } catch (_) {}
  }

  Future<void> resume(String chapterId) async {
    try {
      await _channel.invokeMethod('resumeDownload', {'chapterId': chapterId});
    } catch (_) {}
  }
}
