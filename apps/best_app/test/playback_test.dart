import 'package:best_app/src/labels.dart';
import 'package:best_app/src/navigation.dart';
import 'package:best_domain/best_domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the clock grows hours only when they exist', () {
    expect(formatClock(0), '0:00');
    expect(formatClock(65), '1:05');
    expect(formatClock(600), '10:00');
    expect(formatClock(3661), '1:01:01');
    expect(formatClock(-4), '0:00');
  });

  test('a watch route carries source, work and unit as query parameters', () {
    const media = Media(
      ref: SourceRef('guide', 'neon-seoul'),
      title: 'Neon Seoul',
      kind: MediaKind.drama,
    );
    const unit = MediaUnit(
      mediaId: 'guide::neon-seoul',
      url: 'unit-1',
      number: 1,
      title: 'Episode 1',
      kind: UnitKind.episode,
    );

    final uri = Uri.parse(Routes.watchOf(media, unit));
    expect(uri.path, '/watch');
    expect(uri.queryParameters['source'], 'guide');
    expect(uri.queryParameters['url'], 'neon-seoul');
    expect(uri.queryParameters['unit'], 'unit-1');
  });
}
