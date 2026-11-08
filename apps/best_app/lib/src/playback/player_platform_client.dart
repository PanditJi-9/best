import 'dart:io';
import 'package:flutter/services.dart';

/// Activity-only presentation features, separate from the playback engine.
/// Session ownership prevents a replaced episode from clearing its successor's
/// PiP callback during an animated route transition.
class PlayerPlatformClient {
  PlayerPlatformClient({this.enabled});
  final bool? enabled;
  static const _channel = MethodChannel('app.best/player');
  static int _owner = 0;
  int _session = 0;

  bool get isSupported => enabled ?? Platform.isAndroid;

  Future<bool> initialize(void Function(bool) onPip) async {
    if (!isSupported) return false;
    _session = ++_owner;
    _channel.setMethodCallHandler((call) async {
      if (_session == _owner && call.method == 'pipChanged') {
        onPip(call.arguments == true);
      }
    });
    try {
      return await _channel.invokeMethod<bool>('pipSupported') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> enterPip(double aspectRatio) async {
    if (!isSupported || _session != _owner) return false;
    try {
      return await _channel.invokeMethod<bool>('enterPip', {
        'aspectRatio': aspectRatio,
      }) ?? false;
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    if (isSupported && _session == _owner) {
      _channel.setMethodCallHandler(null);
      _owner++;
    }
  }
}
