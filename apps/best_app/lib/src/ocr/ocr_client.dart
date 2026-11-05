import 'package:best_domain/best_domain.dart';
import 'package:flutter/services.dart';

/// Dart client for native OCR and translation services.
class OcrClient {
  OcrClient({LibraryRepository? repository}) : _repository = repository;

  final LibraryRepository? _repository;
  static const MethodChannel _channel = MethodChannel('app.best/ocr');

  late final MangaTranslationPipeline pipeline = MangaTranslationPipeline(
    rawTranslator: translateText,
  );

  Future<String> translateText(String text) async {
    try {
      final res = await _channel.invokeMethod<String>('translateText', {'text': text});
      return res ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<bool> isModelDownloaded() async {
    try {
      final res = await _channel.invokeMethod<bool>('isModelDownloaded');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> downloadModel() async {
    try {
      final res = await _channel.invokeMethod<bool>('downloadModel');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Recognizes speech bubbles on a manga page and translates them to Arabic.
  /// Checks local SQLite cache first.
  Future<PageOcrResult> processAndTranslatePage({
    required String unitId,
    required int pageIndex,
    required Uint8List imageBytes,
    String? seriesOrigin,
  }) async {
    // 1. Check cache
    if (_repository != null) {
      final cached = await _repository.getPageOcr(unitId, pageIndex);
      if (cached != null && cached.bubbles.isNotEmpty) {
        return cached;
      }
    }

    // 2. Call native ML Kit OCR
    Map<Object?, Object?>? ocrData;
    try {
      ocrData = await _channel.invokeMethod<Map<Object?, Object?>>(
        'recognizeBubbles',
        {'bytes': imageBytes},
      );
    } catch (_) {
      ocrData = null;
    }

    if (ocrData == null) {
      return PageOcrResult(
        pageIndex: pageIndex,
        imageWidth: 0,
        imageHeight: 0,
        bubbles: const [],
      );
    }

    final width = (ocrData['width'] as num?)?.toInt() ?? 0;
    final height = (ocrData['height'] as num?)?.toInt() ?? 0;
    final rawBubblesList =
        (ocrData['bubbles'] as List<Object?>? ?? const <Object?>[]);

    final rawBubbles =
        rawBubblesList.whereType<Map<Object?, Object?>>().map((Map<Object?, Object?> map) {
      final m = Map<String, dynamic>.from(map);
      return Bubble.fromJson(m);
    }).toList();

    // 3. Run through translation pipeline (dictionaries, name transliteration, translation, polish)
    final translatedBubbles = await pipeline.translatePageBubbles(
      rawBubbles,
      seriesOrigin: seriesOrigin,
    );

    final result = PageOcrResult(
      pageIndex: pageIndex,
      imageWidth: width,
      imageHeight: height,
      bubbles: translatedBubbles,
    );

    // 4. Save to SQLite cache
    if (_repository != null) {
      await _repository.savePageOcr(unitId, result);
    }

    return result;
  }

  /// Checks if an image is an excessively tall webtoon strip requiring slicing.
  Future<bool> shouldSliceWebtoon(Uint8List bytes) async {
    try {
      final res = await _channel.invokeMethod<bool>(
        'shouldSliceWebtoon',
        {'bytes': bytes},
      );
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Slices an oversized webtoon strip into 2048px vertical tiles using native BitmapRegionDecoder.
  Future<List<Map<String, dynamic>>> sliceWebtoon({
    required Uint8List bytes,
    required String pageId,
  }) async {
    try {
      final res = await _channel.invokeListMethod<Map<Object?, Object?>>(
        'sliceWebtoon',
        {'bytes': bytes, 'pageId': pageId},
      );
      if (res == null) return const <Map<String, dynamic>>[];
      return res
          .map((Map<Object?, Object?> m) => Map<String, dynamic>.from(m))
          .toList();
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }
}
