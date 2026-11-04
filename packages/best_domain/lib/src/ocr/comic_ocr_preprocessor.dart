/// Comic text preprocessor to clean common OCR artifacts, typos, speech stutters,
/// and homoglyphs. Ported from HikariManga 1.4.2.

class ComicOcrPreprocessor {
  ComicOcrPreprocessor._();
  static final ComicOcrPreprocessor instance = ComicOcrPreprocessor._();

  static final List<MapEntry<RegExp, String>> ocrTypoFixes = [
    MapEntry(RegExp(r'(?i)\bhuman\s+biogs?\b'), 'human being'),
    MapEntry(RegExp(r'(?i)\bhuman\s+beogs?\b'), 'human being'),
    MapEntry(RegExp(r'(?i)\bhuman\s+byogs?\b'), 'human being'),
    MapEntry(RegExp(r'(?i)\bbiogs?\b'), 'being'),
    MapEntry(RegExp(r'(?i)\bbyog\b'), 'being'),
    MapEntry(RegExp(r'(?i)\bbeog\b'), 'being'),
    MapEntry(RegExp(r'(?i)\bran\s+your\s+moth(er)?\b'), 'ran your mouth'),
    MapEntry(RegExp(r'(?i)\brunning\s+your\s+moth(er)?\b'), 'running your mouth'),
    MapEntry(RegExp(r'(?i)\brun\s+your\s+moth(er)?\b'), 'run your mouth'),
    MapEntry(RegExp(r'(?i)\bshut\s+your\s+moth(er)?\b'), 'shut your mouth'),
    MapEntry(RegExp(r'(?i)\bwatch\s+your\s+moth(er)?\b'), 'watch your mouth'),
    MapEntry(RegExp(r'(?i)\bwatch\s+your\s+tongue\b'), 'watch your tongue'),
    MapEntry(RegExp(r'(?i)\bclorn\b'), 'clown'),
    MapEntry(RegExp(r'(?i)\bclead\b'), 'dead'),
    MapEntry(RegExp(r'(?i)\bmodem\b'), 'modern'),
    MapEntry(RegExp(r'(?i)\bdarnn\b'), 'damn'),
    MapEntry(RegExp(r'(?i)\bdamm\b'), 'damn'),
    MapEntry(RegExp(r'(?i)\bliell\b'), 'hell'),
    MapEntry(RegExp(r'(?i)\blieil\b'), 'hell'),
    MapEntry(RegExp(r'(?i)\bvvat\b'), 'what'),
    MapEntry(RegExp(r'(?i)\bvvh(y|o|ere|en)\b'), 'wh\$1'),
    MapEntry(RegExp(r'(?i)^\s*pie\s*(!+|\.{2,}|…|$)\s*'), 'die\$1'),
    MapEntry(RegExp(r'(?i)(?<=^|[\s"“\x27«(\[\r\n.!?…،,])pie\s*(!{1,4})'), 'die\$1'),
    MapEntry(RegExp(r'(?i)\b(just|go)\s+pie\b'), '\$1 die'),
    MapEntry(RegExp(r'(?i)\b(?:[1l|]\s+|m\s*y\s+)gun\b'), 'my gun'),
    MapEntry(RegExp(r'(?i)\b(?:[1l|]\s+|m\s*y\s+)guns\b'), 'my guns'),
    MapEntry(RegExp(r'(?i)\b(?:[1l|]\s+|m\s*y\s+)pistol\b'), 'my pistol'),
    MapEntry(RegExp(r'(?i)\b(?:[1l|]\s+|m\s*y\s+)weapon\b'), 'my weapon'),
    MapEntry(RegExp(r'(?i)\b(?:[1l|]\s+|m\s*y\s+)sword\b'), 'my sword'),
    MapEntry(RegExp(r"(?i)\bdon\s+t\b|\bdont\b|\bdon\s*['’`]\s*t\b"), "don't"),
    MapEntry(RegExp(r"(?i)\bcan\s+t\b|\bcant\b|\bcan\s*['’`]\s*t\b"), "can't"),
    MapEntry(RegExp(r"(?i)\bwon\s+t\b|\bwont\b|\bwon\s*['’`]\s*t\b"), "won't"),
    MapEntry(RegExp(r"(?i)\bi\s+m\b|\bi\s*['’`]\s*m\b"), "I'm"),
    MapEntry(RegExp(r"(?i)\bit\s+s\b|\bit\s*['’`]\s*s\b"), "it's"),
    MapEntry(RegExp(r"(?i)\byou\s+re\b|\byou\s*['’`]\s*re\b"), "you're"),
    MapEntry(RegExp(r"(?i)\bthey\s+re\b|\bthey\s*['’`]\s*re\b"), "they're"),
    MapEntry(RegExp(r"(?i)\bwe\s+re\b|\bwe\s*['’`]\s*re\b"), "we're"),
    MapEntry(RegExp(r"(?i)\bdidn\s+t\b|\bdidnt\b|\bdidn\s*['’`]\s*t\b"), "didn't"),
    MapEntry(RegExp(r"(?i)\bdoesn\s+t\b|\bdoesnt\b|\bdoesn\s*['’`]\s*t\b"), "doesn't"),
    MapEntry(RegExp(r"(?i)\bcouldn\s+t\b|\bcouldnt\b|\bcouldn\s*['’`]\s*t\b"), "couldn't"),
    MapEntry(RegExp(r"(?i)\bwouldn\s+t\b|\bwouldnt\b|\bwouldn\s*['’`]\s*t\b"), "wouldn't"),
    MapEntry(RegExp(r"(?i)\bshouldn\s+t\b|\bshouldnt\b|\bshouldn\s*['’`]\s*t\b"), "shouldn't"),
    MapEntry(RegExp(r"(?i)\bhasn\s+t\b|\bhasnt\b|\bhasn\s*['’`]\s*t\b"), "hasn't"),
    MapEntry(RegExp(r"(?i)\bhaven\s+t\b|\bhavent\b|\bhaven\s*['’`]\s*t\b"), "haven't"),
    MapEntry(RegExp(r"(?i)\bthat\s+s\b|\bthat\s*['’`]\s*s\b"), "that's"),
    MapEntry(RegExp(r"(?i)\bwhat\s+s\b|\bwhat\s*['’`]\s*s\b"), "what's"),
    MapEntry(RegExp(r"(?i)\bwho\s+s\b|\bwho\s*['’`]\s*s\b"), "who's"),
    MapEntry(RegExp(r"(?i)\blet\s+s\b|\blet\s*['’`]\s*s\b"), "let's"),
  ];

  static final RegExp stutterRegex = RegExp(
    r'(?i)\b([a-zA-Z]{1,2})(?:\s*[-–—―−_~〜～ー一\.]+\s*|\s*…\s*)+(?:[a-zA-Z]{1,2}(?:\s*[-–—―−_~〜～ー一\.]+\s*|\s*…\s*)+)*([a-zA-Z]{2,}(?:\x27[a-zA-Z]+)?)\b',
  );

  static final Map<int, String> homoglyphMap = {
    913: 'A', 914: 'B', 915: 'G', 916: 'D', 917: 'E', 918: 'Z',
    919: 'H', 920: 'T', 921: 'I', 922: 'K', 923: 'L', 924: 'M',
    925: 'N', 926: 'X', 927: 'O', 928: 'P', 929: 'R', 931: 'S',
    932: 'T', 933: 'Y', 934: 'F', 935: 'X', 936: 'P', 937: 'O',
    945: 'a', 946: 'b', 949: 'e', 953: 'i', 954: 'k', 957: 'v',
    959: 'o', 961: 'p', 964: 't', 965: 'u', 1040: 'A', 1042: 'B',
    1045: 'E', 1050: 'K', 1052: 'M', 1053: 'H', 1054: 'O', 1056: 'P',
    1057: 'C', 1058: 'T', 1059: 'Y', 1061: 'X', 1072: 'a', 1077: 'e',
    1086: 'o', 1088: 'p', 1089: 'c', 1091: 'y', 1093: 'x',
  };

  String normalizeHomoglyphs(String text) {
    final sb = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      if (homoglyphMap.containsKey(code)) {
        sb.write(homoglyphMap[code]);
      } else {
        sb.writeCharCode(code);
      }
    }
    return sb.toString();
  }

  bool hasLeadingStutter(String text) {
    final trimmed = text.trim();
    return stutterRegex.hasMatch(trimmed) && trimmed.indexOf(stutterRegex) == 0;
  }

  String cleanStutters(String text) {
    return text.replaceAllMapped(stutterRegex, (m) {
      final fullWord = m.group(2) ?? '';
      return fullWord;
    });
  }

  String applyArabicStutterToFirstWord(String arabicText) {
    final trimmed = arabicText.trim();
    if (trimmed.isEmpty) return arabicText;
    final words = trimmed.split(' ');
    if (words.isEmpty) return arabicText;
    final first = words[0];
    if (first.length <= 1) return arabicText;
    final stuttered = '${first[0]}...$first';
    return ([stuttered, ...words.skip(1)]).join(' ');
  }

  String cleanComicOcrText(String rawText) {
    String text = normalizeHomoglyphs(rawText);
    for (final fix in ocrTypoFixes) {
      text = text.replaceAllMapped(fix.key, (m) {
        String rep = fix.value;
        for (int i = 1; i <= m.groupCount; i++) {
          rep = rep.replaceAll('\$$i', m.group(i) ?? '');
        }
        return rep;
      });
    }
    // Clean up multiple hyphens or tildes used for comic stutters/shouts
    text = text.replaceAll(RegExp(r'[-–—―~]{2,}'), '-');
    return text.trim();
  }
}
