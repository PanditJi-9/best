import 'package:best_app/src/extension_host.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SourceSetting', () {
    test('labels a mirror by the entry that matches its value', () {
      final setting = SourceSetting.fromMap(<String, dynamic>{
        'key': 'preferred_mirror',
        'type': 'list',
        'title': 'الخادم البديل المفضل',
        'value': '2',
        'entries': ['mangalik.net', 'lekmanga.online', 'like-manga.net'],
        'entryValues': ['0', '1', '2'],
      });

      expect(setting.isList, isTrue);
      expect(setting.selectedLabel, 'like-manga.net');
    });

    test('a switch keeps a boolean as a string value', () {
      final setting = SourceSetting.fromMap(<String, dynamic>{
        'key': 'preferred_quality',
        'type': 'switch',
        'value': true,
      });

      expect(setting.isSwitch, isTrue);
      expect(setting.value, 'true');
    });

    test('a list with mismatched entries is never shown as a picker', () {
      final setting = SourceSetting.fromMap(<String, dynamic>{
        'key': 'broken',
        'type': 'list',
        'entries': ['only one'],
        'entryValues': ['1', '2'],
      });

      expect(setting.isList, isFalse);
    });

    test('a multi-select keeps every chosen value', () {
      final setting = SourceSetting.fromMap(<String, dynamic>{
        'key': 'languages',
        'type': 'multi',
        'values': ['ar', 'en'],
      });

      expect(setting.isMulti, isTrue);
      expect(setting.selectedLabel, 'ar, en');
    });
  });
}
