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

  /// Machine translation is the slowest step and comic pages repeat short
  /// bubbles constantly. A small LRU keeps a chapter's common lines local,
  /// including the code-points that distinguish two series' names.
  static const int _translationCacheLimit = 500;
  static final Map<String, String> _translationCache = <String, String>{};

  /// A page often repeats the same shout or reaction. Sharing the in-flight
  /// future avoids sending that line to the network twice while the first
  /// copy is still being translated.
  static final Map<String, Future<String>> _inFlightTranslations =
      <String, Future<String>>{};

  /// A page often contains four to ten balloons. Translating them one after
  /// another made the slowest bubble set the page latency; a small pool keeps
  /// the order deterministic without letting a whole chapter compete for the
  /// translation engine.
  static const int _pageTranslationConcurrency = 4;

  static final RegExp _urlRegex = RegExp(
    r'\b(?:https?://|ftp://|www\.)\S+|(?:discord\.(?:gg|com/invite)|t\.me|patreon\.com)/[^\s<>]+',
    caseSensitive: false,
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
  Future<String> translateBubbleText(
    String rawText, {
    String? seriesOrigin,
  }) {
    final trimmed = rawText.trim();
    if (trimmed.isEmpty) return Future<String>.value('');
    final key = '${seriesOrigin ?? ''}\u0000$trimmed';
    final cached = _translationCache.remove(key);
    if (cached != null) {
      _translationCache[key] = cached;
      return Future<String>.value(cached);
    }
    final inFlight = _inFlightTranslations[key];
    if (inFlight != null) return inFlight;

    final future = _translateBubbleTextUncached(
      trimmed,
      seriesOrigin: seriesOrigin,
    ).then((result) {
      // An empty result usually means the network was down or the on-device
      // model was still downloading. Caching it would permanently hide the
      // translation after connectivity returns.
      if (result.isNotEmpty) _rememberTranslation(key, result);
      return result;
    }).whenComplete(() {
      _inFlightTranslations.remove(key);
    });
    _inFlightTranslations[key] = future;
    return future;
  }

  void _rememberTranslation(String key, String value) {
    _translationCache.remove(key);
    _translationCache[key] = value;
    while (_translationCache.length > _translationCacheLimit) {
      _translationCache.remove(_translationCache.keys.first);
    }
  }

  Future<String> _translateBubbleTextUncached(
    String trimmed, {
    String? seriesOrigin,
  }) async {
    if (isWatermarkOrUrl(trimmed)) return '';

    // Step 1: Clean comic OCR artifacts & typos
    final cleaned = ComicOcrPreprocessor.instance.cleanComicOcrText(trimmed);
    if (cleaned.isEmpty) return '';

    // Step 2: Direct standalone idiom check
    final directIdiom =
        MangaIdiomsDictionary.instance.getDirectIdiomTranslation(cleaned);
    if (directIdiom != null) {
      return directIdiom;
    }

    // Step 3: Check if it's a character name
    if (ArabicNameTransliteration.instance.shouldTransliterateWord(cleaned)) {
      final nameResult = ArabicNameTransliteration.instance
          .transliterateArabicName(cleaned, seriesOrigin);
      if (nameResult.confidence != 'low') {
        return nameResult.arabic;
      }
    }

    // Step 4: Handle stutters (e.g. W-What? -> What?)
    final hasStutter = ComicOcrPreprocessor.instance.hasLeadingStutter(cleaned);
    final textForTranslation =
        ComicOcrPreprocessor.instance.cleanStutters(cleaned);

    // Step 5: Prepare text for machine translation
    final prepared = MangaIdiomsDictionary.instance
        .prepareTextForMachineTranslation(textForTranslation);

    // Step 6: Invoke raw translator (ML Kit on-device or HTTP fallback)
    String rawArabic;
    try {
      rawArabic = await rawTranslator(prepared);
    } catch (_) {
      rawArabic = '';
    }

    if (rawArabic.trim().isEmpty) {
      // Keep a one- or two-word name readable, but never turn a whole English
      // sentence into Arabic letters: that looks translated without being
      // translated. The original bubble will stay visible instead.
      final words = cleaned.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
      if (words.length <= 2) {
        return ArabicNameTransliteration.instance
            .transliterateRemainingEnglishWords(cleaned, seriesOrigin);
      }
      return '';
    }

    // Step 7: Arabic post-polishing & punctuation
    String polished =
        ArabicTranslationPolisher.instance.polishArabicTranslation(rawArabic);

    // Step 8: Transliterate any residual English names inside the Arabic text
    polished = ArabicNameTransliteration.instance
        .transliterateRemainingEnglishWords(polished, seriesOrigin);

    // Step 9: Reapply stutter if original had one (e.g. "ن...نعم")
    if (hasStutter) {
      polished =
          ComicOcrPreprocessor.instance.applyArabicStutterToFirstWord(polished);
    }

    return polished.trim();
  }

  /// Translates all bubbles on a page and returns updated bubbles in image
  /// order. Work is bounded rather than unbounded: the native engine already
  /// serialises its model work, and a page of twenty bubbles should not launch
  /// twenty HTTP requests.
  Future<List<Bubble>> translatePageBubbles(
    List<Bubble> bubbles, {
    String? seriesOrigin,
  }) async {
    if (bubbles.isEmpty) return const <Bubble>[];
    final translated = List<Bubble>.filled(bubbles.length, bubbles.first);
    var next = 0;

    Future<void> worker() async {
      while (true) {
        final index = next;
        if (index >= bubbles.length) return;
        next++;
        final bubble = bubbles[index];
        String arText;
        try {
          arText = await translateBubbleText(
            bubble.text,
            seriesOrigin: seriesOrigin,
          );
        } catch (_) {
          arText = '';
        }
        translated[index] = arText.isNotEmpty
            ? bubble.copyWith(text: arText, rawEnglishText: bubble.text)
            : bubble;
      }
    }

    final workers = bubbles.length < _pageTranslationConcurrency
        ? bubbles.length
        : _pageTranslationConcurrency;
    await Future.wait([for (var i = 0; i < workers; i++) worker()]);
    return translated;
  }
}
