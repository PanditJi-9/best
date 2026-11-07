import 'package:flutter/widgets.dart';

/// The direction a title should be painted in.
///
/// The app is Arabic-first, but most source titles are Latin. Painting a Latin
/// title with the ambient RTL direction puts the ellipsis on the left, so the
/// useful end of the name disappears (`…Wind Breaker S`). A title follows its
/// first strong letter instead; pure numbers and punctuation keep the ambient
/// direction.
TextDirection autoTextDirection(String text, TextDirection fallback) {
  for (final rune in text.runes) {
    if (rune >= 0x0590 && rune <= 0x08FF) return TextDirection.rtl;
    if ((rune >= 0x0041 && rune <= 0x005A) ||
        (rune >= 0x0061 && rune <= 0x007A)) {
      return TextDirection.ltr;
    }
  }
  return fallback;
}

/// Wraps machine-readable values (dates, scores, sizes) in a Unicode LTR
/// isolate so an Arabic paragraph cannot reorder their parts.
String ltrIsolate(String value) => '\u2066$value\u2069';
