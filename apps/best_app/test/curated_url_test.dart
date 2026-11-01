import 'dart:io';

import 'package:best_app/src/providers.dart';
import 'package:best_data/best_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the remote shelf URL points at the file this repo actually ships', () {
    // The repository root is the `mobile/` directory, so a path copied from the
    // workstation ("mobile/apps/...") answers 404 on GitHub and the app would
    // silently stay on its bundled copy forever. Resolve the URL against the
    // checkout instead of trusting the string.
    const prefix = 'https://raw.githubusercontent.com/';
    expect(kCuratedRemote, startsWith(prefix));

    final parts = kCuratedRemote.substring(prefix.length).split('/');
    // owner/repo/branch/...path
    expect(parts.length, greaterThan(3));
    final relative = parts.skip(3).join('/');

    // `flutter test` runs from apps/best_app, so the repository root — the
    // directory whose paths appear in the raw URL — is two levels up.
    final root = Directory.current.parent.parent.path;
    final file = File('$root/$relative');
    expect(
      file.existsSync(),
      isTrue,
      reason: '$kCuratedRemote resolves to "$relative", which is not in this '
          'checkout (root: $root).',
    );
    expect(CuratedList.parse(file.readAsStringSync()).picks, isNotEmpty);
  });
}
