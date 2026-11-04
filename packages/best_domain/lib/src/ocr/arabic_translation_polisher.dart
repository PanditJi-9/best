/// Arabic translation polisher that cleans machine translation blunders,
/// enforces comic-appropriate phrasing, and formats punctuation for RTL Arabic.
/// Ported from HikariManga 1.4.2.
library;

class ArabicTranslationPolisher {
  ArabicTranslationPolisher._();
  static final ArabicTranslationPolisher instance = ArabicTranslationPolisher._();

  static final List<MapEntry<RegExp, String>> arabicPostPolish = [
    MapEntry(RegExp(r'^\s*(?:فطيرة|يموت)\s*(!+|\.{2,}|…|$)\s*'), 'مُت\$1'),
    MapEntry(RegExp(r'(?<=^|[\r\n])\s*(?:فطيرة|يموت)\s*(!+|\.{2,}|…|$)\s*'), 'مُت\$1'),
    MapEntry(RegExp(r'(?<=^|[\s"“\x27«(\[\r\n.!?…،,])(?:فطيرة|يموت)\s*(!{1,4})'), 'مُت\$1'),
    MapEntry(RegExp(r'(?<=^|[\s"“\x27«(\[\r\n.!?…،,])(?:اذهب\s+و)?يموت\s*(!{1,4})'), 'مُت\$1'),
    MapEntry(RegExp(r'^\s*بلدي\s*(!+|\?+|\.{2,}|…|$)\s*'), 'مؤخرتي\$1'),
    MapEntry(RegExp(r'(?<=^|[\r\n])\s*بلدي\s*(!+|\?+|\.{2,}|…|$)\s*'), 'مؤخرتي\$1'),
    MapEntry(RegExp(r'\b(في|يا|نعم[،,]\s*|مثل)\s+بلدي\s*(!+|\?+|$)'), '\$1 مؤخرتي\$2'),
    MapEntry(RegExp(r'(^|(?<=[.!?…\n،,:\s]))وا(?:\.{2,}|…|[-–—―]+)'), 'ماذا...'),
    MapEntry(RegExp(r'(^|(?<=[.!?…\n،,:\s]))وا([؟!?!]{1,3})'), 'ماذا\$1'),
    MapEntry(RegExp(r'(^|(?<=[.!?…\n،,:\s]))وا\s+(?=[\u0621-\u064A])'), 'ماذا... '),
    MapEntry(RegExp(r'\b(?:ماذا|وا)(?:\.{2,}|…|\s+)(?:[1l|I]\s+)?(?:غون|عون)\s*([؟!?!]*)'), 'ماذا... مسدسي\$1'),
    MapEntry(RegExp(r'(^|(?<=[.!?…\n،,:\s]))(?:[1l|I]\s+)?(?:غون|عون)\s*([؟!?!]+)'), 'مسدسي\$1'),
    MapEntry(RegExp(r'(^|(?<=[.!?…\n،,:\s]))(?:[1l|I]\s+)?(?:غون|عون)\s+(?=[\u0621-\u064A])'), 'مسدسي '),
    MapEntry(RegExp(r'(?<!إلى\s)(?<!على\s)(?<!عن\s)(?<!نحو\s)(?<!جهة\s)(?<!جانب\s)(?<!انعطف\s)(?<!أدر\s)(?<!تحرك\s)(?<!حلف\s)(?<!أقسم\s)(?:^|(?<=[.!?…\n،,:\s]))(?:\.{1,4}|…)?\s*يمين\s*(!+)'), 'معك حق\$1'),
    MapEntry(RegExp(r'(?<!إلى\s)(?<!على\s)(?<!عن\s)(?<!نحو\s)(?:^|(?<=[.!?…\n]))(?:\.{1,4}|…)?\s*يمين\s*([،,])'), 'معك حق\$1'),
    MapEntry(RegExp(r'(?<!إلى\s)(?<!على\s)(?<!عن\s)(?<!نحو\s)(?:[،,]\s*|\.{1,4}\s*|…\s*|^|\s)يمين\s*([؟?]+)'), '، أليس كذلك\$1'),
    MapEntry(RegExp(r'\b(صحيح|حقاً|حسناً)[،,\s]+يمين\s*([؟?]+)'), '\$1، أليس كذلك\$2'),
    MapEntry(RegExp(r'\bأنت\s+يمين\b'), 'أنت محق'),
    MapEntry(RegExp(r'\bأنتِ\s+يمين\b'), 'أنتِ محقة'),
    MapEntry(RegExp(r'\bأنتم\s+يمين\b'), 'أنتم محقون'),
    MapEntry(RegExp(r'\b(هو|إنه)\s+يمين\b'), '\$1 محق'),
    MapEntry(RegExp(r'\b(هي|إنها)\s+يمين\b'), '\$1 محقة'),
    MapEntry(RegExp(r'\b(أنا|إنني)\s+يمين\b'), '\$1 محق'),
    MapEntry(RegExp(r'\b(كنت|كان)\s+يمين\b'), '\$1 محقاً'),
    MapEntry(RegExp(r'\bكانت\s+يمين\b'), 'كانت محقة'),
    MapEntry(RegExp(r'\b(هذا|ذلك)\s+يمين\b'), '\$1 صحيح'),
    MapEntry(RegExp(r'\bليس\s+يمين\b'), 'ليس صحيحاً'),
    MapEntry(RegExp(r'\bأليس\s+(هذا\s+)?يمين\s*([؟?!]*)'), 'أليس هذا صحيحاً\$2'),
    MapEntry(RegExp(r'\bألست\s+يميناً\s*([؟?!]*)'), 'ألست محقاً\$1'),
    MapEntry(RegExp(r'\bكل\s+يمين\b'), 'كل شيء على ما يرام'),
    MapEntry(RegExp(r'\bيمين\s+الآن\b'), 'الآن فوراً'),
    MapEntry(RegExp(r'\bيمين\s+(هنا|هناك)\b'), '\$1 بالضبط'),
    MapEntry(RegExp(r'(?<=^|[\r\n.!?…،,:\s])(?:إله|اله)\s*(?:[.!?…،,]{1,4})\s*'), 'يا إلهي... '),
    MapEntry(RegExp(r'(?<=^|[\r\n.!?…،,:\s])(?:إلهي|الهي)\s*([.!?…،,]+)\s*'), 'يا إلهي\$1 '),
    MapEntry(RegExp(r'(?<=^|[\r\n\s])(?:إله|اله)\s*(!+|\?+)\s*'), 'يا إلهي\$1 '),
    MapEntry(RegExp(r'(?<=^|[\r\n.!?…،,:\s])شيش\s*(?:[.!?…،,]+|\s+)'), 'يا رجل، '),
    MapEntry(RegExp(r'(?<=^|[\s"“\x27«(\[\r\n.!?…،,])لا\s+تتصل\s+بي\s+(بـ?|كـ?|هكذا|بذلك)'), 'لا تنادني \$1'),
    MapEntry(RegExp(r'(?<=^|[\s"“\x27«(\[\r\n.!?…،,])لا\s+تتصل\s+بي\s+([أاإآ][\u0621-\u064A]+|سيد|سيدي|زعيم|ملك|قائد|بطل|أمير|حاكم|معلم|رئيس|شيطان|وحش)'), 'لا تنادني بـ\$1'),
    MapEntry(RegExp(r'(?<=^|[\s"“\x27«(\[\r\n.!?…،,])اتصل\s+بي\s+ب'), 'نادني ب'),
    MapEntry(RegExp(r'(?<=^|[\s"“\x27«(\[\r\n.!?…،,])اتصل\s+بي\s+([أاإآ][\u0621-\u064A]+|[a-zA-Z]+|سيد|سيدي|زعيم|ملك|قائد|بطل|أمير|حاكم|معلم|رئيس|شيطان|وحش)'), 'نادني \$1'),
    MapEntry(RegExp(r'(?<=^|[\s"“\x27«(\[\r\n.!?…،,])فقط\s+اتصل\s+بي\s+'), 'فقط نادني '),
    MapEntry(RegExp(r'(?<=^|[\s"“\x27«(\[\r\n.!?…،,])يمكنك\s+الاتصال\s+بي\s+'), 'يمكنك مناداتي '),
    MapEntry(RegExp(r'\bيعمل\s+(شخص[اًًا]|أحد[اًًا]|نفسه)?\s*حتى\s+العظم\b'), 'ينهك \$1 بالعمل الشاق'),
    MapEntry(RegExp(r'\bيعمل\s+حتى\s+العظم\b'), 'يكدح حتى الإنهاك'),
    MapEntry(RegExp(r'\bنافذة\s+الموقف\b'), 'نافذة الحالة'),
    MapEntry(RegExp(r'\bلب\s+المانا\b'), 'نواة المانا'),
    MapEntry(RegExp(r'\bاستراحة\s+الزنزانة\b'), 'اجتياح الدهليز'),
    MapEntry(RegExp(r'\bكسر\s+البوابة\b'), 'انهيار البوابة'),
    MapEntry(RegExp(r'\bعلم\s+الموت\b'), 'نذير الهلاك'),
    MapEntry(RegExp(r'\bتتودد\s+إلى\s+الموت\b'), 'تسعى لحتمك وهلاكك'),
    MapEntry(RegExp(r'\bيتودد\s+للموت\b'), 'يسعى لهلاكه'),
    MapEntry(RegExp(r'\bفكر،\s+رمادي\b'), 'فكر يا غراي'),
    MapEntry(RegExp(r'\b(الملك|باسم)\s+رمادي\b'), '\$1 غراي'),
    MapEntry(RegExp(r'\bملف(ات)?\s+تعريف\s+الارتباط\b'), 'بسكويت'),
    MapEntry(RegExp(r'\bوهناك\s+لديك\b'), 'ها هو ذا'),
    MapEntry(RegExp(r'\bحزمة\s+بين\s+عشية\s+وضحاها\b'), 'باقة المبيت'),
    MapEntry(RegExp(r'\bبين\s+عشية\s+وضحاها\b'), 'المبيت طوال الليل'),
    MapEntry(RegExp(r'\bقبالة\s+للنوم\b'), 'ذاهب للنوم'),
    MapEntry(RegExp(r'\bحديقة\s+خاصة،?\s*(اصعد|تحرك|تراجع|انتبه|اسمع|قف|تقدم|أسرع|قاتل|توقف|أيها|يا)\b'), 'الجندي بارك، \$1'),
    MapEntry(RegExp(r'\bحديقة\s+خاصة\b(?=،|\s*،)'), 'الجندي بارك'),
  ];

  static final Map<String, String> honorificsMap = {
    "-san": " سان",
    "-kun": " كون",
    "-chan": " تشان",
    "-sama": " ساما",
    "-senpai": " سينباي",
    "-sensei": " سينسي",
    " san": " سان",
    " kun": " كون",
    " chan": " تشان",
    " sama": " ساما",
    " senpai": " سينباي",
    " sensei": " سينسي",
  };

  String polishArabicTranslation(String arabicText) {
    String text = arabicText.trim();
    if (text.isEmpty) return text;

    for (final rule in arabicPostPolish) {
      text = text.replaceAllMapped(rule.key, (m) {
        String rep = rule.value;
        for (int i = 1; i <= m.groupCount; i++) {
          rep = rep.replaceAll('\$$i', m.group(i) ?? '');
        }
        return rep;
      });
    }

    // Replace Japanese honorifics
    for (final entry in honorificsMap.entries) {
      text = text.replaceAll(RegExp(RegExp.escape(entry.key), caseSensitive: false), entry.value);
    }

    // Fix RTL punctuation marks
    text = text
        .replaceAll('?', '؟')
        .replaceAll(',', '،')
        .replaceAll(';', '؛');

    // Clean duplicate punctuation
    text = text
        .replaceAll(RegExp(r'؟+'), '؟')
        .replaceAll(RegExp(r'!+'), '!')
        .replaceAll(RegExp(r'(\.){4,}'), '...');

    return text.trim();
  }
}
