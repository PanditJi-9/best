import 'package:best_domain/best_domain.dart';
import 'package:test/test.dart';

void main() {
  const vtt = '''
WEBVTT

1
00:00:01.000 --> 00:00:03.500
First line
second line

00:00:04.000 --> 00:00:06.000
<i>Styled</i> &amp; escaped

2
00:00:07.000 --> 00:00:09.000
{\\an8}Top positioned
''';

  test('parses cues with their timing and text', () {
    final cues = Subtitles.parse(vtt);
    expect(cues, hasLength(3));
    expect(cues.first.start, const Duration(seconds: 1));
    expect(cues.first.end, const Duration(milliseconds: 3500));
    expect(cues.first.text, 'First line\nsecond line');
  });

  test('strips styling tags and unescapes entities', () {
    final cues = Subtitles.parse(vtt);
    expect(cues[1].text, 'Styled & escaped');
    expect(cues[2].text, 'Top positioned');
  });

  test('finds the cue at a position and nothing between cues', () {
    final cues = Subtitles.parse(vtt);
    expect(Subtitles.textAt(cues, const Duration(seconds: 2)), contains('First'));
    expect(Subtitles.textAt(cues, const Duration(milliseconds: 3900)), isNull);
  });

  test('accepts SRT commas', () {
    final cues = Subtitles.parse('1\n00:00:02,500 --> 00:00:04,000\nHello\n');
    expect(cues.single.start, const Duration(milliseconds: 2500));
    expect(cues.single.text, 'Hello');
  });

  test('a malformed file yields nothing instead of throwing', () {
    expect(Subtitles.parse('WEBVTT\n\nnot a cue\n'), isEmpty);
    expect(Subtitles.parse(''), isEmpty);
  });
}
