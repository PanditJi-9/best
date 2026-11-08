import 'package:best_domain/best_domain.dart';
import 'package:test/test.dart';

void main() {
  test('a positive delay does not expose a cue before its shifted start', () {
    const cues = [SubtitleCue(start: Duration.zero, end: Duration(seconds: 2),
        text: 'Hello')];
    expect(Subtitles.textAt(cues,
        Subtitles.delayedPosition(const Duration(seconds: 1), 2000)), isNull);
    expect(Subtitles.textAt(cues,
        Subtitles.delayedPosition(const Duration(seconds: 3), 2000)), 'Hello');
  });

  test('ASS dialogue preserves commas and line breaks but not vector drawings', () {
    const raw = r'''[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:01.00,0:00:03.50,Default,,0,0,0,,{\i1}Hello, world\Nمرحبا
Dialogue: 0,0:00:04.00,0:00:05.00,Default,,0,0,0,,{\p1}m 0 0 l 20 20
''';
    final cues = Subtitles.parse(raw);
    expect(cues, hasLength(1));
    expect(cues.single.text, 'Hello, world\nمرحبا');
    expect(cues.single.end, const Duration(milliseconds: 3500));
  });
}
