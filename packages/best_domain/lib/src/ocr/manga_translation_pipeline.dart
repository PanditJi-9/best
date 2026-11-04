import 'arabic_name_transliteration.dart';
import 'arabic_translation_polisher.dart';
import 'comic_ocr_preprocessor.dart';
import 'manga_idioms_dictionary.dart';
import 'ocr_models.dart';

typedef RawTranslator = Future<String> Function(String englishText);

/// The complete end-to-end Manga Arabic translation pipeline.
/// Coordinates text cleaning, idiom replacement, on-device translation,
/// name transliteration, and Arabic post-polishing.
/// Ported from HikariManga 1.4.2.
class MangaTranslationPipeline {
  const MangaTranslationPipeline({
    required this.rawTranslator,
  });

  final RawTranslator rawTranslator;

  static final RegExp _urlRegex = RegExp(
    r'(?i)\b(?:https?://|ftp://|www\.)\S+|(?:discord\.(?:gg|com/invite)|t\.me|patreon\.com)/[^\s<>]+',
  );

  bool isWatermarkOrUrl(String text) {
    if (_urlRegex.hasMatch(text)) return true;
    final lower = text.toLowerCase();
    if (lower.contains('read first at') ||
        lower.contains('scanlation') ||
        lower.contains('visit us at') ||
        lower.contains('all rights reserved') ||
        lower.contains('uploaded to') ||
        lower.contains('join our discord')) {
      return true;
    }
    return false;
  }

  /// Translates a single text bubble from English to polished Arabic.
  Future<String> translateBubbleText(String rawText, {String? seriesOrigin}) async {
    final trimmed = rawText.trim();
    if (trimmed.isEmpty) return '';
    if (isWatermarkOrUrl(trimmed)) return '';

    // Step 1: Clean comic OCR artifacts & typos
    final cleaned = ComicOcrPreprocessor.instance.cleanComicOcrText(trimmed);
    if (cleaned.isEmpty) return '';

    // Step 2: Direct standalone idiom check
    final directIdiom = MangaIdiomsDictionary.instance.getDirectIdiomTranslation(cleaned);
    if (directIdiom != null) {
      return directIdiom;
    }

    // Step 3: Check if it's a character name
    if (ArabicNameTransliteration.instance.shouldTransliterateWord(cleaned)) {
      final nameResult = ArabicNameTransliteration.instance.transliterateArabicName(cleaned, seriesOrigin);
      if (nameResult.confidence != 'low') {
        return nameResult.arabic;
      }
    }

    // Step 4: Handle stutters (e.g. W-What? -> What?)
    final hasStutter = ComicOcrPreprocessor.instance.hasLeadingStutter(cleaned);
    final textForTranslation = ComicOcrPreprocessor.instance.cleanStutters(cleaned);

    // Step 5: Prepare text for machine translation
    final prepared = MangaIdiomsDictionary.instance.prepareTextForMachineTranslation(textForTranslation);

    // Step 6: Invoke raw translator (ML Kit on-device or HTTP fallback)
    String rawArabic;
    try {
      rawArabic = await rawTranslator(prepared);
    } catch (_) {
      rawArabic = '';
    }

    if (rawArabic.trim().isEmpty) {
      // Fallback: transliterate remaining English words if machine translation fails
      return ArabicNameTransliteration.instance.transliterateRemainingEnglishWords(cleaned, seriesOrigin);
    }

    // Step 7: Arabic post-polishing & punctuation
    String polished = ArabicTranslationPolisher.instance.polishArabicTranslation(rawArabic);

    // Step 8: Transliterate any residual English names inside the Arabic text
    polished = ArabicNameTransliteration.instance.transliterateRemainingEnglishWords(polished, seriesOrigin);

    // Step 9: Reapply stutter if original had one (e.g. "ن...نعم")
    if (hasStutter) {
      polished = ComicOcrPreprocessor.instance.applyArabicStutterToFirstWord(polished);
    }

    return polished.trim();
  }

  /// Translates all bubbles on a page and returns updated bubbles.
  Future<List<Bubble>> translatePageBubbles(List<Bubble> bubbles, {String? seriesOrigin}) async {
    final translated = <Bubble>[];
    for (final bubble in bubbles) {
      final arText = await translateBubbleText(bubble.text, seriesOrigin: seriesOrigin);
      if (arText.isNotEmpty) {
        translated.add(bubble.copyWith(
          text: arText,
          rawEnglishText: bubble.text,
        ));
      } else {
        translated.add(bubble);
      }
    }
    return translated;
  }
}
