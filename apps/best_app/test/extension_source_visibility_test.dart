import 'package:best_app/src/extension_host.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('extensionSourceVisible', () {
    test('keeps the interface language and language-neutral bundles', () {
      expect(
        extensionSourceVisible(
            sourceLanguage: 'en',
            interfaceLanguage: 'en',
            packageSourceCount: 40),
        isTrue,
      );
      expect(
        extensionSourceVisible(
            sourceLanguage: 'all',
            interfaceLanguage: 'ar',
            packageSourceCount: 40),
        isTrue,
      );
    });

    test('hides one of forty language variants', () {
      expect(
        extensionSourceVisible(
            sourceLanguage: 'es',
            interfaceLanguage: 'en',
            packageSourceCount: 40),
        isFalse,
      );
    });

    test('keeps an explicitly activated single-source bundle', () {
      // Activating "مانجا ليك" with an English interface must not look like a
      // no-op: the bundle has exactly one source, so there is nothing to bury.
      expect(
        extensionSourceVisible(
            sourceLanguage: 'ar',
            interfaceLanguage: 'en',
            packageSourceCount: 1),
        isTrue,
      );
    });
  });
}
