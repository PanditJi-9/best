import 'dart:convert';

import 'package:best_data/best_data.dart';
import 'package:test/test.dart';

void main() {
  String document(Object? value) => jsonEncode(value);

  test('parses a shelf and keeps the order', () {
    final list = CuratedList.parse(
      document({
        'version': 1,
        'updated': '2026-11-01',
        'picks': [
          {'sourceId': 'mangadex', 'id': 'a'},
          {'sourceId': 'mangadex', 'id': 'b'},
        ],
      }),
    );

    expect(list.version, 1);
    expect(list.updated, '2026-11-01');
    expect(list.picks.map((pick) => pick.id), ['a', 'b']);
    expect(list.picks.first.sourceId, 'mangadex');
  });

  test('drops duplicate and incomplete entries instead of failing', () {
    final list = CuratedList.parse(
      document({
        'version': 1,
        'picks': [
          {'sourceId': 'mangadex', 'id': 'a'},
          {'sourceId': 'mangadex', 'id': 'a'},
          {'sourceId': 'mangadex'},
          {'id': 'b'},
          {'sourceId': '  ', 'id': 'c'},
          'not an object',
        ],
      }),
    );

    expect(list.picks, hasLength(1));
    expect(list.picks.single.id, 'a');
  });

  test('caps a document that pretends to be a database', () {
    final list = CuratedList.parse(
      document({
        'version': 1,
        'picks': [
          for (var i = 0; i < kMaxCuratedPicks + 10; i++)
            {'sourceId': 'mangadex', 'id': '$i'},
        ],
      }),
    );

    expect(list.picks, hasLength(kMaxCuratedPicks));
  });

  test('refuses a format from the future', () {
    expect(
      () => CuratedList.parse(document({'version': 2, 'picks': <Object>[]})),
      throwsA(isA<CuratedException>()),
    );
  });

  test('refuses a document without a picks array', () {
    expect(
      () => CuratedList.parse(document({'version': 1})),
      throwsA(isA<CuratedException>()),
    );
  });

  test('refuses invalid JSON and an empty document', () {
    expect(
      () => CuratedList.parse('{not json'),
      throwsA(isA<CuratedException>()),
    );
    expect(
      () => CuratedList.parse('   '),
      throwsA(isA<CuratedException>()),
    );
  });
}
