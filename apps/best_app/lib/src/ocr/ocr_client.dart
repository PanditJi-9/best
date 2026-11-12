import 'package:best_domain/best_domain.dart';
import 'package:flutter/services.dart';

/// One vertical tile produced by the native webtoon decoder.
class WebtoonSlice {
  const WebtoonSlice({
    required this.index,
    required this.top,
    required this.width,
    required this.height,
    required this.filePath,
  });

  final int index;
  final int top;
  final int width;
  final int height;
  final String filePath;

  /// The source aspect ratio, kept from the decoder's original coordinates so
  /// the tile can reserve its space before the JPEG is decoded.
  double get aspectRatio => height > 0 ? width / height : 1;

  factory WebtoonSlice.fromMap(Map<String, dynamic> map) {
    return WebtoonSlice(
      index: (map['index'] as num?)?.toInt() ?? 0,
      top: (map['top'] as num?)?.toInt() ?? 0,
      width: (map['width'] as num?)?.toInt() ?? 0,
      height: (map['height'] as num?)?.toInt() ?? 0,
      filePath: map['filePath'] as String? ?? '',
    );
  }
}

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
      final res = await _channel.invokeMethod<String>('translateText', {
        'text': text,
      });
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

  Future<bool> downloadModel({bool force = false}) async {
    try {
      final res = await _channel.invokeMethod<bool>('downloadModel', {
        'force': force,
      });
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
      // A page can legitimately contain no speech bubbles. Caching that empty
      // result is what keeps cover art and silent spreads from being sent
      // through OCR again on every rebuild.
      if (cached != null) return cached;
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

    final rawBubbles = rawBubblesList.whereType<Map<Object?, Object?>>().map((
      Map<Object?, Object?> map,
    ) {
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

    // 4. Save to SQLite cache only when every translatable bubble was handled.
    // A page translated while the model was still downloading (or offline) must
    // be retried later, not frozen as English for every future open.
    final complete = translatedBubbles.every(
      (bubble) =>
          bubble.rawEnglishText != null ||
          !RegExp(r'[A-Za-z]').hasMatch(bubble.text),
    );
    if (_repository != null && complete) {
      await _repository.savePageOcr(unitId, result);
    }

    return result;
  }

  /// Checks if an image is an excessively tall webtoon strip requiring slicing.
  Future<bool> shouldSliceWebtoon(Uint8List bytes) async {
    try {
      final res = await _channel.invokeMethod<bool>('shouldSliceWebtoon', {
        'bytes': bytes,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Slices an oversized webtoon strip into 2048px vertical tiles using native BitmapRegionDecoder.
  Future<List<WebtoonSlice>> sliceWebtoon({
    required Uint8List bytes,
    required String pageId,
  }) async {
    try {
      final res = await _channel.invokeListMethod<Map<Object?, Object?>>(
        'sliceWebtoon',
        {'bytes': bytes, 'pageId': pageId},
      );
      if (res == null) return const <WebtoonSlice>[];
      return res
          .map(
            (Map<Object?, Object?> m) =>
                WebtoonSlice.fromMap(Map<String, dynamic>.from(m)),
          )
          .where((slice) => slice.filePath.isNotEmpty && slice.height > 0)
          .toList();
    } catch (_) {
      return const <WebtoonSlice>[];
    }
  }
}
