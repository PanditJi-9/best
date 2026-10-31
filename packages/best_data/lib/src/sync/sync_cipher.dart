import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// Thrown when a sync envelope cannot be opened.
///
/// It carries a human sentence because every caller shows it to a person: a
/// wrong passphrase and a truncated file both end up on the same screen.
class SyncException implements Exception {
  const SyncException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Seals a backup before it leaves the phone.
///
/// AES-256-GCM with a PBKDF2-HMAC-SHA256 key. The envelope is JSON so a person
/// can still see that the file is a Best sync blob and which format wrote it,
/// while the payload itself is opaque. A sync server only ever holds ciphertext:
/// the passphrase never leaves the device and is never stored with the key.
///
/// The iteration count is part of the envelope, so raising it later does not
/// strand an older file.
class SyncCipher {
  const SyncCipher._();

  static const String format = 'best.sync';
  static const int version = 1;
  static const int defaultIterations = 150000;

  /// Associated data binds the envelope to this format, so a ciphertext cannot
  /// be replayed into a different document type that shares the key.
  static final List<int> _aad = utf8.encode('$format.v$version');

  static Future<String> seal({
    required String plaintext,
    required String passphrase,
    int iterations = defaultIterations,
    Random? random,
  }) async {
    _requirePassphrase(passphrase);
    final source = random ?? Random.secure();
    final salt = List<int>.generate(16, (_) => source.nextInt(256));
    final key = await _deriveKey(passphrase, salt, iterations);
    final algorithm = AesGcm.with256bits();
    final nonce = algorithm.newNonce();
    final box = await algorithm.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
      nonce: nonce,
      aad: _aad,
    );

    return const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'format': format,
      'v': version,
      'kdf': 'pbkdf2-sha256',
      'iter': iterations,
      'salt': base64Encode(salt),
      'nonce': base64Encode(box.nonce),
      'mac': base64Encode(box.mac.bytes),
      'data': base64Encode(box.cipherText),
    });
  }

  /// Opens an envelope, or throws [SyncException] with a sentence worth showing.
  static Future<String> open({
    required String envelope,
    required String passphrase,
  }) async {
    _requirePassphrase(passphrase);
    final Object? parsed;
    try {
      parsed = jsonDecode(envelope);
    } on FormatException {
      throw const SyncException('This file is not a Best sync file.');
    }
    if (parsed is! Map<String, Object?>) {
      throw const SyncException('This file is not a Best sync file.');
    }
    if (parsed['format'] != format) {
      throw const SyncException('This file is not a Best sync file.');
    }
    final fileVersion = parsed['v'];
    if (fileVersion is! int || fileVersion < 1 || fileVersion > version) {
      throw SyncException('This sync file uses format $fileVersion.');
    }

    final salt = _bytes(parsed['salt']);
    final nonce = _bytes(parsed['nonce']);
    final mac = _bytes(parsed['mac']);
    final data = _bytes(parsed['data']);
    final iterations = parsed['iter'];
    if (salt == null || nonce == null || mac == null || data == null) {
      throw const SyncException('This sync file is incomplete.');
    }
    if (iterations is! int || iterations < 1000 || iterations > 5000000) {
      throw const SyncException('This sync file has an unusable key setup.');
    }

    final key = await _deriveKey(passphrase, salt, iterations);
    try {
      final clear = await AesGcm.with256bits().decrypt(
        SecretBox(data, nonce: nonce, mac: Mac(mac)),
        secretKey: key,
        aad: _aad,
      );
      return utf8.decode(clear);
    } on SecretBoxAuthenticationError {
      throw const SyncException('The passphrase is wrong, or the file changed.');
    }
  }

  static Future<SecretKey> _deriveKey(
    String passphrase,
    List<int> salt,
    int iterations,
  ) {
    final kdf = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );
    return kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );
  }

  static void _requirePassphrase(String passphrase) {
    if (passphrase.trim().length < 8) {
      throw const SyncException('Use a passphrase of at least 8 characters.');
    }
  }

  static List<int>? _bytes(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    try {
      return base64Decode(raw);
    } on FormatException {
      return null;
    }
  }
}
