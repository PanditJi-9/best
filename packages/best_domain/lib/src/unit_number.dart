import 'search_text.dart';

/// Parses the unit number out of a chapter or episode label.
///
/// Mirrors `best_core::parse_unit_number`; see that file for the rationale.
/// Returns `null` rather than inventing a number when the label has none.
double? parseUnitNumber(String input) {
  final text = SearchText.normalize(input);
  final tokens = _numericTokens(text);
  if (tokens.isEmpty) return null;

  final keywordEnd = _lastKeywordEnd(text);
  if (keywordEnd != null) {
    for (final token in tokens) {
      if (token.start >= keywordEnd) return token.value;
    }
  }

  for (final token in tokens) {
    if (!_isYear(token.value)) return token.value;
  }
  return null;
}

class _Token {
  const _Token(this.start, this.value);
  final int start;
  final double value;
}

List<_Token> _numericTokens(String text) {
  final tokens = <_Token>[];
  var index = 0;

  while (index < text.length) {
    if (!_isDigit(text.codeUnitAt(index))) {
      index++;
      continue;
    }

    final start = index;
    var end = index;
    while (end < text.length && _isDigit(text.codeUnitAt(end))) {
      end++;
    }
    if (end + 1 < text.length &&
        text.codeUnitAt(end) == 0x2E &&
        _isDigit(text.codeUnitAt(end + 1))) {
      end++;
      while (end < text.length && _isDigit(text.codeUnitAt(end))) {
        end++;
      }
    }

    final value = double.tryParse(text.substring(start, end));
    if (value != null) tokens.add(_Token(start, value));
    index = end;
  }

  return tokens;
}

bool _isDigit(int unit) => unit >= 0x30 && unit <= 0x39;

int? _lastKeywordEnd(String text) {
  const keywords = [
    'chapter',
    'ch.',
    'ch ',
    'episode',
    'ep.',
    'ep ',
    'فصل',
    'حلقه',
    '話',
    '话',
  ];

  int? best;
  for (final keyword in keywords) {
    var from = 0;
    while (true) {
      final found = text.indexOf(keyword, from);
      if (found < 0) break;
      final end = found + keyword.length;
      if (best == null || end > best) best = end;
      from = end;
    }
  }
  return best;
}

bool _isYear(double value) =>
    value == value.roundToDouble() && value >= 1900 && value <= 2100;
