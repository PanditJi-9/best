import 'package:flutter/services.dart';

/// Dart client for native biometric authentication (fingerprint, face, lock credential).
class BiometricClient {
  const BiometricClient();

  static const MethodChannel _channel = MethodChannel('app.best/biometric');

  Future<bool> canAuthenticate() async {
    try {
      final res = await _channel.invokeMethod<bool>('canAuthenticate');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticate({
    String title = 'تأكيد الهوية',
    String subtitle = 'استخدم بصمة الإصبع أو رمز القفل للمتابعة',
  }) async {
    try {
      final res = await _channel.invokeMethod<bool>('authenticate', {
        'title': title,
        'subtitle': subtitle,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }
}
