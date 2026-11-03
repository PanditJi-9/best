import 'localized_text.dart';

/// One line in a release note.
class NewsLine {
  const NewsLine(this.title, this.body);

  final LocalizedText title;
  final LocalizedText body;
}

/// A shipped version, described in both languages.
///
/// These are hand-written constants, not a feed: the app should be able to say
/// what changed while offline, and a release note is not a news article. The
/// live parts of the News screen (fresh chapters, the extension market) are
/// fetched separately.
class ReleaseNote {
  const ReleaseNote({
    required this.version,
    required this.date,
    required this.lines,
  });

  final String version;

  /// ISO date of the tag, for a stable sort.
  final String date;
  final List<NewsLine> lines;
}

const List<ReleaseNote> kReleaseNotes = [
  ReleaseNote(
    version: '0.11.0',
    date: '2026-11-03',
    lines: [
      NewsLine(
        LocalizedText(
          en: 'A new front page',
          ar: 'واجهة رئيسية جديدة',
        ),
        LocalizedText(
          en: 'Home now leads with what you were reading, then the live '
              'catalogue, the weekly challenge and the new sections.',
          ar: 'تبدأ الرئيسية بما كنت تقرأه، ثم الكتالوج الحي وتحدي الأسبوع '
              'والأقسام الجديدة.',
        ),
      ),
      NewsLine(
        LocalizedText(
          en: 'Discover, with real scores',
          ar: 'اكتشف، بدرجات حقيقية',
        ),
        LocalizedText(
          en: 'A dedicated Discover screen mixes top-rated works, fresh '
              'chapters and picks based on the genres on your shelf.',
          ar: 'شاشة اكتشف تجمع الأعلى تقييمًا وأحدث الفصول وترشيحات مبنية على '
              'التصنيفات الموجودة في مكتبتك.',
        ),
      ),
      NewsLine(
        LocalizedText(
          en: 'Top rated and a weekly challenge',
          ar: 'الأعلى تقييمًا وتحدي الأسبوع',
        ),
        LocalizedText(
          en: 'A transparent ranking built from MangaDex community scores, '
              'plus local badges for streaks and pages read.',
          ar: 'ترتيب شفاف مبني على تقييمات مجتمع MangaDex، مع شارات محلية '
              'للمداومة وصفحات القراءة.',
        ),
      ),
      NewsLine(
        LocalizedText(
          en: 'News and top contributors',
          ar: 'الأخبار وأبرز المساهمين',
        ),
        LocalizedText(
          en: 'Release notes, fresh chapters and the publishers behind the '
              'extension directory, in two new screens.',
          ar: 'ملاحظات الإصدار وأحدث الفصول والناشرون خلف دليل الإضافات، في '
              'شاشتين جديدتين.',
        ),
      ),
    ],
  ),
  ReleaseNote(
    version: '0.10.1',
    date: '2026-11-02',
    lines: [
      NewsLine(
        LocalizedText(
          en: 'MangaLeek pages work',
          ar: 'صفحات مانجا ليك تعمل',
        ),
        LocalizedText(
          en: 'Madara sources build a chapter URL from the work path. That '
              'path now travels from the catalogue card through storage and '
              'the extension bridge, so the reader receives real pages.',
          ar: 'مصادر Madara تبني رابط الفصل من مسار العمل. هذا المسار صار ينتقل '
              'من بطاقة الفهرس عبر التخزين وجسر الإضافات، فيصل القارئ إلى صفحات '
              'حقيقية.',
        ),
      ),
      NewsLine(
        LocalizedText(
          en: 'Cloudflare is reported, not crashed',
          ar: 'رفض Cloudflare يُبلَّغ عنه بدل الانهيار',
        ),
        LocalizedText(
          en: 'A challenged site now produces one clear error instead of '
              'taking the source down with an interceptor exception.',
          ar: 'الموقع المحمي يعرض خطأً واضحًا بدل إسقاط المصدر بخطأ في '
              'المعترض.',
        ),
      ),
    ],
  ),
  ReleaseNote(
    version: '0.10.0',
    date: '2026-10-28',
    lines: [
      NewsLine(
        LocalizedText(
          en: 'The full extension directory',
          ar: 'دليل الإضافات الكامل',
        ),
        LocalizedText(
          en: 'Every Mihon manga and Aniyomi anime extension is listed with '
              'its language, version and publisher. Nothing installs until '
              'you explicitly activate it.',
          ar: 'كل إضافة مانجا من Mihon وإضافة أنمي من Aniyomi تظهر بلغتها '
              'وإصدارها وناشرها. لا شيء يُثبَّت قبل تفعيلك الصريح.',
        ),
      ),
      NewsLine(
        LocalizedText(
          en: 'Verified automatic updates',
          ar: 'تحديثات تلقائية موثّقة',
        ),
        LocalizedText(
          en: 'Activated extensions update from their original repository. A '
              'changed package identity or signing certificate is rejected.',
          ar: 'الإضافات المفعّلة تتحدث من مستودعها الأصلي، ويُرفض أي تغيّر في '
              'هوية الحزمة أو شهادة التوقيع.',
        ),
      ),
    ],
  ),
];
