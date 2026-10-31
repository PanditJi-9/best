import 'dart:convert';

import 'package:http/http.dart' as http;

import 'sync_cipher.dart';

/// A tiny WebDAV client: enough to keep one file in sync, nothing more.
///
/// Nextcloud, ownCloud, Koofr and a plain Apache directory all speak this much.
/// The client only ever sends an already-sealed document, so the server never
/// sees a shelf, a title or a reading position.
class WebDavSync {
  WebDavSync({
    required this.baseUrl,
    required this.username,
    required this.password,
    required http.Client client,
    this.fileName = 'best-sync.json',
    this.timeout = const Duration(seconds: 30),
  }) : _client = client;

  /// The folder that will hold [fileName]. Validated in [fromSettings].
  final Uri baseUrl;
  final String username;
  final String password;
  final String fileName;
  final Duration timeout;
  final http.Client _client;

  /// Validates a person's input before anything is stored.
  ///
  /// HTTPS only, except for a loopback address used while developing. A plain
  /// `http://` server on the open internet would expose the Basic-auth header,
  /// so it is rejected instead of quietly downgraded.
  static WebDavSync? fromSettings({
    required String url,
    required String username,
    required String password,
    required http.Client client,
    String fileName = 'best-sync.json',
  }) {
    final parsed = Uri.tryParse(url.trim());
    if (parsed == null || !parsed.hasAuthority) return null;
    final loopback = parsed.host == 'localhost' || parsed.host == '127.0.0.1';
    if (parsed.scheme != 'https' && !(parsed.scheme == 'http' && loopback)) {
      return null;
    }
    return WebDavSync(
      baseUrl: parsed,
      username: username,
      password: password,
      client: client,
      fileName: fileName,
    );
  }

  Map<String, String> get _auth => <String, String>{
        if (username.isNotEmpty || password.isNotEmpty)
          'authorization':
              'Basic ${base64Encode(utf8.encode('$username:$password'))}',
      };

  Uri get fileUri {
    final base = baseUrl.path.endsWith('/')
        ? baseUrl
        : baseUrl.replace(path: '${baseUrl.path}/');
    return base.resolve(fileName);
  }

  /// Uploads the sealed document. Creates the folder once when the server says
  /// it does not exist (409), because most WebDAV servers do not auto-create.
  Future<void> upload(String sealed) async {
    final body = utf8.encode(sealed);
    final headers = <String, String>{
      ..._auth,
      'content-type': 'application/json; charset=utf-8',
    };

    var response = await _client
        .put(fileUri, headers: headers, body: body)
        .timeout(timeout);
    if (response.statusCode == 409 || response.statusCode == 404) {
      await _createFolder();
      response = await _client
          .put(fileUri, headers: headers, body: body)
          .timeout(timeout);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SyncException(
        'The sync server answered HTTP ${response.statusCode}.',
      );
    }
  }

  /// Downloads the sealed document, or `null` when nothing is stored yet.
  Future<String?> download() async {
    final response = await _client
        .get(fileUri, headers: _auth)
        .timeout(timeout);
    if (response.statusCode == 404) return null;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SyncException(
        'The sync server answered HTTP ${response.statusCode}.',
      );
    }
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }

  /// `MKCOL` each missing segment, ignoring "already there" (405).
  Future<void> _createFolder() async {
    final segments = baseUrl.path.split('/').where((s) => s.isNotEmpty);
    var path = '';
    for (final segment in segments) {
      path = '$path/$segment';
      final response = await _client
          .send(
            http.Request(
              'MKCOL',
              baseUrl.replace(path: '$path/'),
            )..headers.addAll(_auth),
          )
          .timeout(timeout);
      await response.stream.drain<void>();
      if (response.statusCode >= 400 && response.statusCode != 405) {
        throw SyncException(
          'Could not create the sync folder (HTTP ${response.statusCode}).',
        );
      }
    }
  }
}
