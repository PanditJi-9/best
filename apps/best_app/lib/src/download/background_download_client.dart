import 'dart:io';
import 'package:flutter/services.dart';

/// Android protects the lifetime of the existing Dart manager. It receives
/// display snapshots, never a second set of URLs or file paths to download.
class BackgroundDownloadClient {
  const BackgroundDownloadClient({this.enabled});

  final bool? enabled;
  bool get isSupported => enabled ?? Platform.isAndroid;

  static const MethodChannel _channel =
      MethodChannel('app.best/background_download');

  Future<bool> initialize({
    required Future<void> Function(String, String?) onAction,
    required void Function(String) onFailure,
  }) async {
    if (!isSupported) return false;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'notificationAction' && call.arguments is Map) {
        final arguments = call.arguments as Map;
        final action = arguments['action'];
        final unitId = arguments['unitId'];
        if (action is String) {
          await onAction(action, unitId is String ? unitId : null);
        }
      } else if (call.method == 'backgroundFailure') {
        onFailure('${call.arguments}');
      }
    });
    return await _channel.invokeMethod<bool>('ready') ?? false;
  }

  Future<bool> publish(BackgroundDownloadSnapshot snapshot) async {
    if (!isSupported) return false;
    return await _channel.invokeMethod<bool>(
          'updateDownloadState', snapshot.toMap()) ??
        false;
  }

  void dispose() {
    if (isSupported) _channel.setMethodCallHandler(null);
  }
}

class BackgroundDownloadSnapshot {
  const BackgroundDownloadSnapshot({
    required this.pending,
    required this.wifiOnly,
    required this.title,
    required this.detail,
    required this.pauseLabel,
    this.unitId = '',
    this.progress = 0,
    this.total = 0,
  });

  final bool pending;
  final bool wifiOnly;
  final String unitId;
  final String title;
  final String detail;
  final String pauseLabel;
  final int progress;
  final int total;

  Map<String, Object> toMap() => {
        'pending': pending,
        'wifiOnly': wifiOnly,
        'unitId': unitId,
        'title': title,
        'detail': detail,
        'pauseLabel': pauseLabel,
        'progress': progress,
        'total': total,
      };
}

class BackgroundDownloadState {
  const BackgroundDownloadState({
    this.available = false,
    this.error,
    this.openRequests = 0,
  });

  final bool available;
  final String? error;
  final int openRequests;
}
