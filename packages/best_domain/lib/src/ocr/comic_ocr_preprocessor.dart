/// Comic text preprocessor to clean common OCR artifacts, typos, speech stutters,
/// and homoglyphs. Ported from HikariManga 1.4.2.
library;

class ComicOcrPreprocessor {
  ComicOcrPreprocessor._();
  static final ComicOcrPreprocessor instance = ComicOcrPreprocessor._();

  static final List<MapEntry<RegExp, String>> ocrTypoFixes = [
    MapEntry(RegExp(r'\bhuman\s+biogs?\b', caseSensitive: false), 'human being'),
    MapEntry(RegExp(r'\bhuman\s+beogs?\b', caseSensitive: false), 'human being'),
    MapEntry(RegExp(r'\bhuman\s+byogs?\b', caseSensitive: false), 'human being'),
    MapEntry(RegExp(r'\bbiogs?\b', caseSensitive: false), 'being'),
    MapEntry(RegExp(r'\bbyog\b', caseSensitive: false), 'being'),
    MapEntry(RegExp(r'\bbeog\b', caseSensitive: false), 'being'),
    MapEntry(RegExp(r'\bran\s+your\s+moth(er)?\b', caseSensitive: false), 'ran your mouth'),
    MapEntry(RegExp(r'\brunning\s+your\s+moth(er)?\b', caseSensitive: false), 'running your mouth'),
    MapEntry(RegExp(r'\brun\s+your\s+moth(er)?\b', caseSensitive: false), 'run your mouth'),
    MapEntry(RegExp(r'\bshut\s+your\s+moth(er)?\b', caseSensitive: false), 'shut your mouth'),
    MapEntry(RegExp(r'\bwatch\s+your\s+moth(er)?\b', caseSensitive: false), 'watch your mouth'),
    MapEntry(RegExp(r'\bwatch\s+your\s+tongue\b', caseSensitive: false), 'watch your tongue'),
    MapEntry(RegExp(r'\bclorn\b', caseSensitive: false), 'clown'),
    MapEntry(RegExp(r'\bclead\b', caseSensitive: false), 'dead'),
    MapEntry(RegExp(r'\bmodem\b', caseSensitive: false), 'modern'),
    MapEntry(RegExp(r'\bdarnn\b', caseSensitive: false), 'damn'),
    MapEntry(RegExp(r'\bdamm\b', caseSensitive: false), 'damn'),
    MapEntry(RegExp(r'\bliell\b', caseSensitive: false), 'hell'),
    MapEntry(RegExp(r'\blieil\b', caseSensitive: false), 'hell'),
    MapEntry(RegExp(r'\bvvat\b', caseSensitive: false), 'what'),
    MapEntry(RegExp(r'\bvvh(y|o|ere|en)\b', caseSensitive: false), 'wh\$1'),
    MapEntry(RegExp(r'^\s*pie\s*(!+|\.{2,}|…|$)\s*', caseSensitive: false), 'die\$1'),
    MapEntry(RegExp(r'(?<=^|[\s"“\x27«(\[\r\n.!?…،,])pie\s*(!{1,4})', caseSensitive: false), 'die\$1'),
    MapEntry(RegExp(r'\b(just|go)\s+pie\b', caseSensitive: false), '\$1 die'),
    MapEntry(RegExp(r'\b(?:[1l|]\s+|m\s*y\s+)gun\b', caseSensitive: false), 'my gun'),
    MapEntry(RegExp(r'\b(?:[1l|]\s+|m\s*y\s+)guns\b', caseSensitive: false), 'my guns'),
    MapEntry(RegExp(r'\b(?:[1l|]\s+|m\s*y\s+)pistol\b', caseSensitive: false), 'my pistol'),
    MapEntry(RegExp(r'\b(?:[1l|]\s+|m\s*y\s+)weapon\b', caseSensitive: false), 'my weapon'),
    MapEntry(RegExp(r'\b(?:[1l|]\s+|m\s*y\s+)sword\b', caseSensitive: false), 'my sword'),
    MapEntry(RegExp(r"\bdon\s+t\b|\bdont\b|\bdon\s*['’`]\s*t\b", caseSensitive: false), "don't"),
    MapEntry(RegExp(r"\bcan\s+t\b|\bcant\b|\bcan\s*['’`]\s*t\b", caseSensitive: false), "can't"),
    MapEntry(RegExp(r"\bwon\s+t\b|\bwont\b|\bwon\s*['’`]\s*t\b", caseSensitive: false), "won't"),
    MapEntry(RegExp(r"\bi\s+m\b|\bi\s*['’`]\s*m\b", caseSensitive: false), "I'm"),
    MapEntry(RegExp(r"\bit\s+s\b|\bit\s*['’`]\s*s\b", caseSensitive: false), "it's"),
    MapEntry(RegExp(r"\byou\s+re\b|\byou\s*['’`]\s*re\b", caseSensitive: false), "you're"),
    MapEntry(RegExp(r"\bthey\s+re\b|\bthey\s*['’`]\s*re\b", caseSensitive: false), "they're"),
    MapEntry(RegExp(r"\bwe\s+re\b|\bwe\s*['’`]\s*re\b", caseSensitive: false), "we're"),
    MapEntry(RegExp(r"\bdidn\s+t\b|\bdidnt\b|\bdidn\s*['’`]\s*t\b", caseSensitive: false), "didn't"),
    MapEntry(RegExp(r"\bdoesn\s+t\b|\bdoesnt\b|\bdoesn\s*['’`]\s*t\b", caseSensitive: false), "doesn't"),
    MapEntry(RegExp(r"\bcouldn\s+t\b|\bcouldnt\b|\bcouldn\s*['’`]\s*t\b", caseSensitive: false), "couldn't"),
    MapEntry(RegExp(r"\bwouldn\s+t\b|\bwouldnt\b|\bwouldn\s*['’`]\s*t\b", caseSensitive: false), "wouldn't"),
    MapEntry(RegExp(r"\bshouldn\s+t\b|\bshouldnt\b|\bshouldn\s*['’`]\s*t\b", caseSensitive: false), "shouldn't"),
    MapEntry(RegExp(r"\bhasn\s+t\b|\bhasnt\b|\bhasn\s*['’`]\s*t\b", caseSensitive: false), "hasn't"),
    MapEntry(RegExp(r"\bhaven\s+t\b|\bhavent\b|\bhaven\s*['’`]\s*t\b", caseSensitive: false), "haven't"),
    MapEntry(RegExp(r"\bthat\s+s\b|\bthat\s*['’`]\s*s\b", caseSensitive: false), "that's"),
    MapEntry(RegExp(r"\bwhat\s+s\b|\bwhat\s*['’`]\s*s\b", caseSensitive: false), "what's"),
    MapEntry(RegExp(r"\bwho\s+s\b|\bwho\s*['’`]\s*s\b", caseSensitive: false), "who's"),
    MapEntry(RegExp(r"\blet\s+s\b|\blet\s*['’`]\s*s\b", caseSensitive: false), "let's"),
  ];

  static final RegExp stutterRegex = RegExp(
    r'\b([a-zA-Z]{1,2})(?:\s*[-–—―−_~〜～ー一\.]+\s*|\s*…\s*)+(?:[a-zA-Z]{1,2}(?:\s*[-–—―−_~〜～ー一\.]+\s*|\s*…\s*)+)*([a-zA-Z]{2,}(?:\x27[a-zA-Z]+)?)\b',
    caseSensitive: false,
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
