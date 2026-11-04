/// Comprehensive name transliteration engine for Manga, Manhwa, and Manhua names.
/// Ported from HikariManga 1.4.2.
library;

class TransliterationResult {
  const TransliterationResult({
    required this.original,
    required this.arabic,
    required this.confidence,
  });

  final String original;
  final String arabic;
  final String confidence;

  @override
  String toString() => 'TransliterationResult(original: $original, arabic: $arabic, confidence: $confidence)';
}

class ArabicNameTransliteration {
  ArabicNameTransliteration._();
  static final ArabicNameTransliteration instance = ArabicNameTransliteration._();

  static final RegExp _urlAndEmailRegex = RegExp(
    r'\b(?:https?://|ftp://|www\.)[^\s<>"{}|\\^`]+|(?:[a-zA-Z0-9-]+\.)+(?:com|org|net|io|me|to|co|app|gg|tv|site|xyz|online|club|top|cc|ru|fr|de|jp|kr|cn|us|info|mobi|dev|link|live|pro|space|vip|zone|art|press)(?:/[^\s<>"{}|\\^`]*)?|(?:discord\.(?:gg|com/invite)|t\.me|bit\.ly|linktr\.ee|patreon\.com|ko-fi\.com)/[^\s<>"{}|\\^`]+|[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}\b',
    caseSensitive: false,
  );

  static final Map<String, String> knownNames = {
    "naruto": "ناروتو",
    "sasuke": "ساسكي",
    "sakura": "ساكورا",
    "kakashi": "كاكاشي",
    "itachi": "إيتاتشي",
    "luffy": "لوفي",
    "zoro": "زورو",
    "sanji": "سانجي",
    "nami": "نامي",
    "goku": "غوكو",
    "vegeta": "فيجيتا",
    "ichigo": "إيتشيغو",
    "light": "لايت",
    "eren": "إيرين",
    "mikasa": "ميكاسا",
    "levi": "ليفاي",
    "tanjiro": "تانجيرو",
    "nezuko": "نيزوكو",
    "zenitsu": "زينيتسو",
    "inosuke": "إينوسكي",
    "gojo": "غوجو",
    "yuji": "يوجي",
    "megumi": "ميغومي",
    "denji": "دينجي",
    "power": "باور",
    "senku": "سينكو",
    "izuku": "إيزوكو",
    "deku": "ديكو",
    "bakugo": "باكوغو",
    "todoroki": "تودوروكي",
    "sukuna": "سوكونا",
    "yuta": "يوتا",
    "miku": "ميكو",
    "saitama": "سايتاما",
    "garou": "غارو",
    "jinwoo": "جين وو",
    "sung": "سونغ",
    "jin-woo": "جين وو",
    "cha": "تشا",
    "hae": "هاي",
    "min": "مين",
    "seo": "سيو",
    "yoon": "يون",
    "kang": "كانغ",
    "park": "بارك",
    "kim": "كيم",
    "lee": "لي",
    "choi": "تشوي",
    "jung": "جونغ",
    "han": "هان",
    "woo": "وو",
    "jin": "جين",
    "hyun": "هيون",
    "soo": "سو",
    "won": "وون",
    "jae": "جاي",
    "hoon": "هون",
    "hwan": "هوان",
    "ghun": "غون",
    "tae": "تاي",
    "guk": "غوك",
    "kuk": "غوك",
    "dokja": "دوكجا",
    "kirei": "كيري",
    "joonghyuk": "جونغهيوك",
    "sooyoung": "سويونغ",
    "wei": "وي",
    "wei-wuxian": "وي وو شيان",
    "lan": "لان",
    "wangji": "وانغجي",
    "xian": "شيان",
    "yun": "يون",
    "zhan": "جان",
    "chen": "تشين",
    "qing": "تشينغ",
    "shen": "شين",
    "feng": "فينغ",
    "xiao": "شياو",
    "ye": "يي",
    "long": "لونغ",
    "tian": "تيان",
    "hua": "هوا",
    "jun": "جون",
    "mei": "مي",
    "ling": "لينغ",
    "yan": "يان",
    "bai": "باي",
    "hei": "هي",
    "tang": "تانغ",
    "song": "سونغ",
    "xu": "شو",
    "zhao": "جاو",
    "liu": "ليو",
    "huang": "هوانغ",
    "wu": "وو",
    "zhang": "جانغ",
    "li": "لي",
    "wang": "وانغ",
    "yang": "يانغ",
    "zhou": "جو",
    "jiang": "جيانغ",
    "luo": "لوو",
    "qin": "تشين",
    "mo": "مو",
    "ran": "ران",
    "xie": "شيه",
    "lian": "ليان",
    "binghe": "بينغهي",
    "luo-binghe": "لوو بينغهي",
    "wuxian": "وو شيان",
    "chu": "تشو",
    "wenzhou": "وينجيو",
    "zhou-zishu": "جو زيشو",
    "kexing": "كيكسينغ",
    "arthur": "أرثر",
    "lucas": "لوكاس",
    "jack": "جاك",
    "john": "جون",
    "david": "ديفيد",
    "william": "ويليام",
    "thomas": "توماس",
    "james": "جيمس",
    "robert": "روبرت",
    "charles": "تشارلز",
    "michael": "مايكل",
    "daniel": "دانيال",
    "matthew": "ماتيو",
    "alexander": "ألكسندر",
    "edward": "إدوارد",
    "george": "جورج",
    "joseph": "جوزيف",
    "richard": "ريتشارد",
    "henry": "هنري",
    "brian": "برايان",
    "kevin": "كيفن",
    "jason": "جايسون",
    "ian": "إيان",
    "eric": "إيريك",
    "adam": "آدم",
    "luke": "لوك",
    "ryan": "رايان",
    "leo": "ليو",
    "oliver": "أوليفر",
    "noah": "نوح",
    "elijah": "إيليا",
    "liam": "ليام",
    "benjamin": "بنيامين",
    "lucian": "لوسيان",
    "lewis": "لويس",
    "samuel": "سامويل",
    "nathan": "ناثان",
    "christopher": "كريستوفر",
    "andrew": "أندرو",
    "simon": "سايمون",
    "peter": "بيتر",
    "paul": "بول",
    "mark": "مارك",
    "jonathan": "جوناثان",
    "adrian": "أدريان",
    "victor": "فيكتور",
    "vincent": "فينسنت",
    "felix": "فيليكس",
    "kurt": "كورت",
    "karl": "كارل",
    "albert": "ألبيرت",
    "louis": "لويس",
    "harry": "هاري",
    "bruce": "بروس",
    "clark": "كلارك",
    "raymond": "رايموند",
    "lawrence": "لورنس",
    "alan": "ألان",
    "roy": "روي",
    "elena": "إيلينا",
    "alice": "أليس",
    "mary": "ماري",
    "patricia": "باتريشيا",
    "jennifer": "جينيفير",
    "elizabeth": "إليزابيث",
    "linda": "ليندا",
    "barbara": "باربارا",
    "susan": "سوزان",
    "jessica": "جيسيكا",
    "sarah": "سارة",
    "karen": "كارن",
    "nancy": "نانسي",
    "lisa": "ليسا",
    "betty": "بيتي",
    "margaret": "مارغريت",
    "sandra": "ساندرا",
    "ashley": "أشلي",
    "kimberly": "كيمبرلي",
    "emily": "إيميلي",
    "donna": "دونا",
    "michelle": "ميشيل",
    "carol": "كارول",
    "amanda": "أماندا",
    "melissa": "ميليسا",
    "deborah": "ديبورا",
    "stephanie": "ستيفاني",
    "rebecca": "ريبكا",
    "sharon": "شارون",
    "laura": "لورا",
    "cynthia": "سينثيا",
    "kathleen": "كاثلين",
    "amy": "إيمي",
    "angela": "أنجيلا",
    "shirley": "شيرلي",
    "anna": "أنا",
    "brenda": "بريندا",
    "pamela": "باميلا",
    "nicole": "نيكول",
    "samantha": "سامانثا",
    "katherine": "كاثرين",
    "christine": "كريستين",
    "rachel": "راشيل",
    "catherine": "كاثرين",
    "virginia": "فيرجينيا",
    "debra": "ديبرا",
    "janet": "جانيت",
    "emma": "إيما",
    "olivia": "أوليفيا",
    "sophia": "صوفيا",
    "isabella": "إيزابيلا",
    "mia": "ميا",
    "charlotte": "شارلوت",
    "amelia": "أميليا",
    "harper": "هاربر",
    "evelyn": "إيفلين",
    "abigail": "أبيجيل",
    "clara": "كلارا",
    "lily": "ليلي",
    "chloe": "كلوي",
    "smith": "سميث",
    "jones": "جونز",
    "miller": "ميلر",
    "davis": "ديفيدز",
    "garcia": "غارسيا",
    "rodriguez": "رودريغيز",
    "wilson": "ويلسون",
    "martinez": "مارتينيز",
    "anderson": "أندرسون",
    "taylor": "تايلور",
    "moore": "مور",
    "jackson": "جاكسون",
    "martin": "مارتن",
    "perez": "بيريز",
    "thompson": "تومسون",
    "white": "وايت",
    "harris": "هاريس",
    "sanchez": "سانشيز",
    "ramirez": "راميريز",
    "robinson": "روبينسون",
    "walker": "واكر",
    "young": "يونغ",
    "allen": "ألان",
    "king": "كينغ",
    "wright": "رايت",
    "scott": "سكوت",
    "torres": "توريس",
    "nguyen": "نغوين",
    "hill": "هيل",
    "flores": "فلوريس",
    "green": "غرين",
    "adams": "أدامز",
    "nelson": "نيلسون",
    "baker": "بيكر",
    "hall": "هال",
    "rivera": "ريفيرا",
    "campbell": "كامبل",
    "mitchell": "ميتشيل",
    "carter": "كارتر",
    "roberts": "روبرتس",
    "gomez": "غوميز",
    "phillips": "فيليبس",
    "evans": "إيفانز",
    "turner": "تيرنر",
    "diaz": "دياز",
    "parker": "باركر",
    "lewin": "لوين",
    "leywin": "ليوين",
    "agris": "أغريس",
    "indrath": "إندراث",
    "greymore": "غريغور",
    "grey": "غراي",
    "rey": "ري",
    "dicathen": "ديكاثين",
    "sapin": "سابين",
    "elenoir": "إلينوار",
  };

  static final List<MapEntry<String, String>> japaneseSyllables = [
    MapEntry("shio", "شيو"), MapEntry("shia", "شيا"), MapEntry("shiu", "شيو"),
    MapEntry("chi", "تشي"), MapEntry("shi", "شي"), MapEntry("tsu", "تسو"),
    MapEntry("kya", "كيا"), MapEntry("kyu", "كيو"), MapEntry("kyo", "كيو"),
    MapEntry("sha", "شا"), MapEntry("shu", "شو"), MapEntry("sho", "شو"),
    MapEntry("cha", "تشا"), MapEntry("chu", "تشو"), MapEntry("cho", "تشو"),
    MapEntry("nya", "نيا"), MapEntry("nyu", "نيو"), MapEntry("nyo", "نيو"),
    MapEntry("hya", "هيا"), MapEntry("hyu", "هيو"), MapEntry("hyo", "هيو"),
    MapEntry("mya", "ميا"), MapEntry("myu", "ميو"), MapEntry("myo", "ميو"),
    MapEntry("rya", "ريا"), MapEntry("ryu", "ريو"), MapEntry("ryo", "ريو"),
    MapEntry("gya", "غيا"), MapEntry("gyu", "غيو"), MapEntry("gyo", "غيو"),
    MapEntry("jya", "جيا"), MapEntry("byo", "بيو"), MapEntry("pyo", "بيو"),
    MapEntry("ka", "كا"), MapEntry("ki", "كي"), MapEntry("ku", "كو"),
    MapEntry("ke", "كي"), MapEntry("ko", "كو"), MapEntry("sa", "سا"),
    MapEntry("su", "سو"), MapEntry("se", "سي"), MapEntry("so", "سو"),
    MapEntry("ta", "تا"), MapEntry("ti", "تي"), MapEntry("to", "تو"),
    MapEntry("na", "نا"), MapEntry("ni", "ني"), MapEntry("nu", "نو"),
    MapEntry("ne", "ني"), MapEntry("no", "نو"), MapEntry("ha", "ها"),
    MapEntry("hi", "هي"), MapEntry("fu", "فو"), MapEntry("he", "هي"),
    MapEntry("ho", "هو"), MapEntry("ma", "ما"), MapEntry("mi", "مي"),
    MapEntry("mu", "مو"), MapEntry("me", "مي"), MapEntry("mo", "مو"),
    MapEntry("ya", "يا"), MapEntry("yu", "يو"), MapEntry("yo", "يو"),
    MapEntry("ra", "را"), MapEntry("ri", "ري"), MapEntry("ru", "رو"),
    MapEntry("re", "ري"), MapEntry("ro", "رو"), MapEntry("wa", "وا"),
    MapEntry("wo", "وو"), MapEntry("ga", "غا"), MapEntry("gi", "غي"),
    MapEntry("gu", "غو"), MapEntry("ge", "غي"), MapEntry("go", "غو"),
    MapEntry("za", "زا"), MapEntry("ji", "جي"), MapEntry("zu", "زو"),
    MapEntry("ze", "زي"), MapEntry("zo", "زو"), MapEntry("da", "دا"),
    MapEntry("di", "دي"), MapEntry("du", "دو"), MapEntry("de", "دي"),
    MapEntry("do", "دو"), MapEntry("ba", "با"), MapEntry("bi", "بي"),
    MapEntry("bu", "بو"), MapEntry("be", "بي"), MapEntry("bo", "بو"),
    MapEntry("pa", "با"), MapEntry("pi", "بي"), MapEntry("pu", "بو"),
    MapEntry("pe", "بي"), MapEntry("po", "بو"), MapEntry("a", "ا"),
    MapEntry("i", "ي"), MapEntry("u", "و"), MapEntry("e", "ي"),
    MapEntry("o", "و"), MapEntry("n", "ن"),
  ];

  static final List<MapEntry<String, String>> koreanPatterns = [
    MapEntry("hwan", "هوان"), MapEntry("gwan", "غوان"), MapEntry("kwan", "كوان"),
    MapEntry("cheo", "تشو"), MapEntry("jyeo", "جيو"), MapEntry("shyeo", "شيو"),
    MapEntry("eok", "وك"), MapEntry("eong", "ونغ"), MapEntry("yeong", "يونغ"),
    MapEntry("myeong", "ميونغ"), MapEntry("hyeon", "هيون"), MapEntry("gyeong", "غيونغ"),
    MapEntry("jeong", "جونغ"), MapEntry("eo", "أو"), MapEntry("eu", "و"),
    MapEntry("ae", "يه"), MapEntry("oo", "و"), MapEntry("ui", "وي"),
    MapEntry("ng", "نغ"), MapEntry("yeo", "يو"), MapEntry("ya", "يا"),
    MapEntry("yo", "يو"), MapEntry("yu", "يو"), MapEntry("ch", "تش"),
    MapEntry("g", "غ"), MapEntry("j", "ج"),
  ];

  static final List<MapEntry<String, String>> chinesePatterns = [
    MapEntry("xiong", "شيونغ"), MapEntry("qiong", "تشيونغ"), MapEntry("shuang", "شوانغ"),
    MapEntry("huang", "هوانغ"), MapEntry("zhuang", "جوانغ"), MapEntry("chuang", "تشوانغ"),
    MapEntry("xiang", "شيانغ"), MapEntry("zhi", "جي"), MapEntry("chi", "تشي"),
    MapEntry("shi", "شي"), MapEntry("zhu", "جو"), MapEntry("chu", "تشو"),
    MapEntry("shu", "شو"), MapEntry("zhe", "جي"), MapEntry("che", "تشي"),
    MapEntry("she", "شي"), MapEntry("zha", "جا"), MapEntry("cha", "تشا"),
    MapEntry("sha", "شا"), MapEntry("zho", "جو"), MapEntry("cho", "تشو"),
    MapEntry("sho", "شو"), MapEntry("xia", "شيا"), MapEntry("xie", "شيه"),
    MapEntry("xiu", "شيو"), MapEntry("xin", "شين"), MapEntry("xing", "شينغ"),
    MapEntry("xu", "شو"), MapEntry("xian", "شيان"), MapEntry("qia", "تشيا"),
    MapEntry("qie", "شيه"), MapEntry("qin", "تشين"), MapEntry("qing", "تشينغ"),
    MapEntry("qian", "تشيان"), MapEntry("qu", "تشو"), MapEntry("jia", "جيا"),
    MapEntry("jie", "جيه"), MapEntry("jin", "جين"), MapEntry("jing", "جينغ"),
    MapEntry("jian", "جيان"), MapEntry("ju", "جو"), MapEntry("ang", "انغ"),
    MapEntry("eng", "ينغ"), MapEntry("ong", "ونغ"), MapEntry("ing", "ينغ"),
    MapEntry("ai", "اي"), MapEntry("ao", "او"), MapEntry("ei", "ي"),
    MapEntry("ou", "و"), MapEntry("an", "ان"), MapEntry("en", "ين"),
    MapEntry("in", "ين"), MapEntry("un", "ون"), MapEntry("er", "إير"),
    MapEntry("ba", "با"), MapEntry("bi", "بي"), MapEntry("bu", "بو"),
    MapEntry("bo", "بو"), MapEntry("bai", "باي"), MapEntry("pa", "با"),
    MapEntry("pi", "بي"), MapEntry("pu", "بو"), MapEntry("po", "بو"),
    MapEntry("ma", "ما"), MapEntry("mi", "مي"), MapEntry("mu", "مو"),
    MapEntry("mo", "مو"), MapEntry("mei", "مي"), MapEntry("fa", "فا"),
    MapEntry("fu", "فو"), MapEntry("fo", "فو"), MapEntry("da", "دا"),
    MapEntry("de", "دي"), MapEntry("di", "دي"), MapEntry("du", "دو"),
    MapEntry("dao", "داو"), MapEntry("ta", "تا"), MapEntry("te", "تي"),
    MapEntry("ti", "تي"), MapEntry("tu", "تو"), MapEntry("na", "نا"),
    MapEntry("ne", "ني"), MapEntry("ni", "ني"), MapEntry("nu", "نو"),
    MapEntry("la", "لا"), MapEntry("le", "لي"), MapEntry("li", "لي"),
    MapEntry("lu", "لو"), MapEntry("lo", "لو"), MapEntry("ga", "غا"),
    MapEntry("ge", "غي"), MapEntry("gu", "غو"), MapEntry("gao", "غاو"),
    MapEntry("ka", "كا"), MapEntry("ke", "كي"), MapEntry("ku", "كو"),
    MapEntry("ha", "ها"), MapEntry("he", "هي"), MapEntry("ho", "هو"),
    MapEntry("hua", "هوا"), MapEntry("ya", "يا"), MapEntry("ye", "يه"),
    MapEntry("yu", "يو"), MapEntry("yun", "يون"), MapEntry("yan", "يان"),
    MapEntry("yang", "يانغ"), MapEntry("wa", "وا"), MapEntry("wu", "وو"),
    MapEntry("wan", "وان"), MapEntry("wang", "وانغ"), MapEntry("wei", "وي"),
    MapEntry("ru", "رو"), MapEntry("ren", "رين"), MapEntry("rong", "رونغ"),
    MapEntry("ri", "ري"), MapEntry("zi", "زي"), MapEntry("ze", "زي"),
    MapEntry("zu", "زو"), MapEntry("zong", "زونغ"), MapEntry("ci", "تسي"),
    MapEntry("ce", "تسي"), MapEntry("cu", "تسو"), MapEntry("cong", "تسونغ"),
    MapEntry("si", "سي"), MapEntry("se", "سي"), MapEntry("su", "سو"),
    MapEntry("song", "سونغ"), MapEntry("x", "ش"), MapEntry("q", "تش"),
    MapEntry("c", "تسي"), MapEntry("z", "ج"), MapEntry("a", "ا"),
    MapEntry("e", "ي"), MapEntry("i", "ي"), MapEntry("o", "و"), MapEntry("u", "و"),
  ];

  static final List<MapEntry<String, String>> westernPatterns = [
    MapEntry("tion", "شن"), MapEntry("sion", "شن"), MapEntry("ph", "ف"),
    MapEntry("sh", "ش"), MapEntry("ch", "تش"), MapEntry("th", "ث"),
    MapEntry("gh", "غ"), MapEntry("kh", "خ"), MapEntry("wh", "و"),
    MapEntry("ck", "ك"), MapEntry("kn", "ن"), MapEntry("ee", "ي"),
    MapEntry("ea", "ي"), MapEntry("oo", "و"), MapEntry("ou", "و"),
    MapEntry("oi", "وي"), MapEntry("ay", "ي"), MapEntry("ey", "ي"),
    MapEntry("au", "و"), MapEntry("aw", "و"), MapEntry("ai", "اي"),
    MapEntry("oa", "و"), MapEntry("ie", "ي"), MapEntry("ius", "يوس"),
    MapEntry("us", "وس"), MapEntry("er", "ير"), MapEntry("or", "ور"),
    MapEntry("an", "ان"), MapEntry("am", "ام"), MapEntry("al", "ال"),
    MapEntry("en", "ين"), MapEntry("el", "يل"), MapEntry("on", "ون"),
    MapEntry("ar", "ار"), MapEntry("at", "ات"), MapEntry("ba", "با"),
    MapEntry("bi", "بي"), MapEntry("bu", "بو"), MapEntry("be", "بي"),
    MapEntry("bo", "بو"), MapEntry("ca", "كا"), MapEntry("ci", "سي"),
    MapEntry("cu", "كو"), MapEntry("ce", "سي"), MapEntry("co", "كو"),
    MapEntry("da", "دا"), MapEntry("di", "دي"), MapEntry("du", "دو"),
    MapEntry("de", "دي"), MapEntry("do", "دو"), MapEntry("fa", "فا"),
    MapEntry("fi", "في"), MapEntry("fu", "فو"), MapEntry("fe", "في"),
    MapEntry("fo", "فو"), MapEntry("ga", "غا"), MapEntry("gi", "جي"),
    MapEntry("gu", "غو"), MapEntry("ge", "جي"), MapEntry("go", "غو"),
    MapEntry("ha", "ها"), MapEntry("hi", "هي"), MapEntry("hu", "هو"),
    MapEntry("he", "هي"), MapEntry("ho", "هو"), MapEntry("ja", "جا"),
    MapEntry("ji", "جي"), MapEntry("ju", "جو"), MapEntry("je", "جي"),
    MapEntry("jo", "جو"), MapEntry("ka", "كا"), MapEntry("ki", "كي"),
    MapEntry("ku", "كو"), MapEntry("ke", "كي"), MapEntry("ko", "كو"),
    MapEntry("la", "لا"), MapEntry("li", "لي"), MapEntry("lu", "لو"),
    MapEntry("le", "لي"), MapEntry("lo", "لو"), MapEntry("ma", "ما"),
    MapEntry("mi", "مي"), MapEntry("mu", "مو"), MapEntry("me", "مي"),
    MapEntry("mo", "مو"), MapEntry("na", "نا"), MapEntry("ni", "ني"),
    MapEntry("nu", "نو"), MapEntry("ne", "ني"), MapEntry("no", "نو"),
    MapEntry("pa", "با"), MapEntry("pi", "بي"), MapEntry("pu", "بو"),
    MapEntry("pe", "بي"), MapEntry("po", "بو"), MapEntry("ra", "را"),
    MapEntry("ri", "ري"), MapEntry("ru", "رو"), MapEntry("re", "ري"),
    MapEntry("ro", "رو"), MapEntry("sa", "سا"), MapEntry("si", "سي"),
    MapEntry("su", "سو"), MapEntry("se", "سي"), MapEntry("so", "سو"),
    MapEntry("ta", "تا"), MapEntry("ti", "تي"), MapEntry("tu", "تو"),
    MapEntry("te", "تي"), MapEntry("to", "تو"), MapEntry("va", "فا"),
    MapEntry("vi", "في"), MapEntry("vu", "فو"), MapEntry("ve", "في"),
    MapEntry("vo", "فو"), MapEntry("wa", "وا"), MapEntry("wi", "وي"),
    MapEntry("wu", "و"), MapEntry("we", "وي"), MapEntry("wo", "و"),
    MapEntry("za", "زا"), MapEntry("zi", "زي"), MapEntry("zu", "زو"),
    MapEntry("ze", "زي"), MapEntry("zo", "زو"), MapEntry("c", "ك"),
    MapEntry("j", "ج"), MapEntry("x", "كس"), MapEntry("q", "ك"),
    MapEntry("v", "ف"), MapEntry("a", "ا"), MapEntry("e", "ي"),
    MapEntry("i", "ي"), MapEntry("o", "و"), MapEntry("u", "و"),
    MapEntry("b", "ب"), MapEntry("d", "د"), MapEntry("f", "ف"),
    MapEntry("g", "غ"), MapEntry("h", "هـ"), MapEntry("k", "ك"),
    MapEntry("l", "ل"), MapEntry("m", "م"), MapEntry("n", "ن"),
    MapEntry("p", "ب"), MapEntry("r", "ر"), MapEntry("s", "س"),
    MapEntry("t", "ت"), MapEntry("w", "و"), MapEntry("z", "ز"), MapEntry("y", "ي"),
  ];

  static final Set<String> commonEnglishWords = {
    "the", "be", "to", "of", "and", "a", "in", "that", "have", "i", "it", "for",
    "not", "on", "with", "he", "as", "you", "do", "at", "this", "but", "his",
    "by", "from", "they", "we", "say", "her", "she", "or", "an", "will", "my",
    "one", "all", "would", "there", "their", "what", "so", "up", "out", "if",
    "about", "who", "get", "which", "go", "me", "when", "make", "can", "like",
    "time", "no", "just", "him", "know", "take", "people", "into", "year",
    "your", "good", "some", "could", "them", "see", "other", "than", "then",
    "now", "look", "only", "come", "its", "over", "think", "also", "back",
    "after", "use", "two", "how", "our", "work", "first", "well", "way",
    "even", "new", "want", "because", "any", "these", "give", "day", "most",
    "us", "is", "am", "are", "was", "were", "been", "has", "had", "did",
    "does", "doing", "win", "wins", "winner", "loss", "losses", "lost", "kill",
    "kills", "killed", "dead", "die", "death", "game", "games", "gaming",
    "play", "player", "playing", "room", "lobby", "pass", "password", "stream",
    "streamer", "streaming", "live", "chat", "host", "boss", "quest", "level",
    "lvl", "exp", "hp", "mp", "sp", "ap", "dps", "pvp", "pve", "rank",
    "ranking", "solo", "duo", "trio", "squad", "party", "guild", "clan",
    "buff", "debuff", "heal", "healer", "tank", "carry", "gg", "wp", "gl",
    "hf", "afk", "npc", "mob", "drop", "item", "inventory", "skill", "stat",
    "stats", "atk", "def", "speed", "crit", "mana", "stamina", "cooldown",
    "cd", "ultimate", "ult", "gun", "guns", "pistol", "pistols", "rifle",
    "rifles", "bullet", "bullets", "shotgun", "weapon", "weapons", "sword",
    "swords", "blade", "blades", "knife", "shield", "armor", "sub", "subs",
    "subscribe", "subscribers", "follow", "followers", "view", "viewer",
    "viewers", "cookie", "cookies", "biscuit", "biscuits", "snack", "snacks",
    "cake", "candy", "food", "coffee", "tea", "water", "milk", "drink",
    "drinks", "shift", "night", "overnight", "pack", "package", "plan",
    "booth", "seat", "id", "card", "age", "check", "customer", "regular",
    "young", "boy", "girl", "kid", "man", "woman", "person",
    "anime", "manga", "comic", "voice", "sound", "sounds", "music", "song",
    "video", "screen", "phone", "pc", "tv"
  };

  bool isUrlOrDomain(String text) {
    return _urlAndEmailRegex.hasMatch(text);
  }

  bool shouldTransliterateWord(String word, [bool isInsideArabicContext = false]) {
    final trimmed = word.trim();
    if (trimmed.length <= 2) return false;
    for (int i = 0; i < trimmed.length; i++) {
      final code = trimmed.codeUnitAt(i);
      if (code >= 48 && code <= 57) return false; // Contains digits
    }
    final lower = trimmed.toLowerCase().replaceAll(RegExp(r'[^a-z-]'), '');
    if (lower.isEmpty) return false;
    if (knownNames.containsKey(lower)) return true;
    if (commonEnglishWords.contains(lower)) return false;
    if (isInsideArabicContext) return true;
    return trimmed[0].toUpperCase() == trimmed[0];
  }

  TransliterationResult transliterateArabicName(String? name, [String? origin]) {
    if (name == null || name.trim().isEmpty) {
      return TransliterationResult(original: name ?? "", arabic: name ?? "", confidence: "low");
    }
    final trimmed = name.trim();
    final lower = trimmed.toLowerCase().replaceAll(RegExp(r'[^a-z-]'), '');
    if (knownNames.containsKey(lower)) {
      return TransliterationResult(
        original: trimmed,
        arabic: knownNames[lower]!,
        confidence: "exact_match",
      );
    }
    final phonetic = _applyPhoneticFallback(lower, origin);
    return TransliterationResult(
      original: trimmed,
      arabic: phonetic,
      confidence: "phonetic",
    );
  }

  String transliterateRemainingEnglishWords(String text, [String? origin]) {
    if (isUrlOrDomain(text)) return text;
    final wordRegex = RegExp(r'\b[A-Za-z]+(?:-[A-Za-z]+)*\b');
    return text.replaceAllMapped(wordRegex, (match) {
      final word = match.group(0)!;
      if (!shouldTransliterateWord(word, true)) {
        return word;
      }
      return transliterateArabicName(word, origin).arabic;
    });
  }

  String _applyPhoneticFallback(String word, String? origin) {
    final order = <String>["chinese", "korean", "japanese", "western"];
    if (origin != null && order.contains(origin)) {
      order.remove(origin);
      order.insert(0, origin);
    }

    String result = "";
    final letterRegex = RegExp(r'[a-z]', caseSensitive: false);

    for (final sys in order) {
      List<MapEntry<String, String>> patterns;
      if (sys == "western") {
        patterns = westernPatterns;
      } else if (sys == "chinese") {
        patterns = chinesePatterns;
      } else if (sys == "korean") {
        patterns = [...koreanPatterns, ...japaneseSyllables];
      } else {
        patterns = japaneseSyllables;
      }

      result = _processPatterns(word, patterns);
      if (!letterRegex.hasMatch(result)) {
        break;
      }
    }

    // Clean consecutive duplicate vowels
    result = result
        .replaceAll(RegExp(r'بيي'), 'بي')
        .replaceAll(RegExp(r'اا+'), 'ا')
        .replaceAll(RegExp(r'يي+'), 'ي')
        .replaceAll(RegExp(r'وو+'), 'و');

    return result;
  }

  String _processPatterns(String word, List<MapEntry<String, String>> patterns) {
    final sorted = List<MapEntry<String, String>>.from(patterns)
      ..sort((a, b) => b.key.length.compareTo(a.key.length));

    final sb = StringBuffer();
    String remaining = word;

    while (remaining.isNotEmpty) {
      MapEntry<String, String>? match;
      for (final entry in sorted) {
        if (remaining.toLowerCase().startsWith(entry.key.toLowerCase())) {
          match = entry;
          break;
        }
      }

      if (match != null) {
        sb.write(match.value);
        remaining = remaining.substring(match.key.length);
      } else {
        sb.write(remaining[0]);
        remaining = remaining.substring(1);
      }
    }

    return sb.toString();
  }
}
