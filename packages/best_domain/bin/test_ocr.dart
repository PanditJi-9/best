import 'package:best_domain/best_domain.dart';

void main() async {
  print('1. Testing idioms...');
  final idiom1 = MangaIdiomsDictionary.instance.getDirectIdiomTranslation('give me a break');
  print('idiom1: $idiom1');
  assert(idiom1 != null && idiom1.contains('كفاك هراءً'));

  final idiom2 = MangaIdiomsDictionary.instance.getDirectIdiomTranslation('over my dead body');
  print('idiom2: $idiom2');
  assert(idiom2 != null && idiom2.contains('على جثتي'));

  final idiom3 = MangaIdiomsDictionary.instance.getDirectIdiomTranslation('level up');
  print('idiom3: $idiom3');
  assert(idiom3 != null && idiom3.contains('ارتقاء في المستوى'));

  print('2. Testing names...');
  final res1 = ArabicNameTransliteration.instance.transliterateArabicName('Naruto');
  print('res1: ${res1.arabic}');
  assert(res1.arabic == 'ناروتو');

  final res2 = ArabicNameTransliteration.instance.transliterateArabicName('Jin-Woo');
  print('res2: ${res2.arabic}');
  assert(res2.arabic == 'جين وو');

  final res3 = ArabicNameTransliteration.instance.transliterateArabicName('Gojo');
  print('res3: ${res3.arabic}');
  assert(res3.arabic == 'غوجو');

  print('3. Testing preprocessor...');
  final cleaned = ComicOcrPreprocessor.instance.cleanComicOcrText('clead clown modem');
  print('cleaned: $cleaned');
  assert(cleaned == 'dead clown modern');

  final pieCleaned = ComicOcrPreprocessor.instance.cleanComicOcrText('pie!');
  print('pieCleaned: $pieCleaned');
  assert(pieCleaned == 'die!');

  print('4. Testing polisher...');
  final polished1 = ArabicTranslationPolisher.instance.polishArabicTranslation('فطيرة!');
  print('polished1: $polished1');
  assert(polished1 == 'مُت!');

  final polished2 = ArabicTranslationPolisher.instance.polishArabicTranslation('أنت يمين؟');
  print('polished2: $polished2');
  assert(polished2 == 'أنت محق؟');

  final polished3 = ArabicTranslationPolisher.instance.polishArabicTranslation('Naruto-kun, انتظر!');
  print('polished3: $polished3');
  assert(polished3.contains('كون'));

  print('5. Testing pipeline...');
  final pipeline = MangaTranslationPipeline(
    rawTranslator: (en) async {
      if (en == 'die!') return 'مُت!';
      if (en == 'hello') return 'مرحبا';
      return 'ترجمة $en';
    },
  );

  final result1 = await pipeline.translateBubbleText('pie!');
  print('result1: $result1');
  assert(result1 == 'مُت!');

  final result2 = await pipeline.translateBubbleText('give me a break');
  print('result2: $result2');
  assert(result2.contains('كفاك هراءً'));

  final result3 = await pipeline.translateBubbleText('Naruto');
  print('result3: $result3');
  assert(result3 == 'ناروتو');

  print('ALL PASSED!');
}
