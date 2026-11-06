import 'dart:convert';

import 'package:best_domain/best_domain.dart';
import 'package:test/test.dart';

void main() {
  test('a missing reader section keeps older backups compatible', () {
    final state = ReaderStateSnapshot.fromJson(null);
    expect(state.isEmpty, isTrue);
    expect(state.defaults, isNull);
    expect(state.bookmarkCount, 0);
  });

  test('defaults, work preferences and bookmarks survive JSON', () {
    const state = ReaderStateSnapshot(
      defaults: ReaderPreferences(direction: ReaderDirection.rtl),
      profiles: {'source::work': ReaderPreferences(mode: ReaderMode.vertical)},
      bookmarks: {
        'source::chapter': [2, 7]
      },
    );
    final restored =
        ReaderStateSnapshot.fromJson(jsonDecode(jsonEncode(state.toJson())));
    expect(restored.defaults, state.defaults);
    expect(restored.profiles, state.profiles);
    expect(restored.bookmarks, state.bookmarks);
    expect(restored.bookmarkCount, 2);
  });

  test('bookmarks merge by union without changing source page identities', () {
    const local = ReaderStateSnapshot(bookmarks: {
      'chapter-a': [2, 7],
      'chapter-b': [0],
    });
    const imported = ReaderStateSnapshot(bookmarks: {
      'chapter-a': [7, 1, 2],
      'chapter-c': [9],
    });
    final merged = local.merge(imported);
    expect(merged.bookmarks, {
      'chapter-a': [1, 2, 7],
      'chapter-b': [0],
      'chapter-c': [9],
    });
    expect(merged.bookmarkCount, 5);
    expect(local.bookmarks['chapter-a'], [2, 7]);
    expect(merged.merge(imported).bookmarks, merged.bookmarks);
  });

  test('existing local work styles win while missing ones are imported', () {
    const local = ReaderStateSnapshot(profiles: {
      'a': ReaderPreferences(direction: ReaderDirection.rtl),
    });
    const imported = ReaderStateSnapshot(profiles: {
      'a': ReaderPreferences(direction: ReaderDirection.ltr),
      'b': ReaderPreferences(mode: ReaderMode.vertical),
    });
    final merged = local.merge(imported);
    expect(merged.profiles['a']!.direction, ReaderDirection.rtl);
    expect(merged.profiles['b']!.mode, ReaderMode.vertical);
  });

  test('defaults are filled only when the local snapshot has no saved default',
      () {
    const imported = ReaderStateSnapshot(
      defaults: ReaderPreferences(direction: ReaderDirection.rtl),
    );
    expect(const ReaderStateSnapshot().merge(imported).defaults!.direction,
        ReaderDirection.rtl);
    const local = ReaderStateSnapshot(defaults: ReaderPreferences());
    expect(local.merge(imported).defaults!.direction, ReaderDirection.ltr);
  });

  test('imported page lists are sorted, deduplicated and immutable', () {
    final state = ReaderStateSnapshot.fromJson({
      'bookmarks': {
        'chapter': [7, 2, 7, 0]
      },
    });
    expect(state.bookmarks['chapter'], [0, 2, 7]);
    expect(() => state.bookmarks['chapter']!.add(1), throwsUnsupportedError);
    expect(() => state.profiles.clear(), throwsUnsupportedError);
  });

  test(
      'device settings and credentials cannot travel through reader preferences',
      () {
    final state = ReaderStateSnapshot.fromJson({
      'defaults': {
        'direction': 'rtl',
        'apiKey': 'sensitive',
        'biometricLockEnabled': false,
        'wifiOnly': false,
        'syncPassword': 'password',
      },
      'server': 'private-server',
    });
    final encoded = jsonEncode(state.toJson());
    expect(encoded, isNot(contains('sensitive')));
    expect(encoded, isNot(contains('Password')));
    expect(encoded, isNot(contains('biometric')));
    expect(encoded, isNot(contains('wifiOnly')));
    expect(encoded, isNot(contains('private-server')));
    expect(state.defaults!.direction, ReaderDirection.rtl);
  });

  test('malformed reader sections are rejected before any restore can write',
      () {
    for (final raw in <Object>[
      4,
      <Object?>[],
      {'defaults': <Object?>[]},
      {'profiles': <Object?>[]},
      {
        'profiles': {'work': 9}
      },
      {
        'profiles': {'': <String, Object?>{}}
      },
      {'bookmarks': <Object?>[]},
      {
        'bookmarks': {'chapter': 1}
      },
      {
        'bookmarks': {
          'chapter': [-1]
        }
      },
      {
        'bookmarks': {
          'chapter': [2.5]
        }
      },
      {
        'bookmarks': {
          'chapter': ['2']
        }
      },
      {
        'bookmarks': {
          '': [0]
        }
      },
    ]) {
      expect(() => ReaderStateSnapshot.fromJson(raw), throwsFormatException);
    }
  });
}
