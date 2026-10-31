import 'dart:convert';

import 'package:best_data/best_data.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  group('SyncCipher', () {
    const passphrase = 'a long enough passphrase';
    const plaintext = '{"format":"best.library","version":2,"media":[]}';

    test('seals and opens a document', () async {
      final sealed = await SyncCipher.seal(
        plaintext: plaintext,
        passphrase: passphrase,
        iterations: 1000,
      );
      expect(sealed, isNot(contains('best.library')));
      expect(sealed, contains('"format": "best.sync"'));

      final opened = await SyncCipher.open(
        envelope: sealed,
        passphrase: passphrase,
      );
      expect(opened, plaintext);
    });

    test('a wrong passphrase is refused with a readable sentence', () async {
      final sealed = await SyncCipher.seal(
        plaintext: plaintext,
        passphrase: passphrase,
        iterations: 1000,
      );
      expect(
        () => SyncCipher.open(envelope: sealed, passphrase: 'wrong passphrase'),
        throwsA(
          isA<SyncException>().having(
            (error) => error.message,
            'message',
            contains('passphrase'),
          ),
        ),
      );
    });

    test('a tampered payload is refused', () async {
      final sealed = await SyncCipher.seal(
        plaintext: plaintext,
        passphrase: passphrase,
        iterations: 1000,
      );
      final document = jsonDecode(sealed) as Map<String, Object?>;
      final data = base64Decode(document['data']! as String);
      data[0] = data[0] ^ 0xff;
      document['data'] = base64Encode(data);

      expect(
        () => SyncCipher.open(
          envelope: jsonEncode(document),
          passphrase: passphrase,
        ),
        throwsA(isA<SyncException>()),
      );
    });

    test('a short passphrase is refused before any work is done', () async {
      expect(
        () => SyncCipher.seal(plaintext: plaintext, passphrase: 'short'),
        throwsA(isA<SyncException>()),
      );
    });

    test('something that is not a sync file is named as such', () async {
      expect(
        () => SyncCipher.open(envelope: '{"format":"other"}', passphrase: passphrase),
        throwsA(isA<SyncException>()),
      );
    });
  });

  group('WebDavSync', () {
    test('rejects a plain-http host that is not loopback', () {
      final client = MockClient((request) async => http.Response('', 200));
      expect(
        WebDavSync.fromSettings(
          url: 'http://cloud.example.com/backups',
          username: 'me',
          password: 'secret',
          client: client,
        ),
        isNull,
      );
      expect(
        WebDavSync.fromSettings(
          url: 'http://127.0.0.1:8080/dav',
          username: 'me',
          password: 'secret',
          client: client,
        ),
        isNotNull,
      );
    });

    test('uploads with basic auth and creates a missing folder once', () async {
      final seen = <String>[];
      var puts = 0;
      final client = MockClient((request) async {
        seen.add('${request.method} ${request.url}');
        if (request.method == 'PUT') {
          puts++;
          return http.Response('', puts == 1 ? 409 : 201);
        }
        return http.Response('', 201);
      });
      final sync = WebDavSync(
        baseUrl: Uri.parse('https://dav.example.com/backups'),
        username: 'me',
        password: 'secret',
        client: client,
      );

      await sync.upload('{"format":"best.sync"}');

      expect(puts, 2, reason: 'the first PUT learns the folder is missing');
      expect(
        seen.first,
        'PUT https://dav.example.com/backups/best-sync.json',
      );
      expect(seen, contains('MKCOL https://dav.example.com/backups/'));
    });

    test('download returns null when nothing is stored yet', () async {
      final client = MockClient((request) async => http.Response('', 404));
      final sync = WebDavSync(
        baseUrl: Uri.parse('https://dav.example.com/backups/'),
        username: 'me',
        password: 'secret',
        client: client,
      );
      expect(await sync.download(), isNull);
    });

    test('download returns the stored body', () async {
      final client = MockClient(
        (request) async => http.Response('{"format":"best.sync"}', 200),
      );
      final sync = WebDavSync(
        baseUrl: Uri.parse('https://dav.example.com/backups/'),
        username: 'me',
        password: 'secret',
        client: client,
      );
      expect(await sync.download(), '{"format":"best.sync"}');
    });
  });
}
