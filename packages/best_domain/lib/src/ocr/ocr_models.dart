/// Models representing detected speech bubbles, bounding boxes, and OCR results.
class BoundingBox {
  const BoundingBox({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;

  BoundingBox copyWith({
    double? left,
    double? top,
    double? width,
    double? height,
  }) {
    return BoundingBox(
      left: left ?? this.left,
      top: top ?? this.top,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }

  Map<String, dynamic> toJson() => {
    'left': left,
    'top': top,
    'width': width,
    'height': height,
  };

  factory BoundingBox.fromJson(Map<String, dynamic> json) => BoundingBox(
    left: (json['left'] as num).toDouble(),
    top: (json['top'] as num).toDouble(),
    width: (json['width'] as num).toDouble(),
    height: (json['height'] as num).toDouble(),
  );

  @override
  String toString() => 'BoundingBox(left: $left, top: $top, width: $width, height: $height)';
}

/// A speech or thought bubble on a manga page.
class Bubble {
  const Bubble({
    required this.text,
    required this.box,
    this.bgColorHex,
    this.bgGradientEndHex,
    this.textColorHex,
    this.rawEnglishText,
    this.isNativeOverlay = false,
  });

  final String text;
  final BoundingBox box;
  final String? bgColorHex;
  final String? bgGradientEndHex;
  final String? textColorHex;
  final String? rawEnglishText;
  final bool isNativeOverlay;

  Bubble copyWith({
    String? text,
    BoundingBox? box,
    String? bgColorHex,
    String? bgGradientEndHex,
    String? textColorHex,
    String? rawEnglishText,
    bool? isNativeOverlay,
  }) {
    return Bubble(
      text: text ?? this.text,
      box: box ?? this.box,
      bgColorHex: bgColorHex ?? this.bgColorHex,
      bgGradientEndHex: bgGradientEndHex ?? this.bgGradientEndHex,
      textColorHex: textColorHex ?? this.textColorHex,
      rawEnglishText: rawEnglishText ?? this.rawEnglishText,
      isNativeOverlay: isNativeOverlay ?? this.isNativeOverlay,
    );
  }

  Map<String, dynamic> toJson() => {
    'text': text,
    'box': box.toJson(),
    if (bgColorHex != null) 'bgColorHex': bgColorHex,
    if (bgGradientEndHex != null) 'bgGradientEndHex': bgGradientEndHex,
    if (textColorHex != null) 'textColorHex': textColorHex,
    if (rawEnglishText != null) 'rawEnglishText': rawEnglishText,
    'isNativeOverlay': isNativeOverlay,
  };

  factory Bubble.fromJson(Map<String, dynamic> json) => Bubble(
    text: json['text'] as String,
    box: BoundingBox.fromJson(json['box'] as Map<String, dynamic>),
    bgColorHex: json['bgColorHex'] as String?,
    bgGradientEndHex: json['bgGradientEndHex'] as String?,
    textColorHex: json['textColorHex'] as String?,
    rawEnglishText: json['rawEnglishText'] as String?,
    isNativeOverlay: json['isNativeOverlay'] as bool? ?? false,
  );

  @override
  String toString() => 'Bubble(text: "$text", box: $box, bg: $bgColorHex)';
}

/// The result of performing OCR and translation on a single manga page.
class PageOcrResult {
  const PageOcrResult({
    required this.pageIndex,
    required this.imageWidth,
    required this.imageHeight,
    required this.bubbles,
  });

  final int pageIndex;
  final int imageWidth;
  final int imageHeight;
  final List<Bubble> bubbles;

  Map<String, dynamic> toJson() => {
    'pageIndex': pageIndex,
    'imageWidth': imageWidth,
    'imageHeight': imageHeight,
    'bubbles': bubbles.map((b) => b.toJson()).toList(),
  };

  factory PageOcrResult.fromJson(Map<String, dynamic> json) => PageOcrResult(
    pageIndex: json['pageIndex'] as int? ?? 0,
    imageWidth: json['imageWidth'] as int? ?? 0,
    imageHeight: json['imageHeight'] as int? ?? 0,
    bubbles: (json['bubbles'] as List<dynamic>? ?? [])
        .map((b) => Bubble.fromJson(b as Map<String, dynamic>))
        .toList(),
  );
}
