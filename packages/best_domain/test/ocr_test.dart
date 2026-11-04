import 'package:best_domain/best_domain.dart';
import 'package:test/test.dart';

void main() {
  group('Manga Translation Pipeline & Dictionaries', () {
    test('Direct idiom translation works', () {
      final idiom1 = MangaIdiomsDictionary.instance.getDirectIdiomTranslation("give me a break");
      expect(idiom1, contains('كفاك هراءً'));

      final idiom2 = MangaIdiomsDictionary.instance.getDirectIdiomTranslation("over my dead body");
      expect(idiom2, contains('على جثتي'));

      final idiom3 = MangaIdiomsDictionary.instance.getDirectIdiomTranslation("level up");
      expect(idiom3, contains('ارتقاء في المستوى'));
    });

    test('Name transliteration works for known anime/manhwa names', () {
      final res1 = ArabicNameTransliteration.instance.transliterateArabicName("Naruto");
      expect(res1.arabic, 'ناروتو');

      final res2 = ArabicNameTransliteration.instance.transliterateArabicName("Jin-Woo");
      expect(res2.arabic, 'جين وو');

      final res3 = ArabicNameTransliteration.instance.transliterateArabicName("Gojo");
      expect(res3.arabic, 'غوجو');
    });

    test('Comic OCR preprocessor cleans typos and homoglyphs', () {
      final cleaned = ComicOcrPreprocessor.instance.cleanComicOcrText("clead clown modem");
      expect(cleaned, 'dead clown modern');

      final pieCleaned = ComicOcrPreprocessor.instance.cleanComicOcrText("pie!");
      expect(pieCleaned, 'die!');
    });

    test('Arabic translation polisher cleans mistranslations', () {
      final polished1 = ArabicTranslationPolisher.instance.polishArabicTranslation("فطيرة!");
      expect(polished1, 'مُت!');

      final polished2 = ArabicTranslationPolisher.instance.polishArabicTranslation("أنت يمين؟");
      expect(polished2, 'أنت محق؟');

      final polished3 = ArabicTranslationPolisher.instance.polishArabicTranslation("Naruto-kun, انتظر!");
      expect(polished3, contains('كون'));
    });

    test('Full pipeline coordinates end-to-end', () async {
      final pipeline = MangaTranslationPipeline(
        rawTranslator: (en) async {
          if (en == 'die!') return 'مُت!';
          if (en == 'hello') return 'مرحبا';
          return 'ترجمة $en';
        },
      );

      final result1 = await pipeline.translateBubbleText('pie!');
      expect(result1, 'مُت!');

      final result2 = await pipeline.translateBubbleText('give me a break');
      expect(result2, contains('كفاك هراءً'));

      final result3 = await pipeline.translateBubbleText('Naruto');
      expect(result3, 'ناروتو');
    });
  });
}
