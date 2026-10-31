/// Subtitles, parsed here so the player only draws text.
///
/// WebVTT is the format every test stream and most sources ship, and it is a
/// superset of SRT's cue shape, so one parser covers both. Parsing is pure: a
/// malformed file yields an empty list, never an exception in the middle of a
/// film.
class SubtitleCue {
  const SubtitleCue({
    required this.start,
    required this.end,
    required this.text,
  });

  final Duration start;
  final Duration end;
  final String text;

  bool covers(Duration position) => position >= start && position < end;
}

class Subtitles {
  const Subtitles._();

  /// Parses WebVTT or SRT. Cue text keeps its line breaks, loses its styling
  /// tags, and unescapes the entities a subtitle file is allowed to use.
  static List<SubtitleCue> parse(String raw) {
    final text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final cues = <SubtitleCue>[];
    for (final block in text.split(RegExp(r'\n\s*\n'))) {
      final lines = block
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      if (lines.isEmpty) continue;

      final timing = _timing(lines);
      if (timing == null) continue;

      final body = lines
          .skip(timing.index + 1)
          .map(_clean)
          .where((line) => line.isNotEmpty)
          .join('\n');
      if (body.isEmpty) continue;

      cues.add(
        SubtitleCue(start: timing.start, end: timing.end, text: body),
      );
    }
    cues.sort((a, b) => a.start.compareTo(b.start));
    return List.unmodifiable(cues);
  }

  /// The line to show at [position], or `null` between cues.
  static String? textAt(Iterable<SubtitleCue> cues, Duration position) {
    for (final cue in cues) {
      if (cue.covers(position)) return cue.text;
    }
    return null;
  }

  static _Timing? _timing(List<String> lines) {
    for (var index = 0; index < lines.length && index < 2; index++) {
      final line = lines[index];
      final arrow = line.indexOf('-->');
      if (arrow < 0) continue;
      final start = _stamp(line.substring(0, arrow).trim());
      final endPart = line.substring(arrow + 3).trim().split(RegExp(r'\s+'));
      final end = endPart.isEmpty ? null : _stamp(endPart.first);
      if (start == null || end == null) return null;
      return _Timing(start, end, index);
    }
    return null;
  }

  static Duration? _stamp(String raw) {
    final cleaned = raw.replaceAll(',', '.');
    final parts = cleaned.split(':');
    if (parts.length < 2) return null;
    try {
      final secondsPart = parts.last.split('.');
      final seconds = int.parse(secondsPart.first);
      final millis = secondsPart.length > 1
          ? int.parse(secondsPart[1].padRight(3, '0').substring(0, 3))
          : 0;
      final minutes = int.parse(parts[parts.length - 2]);
      final hours = parts.length > 2 ? int.parse(parts[parts.length - 3]) : 0;
      return Duration(
        hours: hours,
        minutes: minutes,
        seconds: seconds,
        milliseconds: millis,
      );
    } on FormatException {
      return null;
    }
  }

  /// `<i>`, `{\an8}`, `{\pos(…)}` and friends are presentation, not words.
  static String _clean(String line) {
    return line
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll(RegExp(r'\{[^}]*\}'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ')
        .trim();
  }
}

class _Timing {
  const _Timing(this.start, this.end, this.index);

  final Duration start;
  final Duration end;

  /// Index of the timing line inside the block, so the body starts after it.
  final int index;
}
