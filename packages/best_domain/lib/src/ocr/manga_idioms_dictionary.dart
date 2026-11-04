/// Dictionary of Manga idioms, combat dialogue, common reactions, and gaming/manhwa status terms.
/// Ported from HikariManga 1.4.2.

class MangaIdiomsDictionary {
  MangaIdiomsDictionary._();
  static final MangaIdiomsDictionary instance = MangaIdiomsDictionary._();

  static final Map<String, String> standaloneIdioms = {
    "right": "معك حق",
    "right!": "معك حق!",
    "right?": "أليس كذلك؟",
    "right?!": "أليس كذلك؟!",
    "right!?": "أليس كذلك؟!",
    "right...": "صحيح...",
    "you're right": "معك حق",
    "you're right!": "معك حق!",
    "that's right": "هذا صحيح",
    "that's right!": "هذا صحيح!",
    "aw": "آه...",
    "awh": "آه...",
    "aww": "آه...",
    "heh": "هه...",
    "hah": "هاه...",
    "hmph": "همف...",
    "tch": "تش...",
    "phew": "ياه...",
    "whew": "ياه...",
    "tap": "*وقع أقدام*",
    "tap tap": "*خطوات*",
    "tap tap tap": "*خطوات*",
    "wha": "ماذا",
    "wha...": "ماذا...",
    "wha...?": "ماذا...؟",
    "wha?!": "ماذا؟! ",
    "wha!?": "ماذا!؟",
    "my gun": "مسدسي",
    "my gun!": "مسدسي!",
    "my weapon": "سلاحي",
    "my sword": "سيفي",
    "dig in": "تفضلوا بتناول الطعام!",
    "dig in!": "تفضلوا بتناول الطعام!",
    "come on, dig in": "هيا! تفضلوا بتناول الطعام!",
    "let's dig in": "لنبدأ بتناول الطعام!",
    "time to dig in": "حان وقت تناول الطعام!",
    "eat up": "تناولوا طعامكم بالهناء!",
    "help yourself": "تفضل على راحتك وتناول ما تحب!",
    "help yourselves": "تفضلوا على راحتكم جميعاً!",
    "bon appetit": "بالهناء والشفاء!",
    "it's on me": "الحساب على حسابي اليوم!",
    "my treat": "عزومتي اليوم!",
    "on the house": "ضيافة مجانية على حساب المحل!",
    "grab a bite": "نتناول وجبة سريعة",
    "bottoms up": "اشربوا حتى آخر قطرة!",
    "cheers": "في صحتكم!",
    "bring it on": "أرني ما لديك!",
    "bring it on!": "أرني ما لديك!",
    "give it your all": "ابذل كل ما تملك!",
    "give it all you've got": "قاتل بكل ما أوتيت من قوة!",
    "over my dead body": "على جثتي أولاً!",
    "in your dreams": "في أحلامك فقط!",
    "don't push your luck": "لا تتمادَ في غيك وتفرط في حظك!",
    "know your place": "اعرف قدرك ومكانتك!",
    "you're toast": "أنت هالك لا محالة!",
    "you're dead meat": "أنت في عداد الموتى!",
    "stay out of this": "ابقَ بعيداً ولا تتدخل!",
    "out of my way": "ابتعد عن طريقي!",
    "get lost": "اغرب عن وجهي!",
    "back off": "تراجع للخلف!",
    "hands off": "ابعد يديك!",
    "pay the price": "تدفع الثمن باهظاً!",
    "an eye for an eye": "العين بالعين والسن بالسن!",
    "you've got to be kidding me": "لا بد أنك تمزح!",
    "are you kidding me": "أأنت جاد فيما تقول؟ أم تمزح! ",
    "give me a break": "كفاك هراءً وارحمني!",
    "cut it out": "كف عن هذا السخف!",
    "knock it off": "توقف عن هذه الحماقة فوراً!",
    "not on my watch": "لن أسمح بهذا ما حييت!",
    "don't flatter yourself": "لا تغتر بنفسك!",
    "serves you right": "تستحق ما جرى لك تماماً!",
    "suit yourself": "افعل ما يحلو لك على راحتك!",
    "as if": "وكأن هذا سيحدث!",
    "what's gotten into you": "ما الذي دهاك وجرى لك؟",
    "for crying out loud": "يا إلهي كفانا!",
    "for heaven's sake": "بحق السماء!",
    "for god's sake": "بحق الجحيم!",
    "the coast is clear": "المكان آمن تماماً وخالٍ من الخطر!",
    "keep your voice down": "اخفض صوتك!",
    "keep it down": "اهدأوا واخفضوا أصواتكم!",
    "take your time": "خذ وقتك ولا تتعجل!",
    "no rush": "لا داعي للعجلة!",
    "no big deal": "أمر بسيط لا يستحق القلق!",
    "so what": "وماذا في ذلك؟! ",
    "say no more": "فهمت قصدك تماماً، لا تقل المزيد!",
    "just in case": "تحسباً لأي طارئ وللاحتياط!",
    "fair enough": "منطقي ومتفق عليه!",
    "fair and square": "بنزاهة وشرف تام!",
    "without a doubt": "بلا أدنى شك وبكل يقين!",
    "god": "يا إلهي",
    "oh god": "يا إلهي",
    "oh my god": "يا إلهي",
    "good god": "يا إلهي",
    "sheesh": "يا رجل...",
    "there you go": "ها هو ذا",
    "good game": "مباراة جيدة",
    "see you tomorrow": "أراك غداً",
    "off to bed": "ذاهب للنوم",
    "status window": "نافذة الحالة",
    "stat window": "نافذة الخصائص",
    "system window": "نافذة النظام",
    "level up": "ارتقاء في المستوى",
    "ranker": "مصنف",
    "high ranker": "مصنف رفيع المستوى",
    "mana core": "نواة المانا",
    "mana circulation": "دوران المانا",
    "qi deviation": "انحراف طاقة التشي",
    "dantian": "الدانتيان (مستودع الطاقة)",
    "dungeon break": "اجتياح الدهليز",
    "gate break": "انهيار البوابة",
    "death flag": "نذير شؤم وهلاك",
    "killing intent": "نية قتل صريحة",
    "bloodlust": "تعطش جارف للدماء",
    "spare my life": "اعفُ عني وأبقِ على حياتي",
    "show no mercy": "بلا أدنى رحمة",
    "out of mana": "استُنفدت المانا بالكامل",
    "skill tree": "شجرة المهارات",
    "awakened one": "مستيقظ",
    "hunter association": "نقابة الصيادين",
    "heavenly demon": "الشيطان السماوي",
    "mount hua sect": "طائفة جبل هوا",
    "wudang sect": "طائفة وودانغ",
    "shaolin temple": "معبد شاولين",
    "cultivation base": "قاعدة الصقل",
    "breakthrough": "اختراق حاجز القوة",
    "realm breakthrough": "اختراق المرحلة",
    "heavenly tribulation": "المحنة السماوية الرعدية",
    "spatial ring": "خاتم فراغي تخزيني",
    "storage ring": "خاتم تخزين مكاني",
    "party leader": "قائد الفريق",
    "raid party": "فريق المداهمة",
    "boss monster": "وحش الزعيم",
    "boss room": "غرفة الزعيم",
    "clear the dungeon": "تطهير الدهليز",
    "unique skill": "مهارة فريدة",
    "unique traits": "سمات فريدة",
    "die": "مُت!",
    "die!": "مُت!",
    "die!!": "مُت!!",
    "go die": "اذهب ومُت!",
    "just die": "فقط مُت!",
    "die already": "مُت بالفعل!",
    "die bastard": "مُت أيها اللعين!",
    "shut up": "اخرس",
    "shut your mouth": "اخرس فوراً",
    "are you out of your mind": "هل فقدت صوابك؟",
    "out of your mind": "فقدت عقلك وصوابك",
    "what the hell": "ما هذا بحق الجحيم",
    "what on earth": "ما هذا بحق السماء",
    "hang in there": "اصمد وتماسك",
    "now or never": "إما الآن أو أبداً",
    "none of your business": "ليس من شأنك في شيء",
    "mind your own business": "اهتم بشؤونك الخاصة",
    "at all costs": "مهما كلف الأمر وبأي ثمن",
    "point of no return": "نقطة اللاعودة",
    "in cold blood": "بدم بارد وبلا رحمة",
    "piece of cake": "أمر هين للغاية",
    "all of a sudden": "فجأة وبلا سابق إنذار",
    "out of the blue": "فجأة ومن حيث لا ندري",
    "behind the scenes": "وراء الكواليس في الخفاء",
  };

  static final List<MapEntry<RegExp, String>> machineTranslateReplacements = [
    MapEntry(RegExp(r'(?i)\bprivate\s+(park|kim|lee|choi|jung|kang|cho|yoon|jang|lim|han|oh|seo|shin|kwon|hwang|ahn|song|ryu|hong|bae|baek|nam|sim|ha|kwak|sung|cha|woo|jin|min)\b'), 'Soldier \$1'),
    MapEntry(RegExp(r'(?i)\bprivate,\s+'), 'Soldier, '),
    MapEntry(RegExp(r'(?i)\bprivate\s+first\s+class\b'), 'Soldier First Class'),
    MapEntry(RegExp(r'\bPrivate\s+([A-Z][a-zA-Z]+)\b'), 'Soldier \$1'),
    MapEntry(RegExp(r'(?i)\ba\s+vip\b'), 'a very important person'),
    MapEntry(RegExp(r'(?i)\bthe\s+vip\b'), 'the very important person'),
    MapEntry(RegExp(r'(?i)\bvips\b'), 'very important persons'),
    MapEntry(RegExp(r'(?i)\bvip\b'), 'very important person'),
    MapEntry(RegExp(r'(?i)\bget\s+off\s+my\s+ass\b'), 'leave me alone'),
    MapEntry(RegExp(r'(?i)\bsave\s+my\s+ass\b'), 'save my life'),
    MapEntry(RegExp(r'(?i)\bsave\s+(your|his|her|their)\s+ass\b'), 'save \$1 life'),
    MapEntry(RegExp(r'(?i)\bmy\s+ass\b'), 'my butt'),
    MapEntry(RegExp(r'(?i)\bis\s+an\s+understatement\b'), 'is far less than the truth'),
    MapEntry(RegExp(r'(?i)\b(come\s+on[!,]?\s*)?let\s*[''’]?s\s+dig\s+in\b'), 'let us start eating'),
    MapEntry(RegExp(r'(?i)\btime\s+to\s+dig\s+in\b'), 'time to start eating'),
    MapEntry(RegExp(r'(?i)\bcourting\s+death\b'), 'seeking death'),
    MapEntry(RegExp(r'(?i)\bstatus\s+window\b'), 'character status window'),
    MapEntry(RegExp(r'(?i)\blevel\s+up\b'), 'level increase'),
    MapEntry(RegExp(r'(?i)\bdungeon\s+break\b'), 'dungeon invasion'),
    MapEntry(RegExp(r'(?i)\bgate\s+break\b'), 'gate collapse'),
    MapEntry(RegExp(r'(?i)\bkilling\s+intent\b'), 'murderous aura'),
  ];

  static String normalizeIdiomKey(String key) {
    return key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  static final Map<String, String> _normalizedIdioms = {
    for (final entry in standaloneIdioms.entries)
      normalizeIdiomKey(entry.key): entry.value,
  };

  String? getDirectIdiomTranslation(String text) {
    final trimmed = text.trim();
    final lower = trimmed.toLowerCase();
    if (standaloneIdioms.containsKey(lower)) {
      return standaloneIdioms[lower];
    }
    final normalized = normalizeIdiomKey(trimmed);
    if (_normalizedIdioms.containsKey(normalized)) {
      return _normalizedIdioms[normalized];
    }
    return null;
  }

  String prepareTextForMachineTranslation(String text) {
    String prepared = text;
    for (final entry in machineTranslateReplacements) {
      prepared = prepared.replaceAllMapped(entry.key, (m) {
        String rep = entry.value;
        for (int i = 1; i <= m.groupCount; i++) {
          rep = rep.replaceAll('\$$i', m.group(i) ?? '');
        }
        return rep;
      });
    }
    return prepared;
  }
}
