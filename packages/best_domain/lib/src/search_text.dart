/// Arabic-aware folding used for matching a query against a title.
///
/// This mirrors `best_core::normalize_search`. The Rust implementation is the
/// canonical one; this Dart copy keeps the web build and unit tests working
/// before the WASM module loads, and a parity test pins both to the same cases.
/// Keep the two files in sync when a rule changes.
class SearchText {
  const SearchText._();

  static String normalize(String input) {
    final out = StringBuffer();
    var pendingSpace = false;

    for (final rune in input.runes) {
      // Tashkeel, superscript alef, Quranic marks, tatweel.
      if ((rune >= 0x064B && rune <= 0x065F) ||
          rune == 0x0670 ||
          (rune >= 0x06D6 && rune <= 0x06ED) ||
          rune == 0x0640) {
        continue;
      }

      final int mapped;
      if (rune == 0x0623 || rune == 0x0625 || rune == 0x0622 || rune == 0x0671) {
        mapped = 0x0627; // alef
      } else if (rune == 0x0629) {
        mapped = 0x0647; // ta marbuta -> ha
      } else if (rune == 0x0649) {
        mapped = 0x064A; // alef maqsura -> ya
      } else if (rune == 0x0624) {
        mapped = 0x0648; // waw with hamza -> waw
      } else if (rune == 0x0626) {
        mapped = 0x064A; // ya with hamza -> ya
      } else if (rune >= 0x0660 && rune <= 0x0669) {
        mapped = 0x30 + (rune - 0x0660);
      } else if (rune >= 0x06F0 && rune <= 0x06F9) {
        mapped = 0x30 + (rune - 0x06F0);
      } else if (rune == 0x20 || rune == 0x09 || rune == 0x0A || rune == 0x0D ||
          rune == 0x00A0) {
        pendingSpace = out.isNotEmpty;
        continue;
      } else if (rune >= 0x41 && rune <= 0x5A) {
        mapped = rune + 32;
      } else {
        mapped = rune;
      }

      if (pendingSpace) {
        out.write(' ');
        pendingSpace = false;
      }
      out.writeCharCode(mapped);
    }

    return out.toString();
  }

  /// True when [haystack] contains [needle] after folding. An empty needle
  /// matches everything, which is what an empty search box means.
  static bool matches(String haystack, String needle) {
    final query = normalize(needle);
    if (query.isEmpty) return true;
    return normalize(haystack).contains(query);
  }
}
