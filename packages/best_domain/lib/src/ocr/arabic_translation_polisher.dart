/// Arabic translation polisher that cleans machine translation blunders,
/// enforces comic-appropriate phrasing, and formats punctuation for RTL Arabic.
/// Ported from HikariManga 1.4.2.
library;

class ArabicTranslationPolisher {
  ArabicTranslationPolisher._();
  static final ArabicTranslationPolisher instance = ArabicTranslationPolisher._();

  static const _bStart = r'(?:^|(?<=[\s"“\x27«(\[\r\n.!?…،,:]))';
  static const _bEnd = r'(?:$|(?=[\s"“\x27«)\]\r\n.!?…،,:؟?]))';

  static final List<MapEntry<RegExp, String>> arabicPostPolish = [
    MapEntry(RegExp(r'^\s*(?:فطيرة|يموت)\s*(!+|\.{2,}|…|$)\s*'), 'مُت\$1'),
    MapEntry(RegExp(r'(?<=^|[\r\n])\s*(?:فطيرة|يموت)\s*(!+|\.{2,}|…|$)\s*'), 'مُت\$1'),
    MapEntry(RegExp(r'(?<=^|[\s"“\x27«(\[\r\n.!?…،,])(?:فطيرة|يموت)\s*(!{1,4})'), 'مُت\$1'),
    MapEntry(RegExp(r'(?<=^|[\s"“\x27«(\[\r\n.!?…،,])(?:اذهب\s+و)?يموت\s*(!{1,4})'), 'مُت\$1'),
    MapEntry(RegExp(r'^\s*بلدي\s*(!+|\?+|\.{2,}|…|$)\s*'), 'مؤخرتي\$1'),
    MapEntry(RegExp(r'(?<=^|[\r\n])\s*بلدي\s*(!+|\?+|\.{2,}|…|$)\s*'), 'مؤخرتي\$1'),
    MapEntry(RegExp('$_bStart(في|يا|نعم[،,]\\s*|مثل)\\s+بلدي\\s*(!+|\\?+|\$)'), '\$1 مؤخرتي\$2'),
    MapEntry(RegExp(r'(^|(?<=[.!?…\n،,:\s]))وا(?:\.{2,}|…|[-–—―]+)'), 'ماذا...'),
    MapEntry(RegExp(r'(^|(?<=[.!?…\n،,:\s]))وا([؟!?!]{1,3})'), 'ماذا\$1'),
    MapEntry(RegExp(r'(^|(?<=[.!?…\n،,:\s]))وا\s+(?=[\u0621-\u064A])'), 'ماذا... '),
    MapEntry(RegExp(r'(?:^|(?<=[\s.!?…،,]))(?:ماذا|وا)(?:\.{2,}|…|\s+)(?:[1l|I]\s+)?(?:غون|عون)\s*([؟!?!]*)'), 'ماذا... مسدسي\$1'),
    MapEntry(RegExp(r'(^|(?<=[.!?…\n،,:\s]))(?:[1l|I]\s+)?(?:غون|عون)\s*([؟!?!]+)'), 'مسدسي\$1'),
    MapEntry(RegExp(r'(^|(?<=[.!?…\n،,:\s]))(?:[1l|I]\s+)?(?:غون|عون)\s+(?=[\u0621-\u064A])'), 'مسدسي '),
    MapEntry(RegExp('$_bStartأنت\\s+يمين$_bEnd'), 'أنت محق'),
    MapEntry(RegExp('$_bStartأنتِ\\s+يمين$_bEnd'), 'أنتِ محقة'),
    MapEntry(RegExp('$_bStartأنتم\\s+يمين$_bEnd'), 'أنتم محقون'),
    MapEntry(RegExp('$_bStart(هو|إنه)\\s+يمين$_bEnd'), '\$1 محق'),
    MapEntry(RegExp('$_bStart(هي|إنها)\\s+يمين$_bEnd'), '\$1 محقة'),
    MapEntry(RegExp('$_bStart(أنا|إنني)\\s+يمين$_bEnd'), '\$1 محق'),
    MapEntry(RegExp('$_bStart(كنت|كان)\\s+يمين$_bEnd'), '\$1 محقاً'),
    MapEntry(RegExp('$_bStartكانت\\s+يمين$_bEnd'), 'كانت محقة'),
    MapEntry(RegExp('$_bStart(هذا|ذلك)\\s+يمين$_bEnd'), '\$1 صحيح'),
    MapEntry(RegExp('$_bStartليس\\s+يمين$_bEnd'), 'ليس صحيحاً'),
    MapEntry(RegExp('$_bStartأليس\\s+(هذا\\s+)?يمين\\s*([؟?!]*)$_bEnd'), 'أليس هذا صحيحاً\$2'),
    MapEntry(RegExp('$_bStartألست\\s+يميناً\\s*([؟?!]*)$_bEnd'), 'ألست محقاً\$1'),
    MapEntry(RegExp('$_bStartكل\\s+يمين$_bEnd'), 'كل شيء على ما يرام'),
    MapEntry(RegExp('$_bStartيمين\\s+الآن$_bEnd'), 'الآن فوراً'),
    MapEntry(RegExp('$_bStartيمين\\s+(هنا|هناك)$_bEnd'), '\$1 بالضبط'),
    MapEntry(RegExp('$_bStart(صحيح|حقاً|حسناً)[،,\\s]+يمين\\s*([؟?]+)'), '\$1، أليس كذلك\$2'),
    MapEntry(RegExp(r'(?<!إلى\s)(?<!على\s)(?<!عن\s)(?<!نحو\s)(?<!جهة\s)(?<!جانب\s)(?<!انعطف\s)(?<!أدر\s)(?<!تحرك\s)(?<!حلف\s)(?<!أقسم\s)(?:^|(?<=[.!?…\n،,:\s]))(?:\.{1,4}|…)?\s*يمين\s*(!+)'), 'معك حق\$1'),
    MapEntry(RegExp(r'(?<!إلى\s)(?<!على\s)(?<!عن\s)(?<!نحو\s)(?:^|(?<=[.!?…\n]))(?:\.{1,4}|…)?\s*يمين\s*([،,])'), 'معك حق\$1'),
    MapEntry(RegExp(r'(?<!إلى\s)(?<!على\s)(?<!عن\s)(?<!نحو\s)(?:[،,]\s*|\.{1,4}\s*|…\s*|^|\s)يمين\s*([؟?]+)'), '، أليس كذلك\$1'),
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
    MapEntry(RegExp('$_bStartيعمل\\s+(شخص[اًًا]|أحد[اًًا]|نفسه)?\\s*حتى\\s+العظم$_bEnd'), 'ينهك \$1 بالعمل الشاق'),
    MapEntry(RegExp('$_bStartيعمل\\s+حتى\\s+العظم$_bEnd'), 'يكدح حتى الإنهاك'),
    MapEntry(RegExp('$_bStartنافذة\\s+الموقف$_bEnd'), 'نافذة الحالة'),
    MapEntry(RegExp('$_bStartلب\\s+المانا$_bEnd'), 'نواة المانا'),
    MapEntry(RegExp('$_bStartاستراحة\\s+الزنزانة$_bEnd'), 'اجتياح الدهليز'),
    MapEntry(RegExp('$_bStartكسر\\s+البوابة$_bEnd'), 'انهيار البوابة'),
    MapEntry(RegExp('$_bStartعلم\\s+الموت$_bEnd'), 'نذير الهلاك'),
    MapEntry(RegExp('$_bStartتتودد\\s+إلى\\s+الموت$_bEnd'), 'تسعى لحتمك وهلاكك'),
    MapEntry(RegExp('$_bStartيتودد\\s+للموت$_bEnd'), 'يسعى لهلاكه'),
    MapEntry(RegExp('$_bStartفكر،\\s+رمادي$_bEnd'), 'فكر يا غراي'),
    MapEntry(RegExp('$_bStart(الملك|باسم)\\s+رمادي$_bEnd'), '\$1 غراي'),
    MapEntry(RegExp('$_bStartملف(ات)?\\s+تعريف\\s+الارتباط$_bEnd'), 'بسكويت'),
    MapEntry(RegExp('$_bStartوهناك\\s+لديك$_bEnd'), 'ها هو ذا'),
    MapEntry(RegExp('$_bStartحزمة\\s+بين\\s+عشية\\s+وضحاها$_bEnd'), 'باقة المبيت'),
    MapEntry(RegExp('$_bStartبين\\s+عشية\\s+وضحاها$_bEnd'), 'المبيت طوال الليل'),
    MapEntry(RegExp('$_bStartقبالة\\s+للنوم$_bEnd'), 'ذاهب للنوم'),
    MapEntry(RegExp('$_bStartحديقة\\s+خاصة،?\\s*(اصعد|تحرك|تراجع|انتبه|اسمع|قف|تقدم|أسرع|قاتل|توقف|أيها|يا)$_bEnd'), 'الجندي بارك، \$1'),
    MapEntry(RegExp('$_bStartحديقة\\s+خاصة(?=،|\\s*،|\$)'), 'الجندي بارك'),
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
