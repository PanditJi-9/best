//! `best_core` holds the small set of routines that must behave identically on
//! Android, iOS, desktop, and the web, and that are hot enough to justify living
//! outside Dart.
//!
//! Everything here is pure: no I/O, no globals, no allocation in the hot paths.
//! That is what makes it safe to call from an FFI boundary and cheap to test.

/// FNV-1a, 64-bit. Used for cache keys and stable diagnostics identifiers.
///
/// This is not a cryptographic hash and must never be used to authenticate a
/// file or a backup. Signatures live in the platform layer.
#[inline]
pub fn fnv1a64(bytes: &[u8]) -> u64 {
    let mut hash: u64 = 0xcbf2_9ce4_8422_2325;
    for byte in bytes {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(0x0000_0100_0000_01b3);
    }
    hash
}

/// Folds a title or a search query into a comparison key.
///
/// The rules are intentionally conservative and reversible by inspection:
/// Arabic diacritics and tatweel are dropped, the common alef/ya/ta-marbuta
/// variants collapse to one letter, Arabic-Indic digits become ASCII, ASCII
/// letters are lowercased, and runs of whitespace become one space.
///
/// It is *not* a locale-aware collation. Sorting stays in the database; this is
/// only for matching what a person typed against what a source returned.
pub fn normalize_search(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    let mut pending_space = false;

    for ch in input.chars() {
        let mapped = match ch {
            // Tashkeel, superscript alef, Quranic marks, tatweel.
            '\u{064B}'..='\u{065F}' | '\u{0670}' | '\u{06D6}'..='\u{06ED}' | '\u{0640}' => continue,
            'أ' | 'إ' | 'آ' | 'ٱ' => 'ا',
            'ة' => 'ه',
            'ى' => 'ي',
            'ؤ' => 'و',
            'ئ' => 'ي',
            '٠'..='٩' => char::from(b'0' + (ch as u32 - '٠' as u32) as u8),
            '۰'..='۹' => char::from(b'0' + (ch as u32 - '۰' as u32) as u8),
            c if c.is_whitespace() => {
                pending_space = !out.is_empty();
                continue;
            }
            c => c.to_ascii_lowercase(),
        };

        if pending_space {
            out.push(' ');
            pending_space = false;
        }
        out.push(mapped);
    }

    out
}

/// Parses the unit number out of a chapter or episode label.
///
/// Sources are wildly inconsistent: `Chapter 12.5`, `Ch. 12`, `الفصل ١٢`,
/// `第12話`, `S2E05`, `Vol. 3 Chapter 7`. The parser prefers a number that
/// follows a known keyword, then falls back to the first plausible number.
/// Four-digit years and numbers attached to `vol` are skipped in the fallback
/// so `2024` is not chapter 2024.
///
/// Returns `None` when no plausible number exists. Callers should keep the
/// label and use a source order instead of inventing a number.
pub fn parse_unit_number(input: &str) -> Option<f64> {
    let normalized = normalize_search(input);
    let tokens = numeric_tokens(&normalized);
    if tokens.is_empty() {
        return None;
    }

    if let Some(keyword_end) = last_keyword_end(&normalized) {
        if let Some((_, value)) = tokens.iter().find(|(start, _)| *start >= keyword_end) {
            return Some(*value);
        }
    }

    tokens
        .iter()
        .map(|(_, value)| *value)
        .find(|value| !is_year(*value))
}

/// One numeric token: byte offset of its first digit, and its value.
fn numeric_tokens(text: &str) -> Vec<(usize, f64)> {
    let bytes = text.as_bytes();
    let mut tokens = Vec::new();
    let mut index = 0;

    while index < bytes.len() {
        if !bytes[index].is_ascii_digit() {
            index += 1;
            continue;
        }

        let start = index;
        let mut end = index;
        while end < bytes.len() && bytes[end].is_ascii_digit() {
            end += 1;
        }
        // A single dot followed by at least one digit is a decimal part. A
        // second dot (`1.2.3`) starts a new token instead of failing the parse.
        if end + 1 < bytes.len() && bytes[end] == b'.' && bytes[end + 1].is_ascii_digit() {
            end += 1;
            while end < bytes.len() && bytes[end].is_ascii_digit() {
                end += 1;
            }
        }

        if let Ok(value) = text[start..end].parse::<f64>() {
            tokens.push((start, value));
        }
        index = end;
    }

    tokens
}

/// Byte offset just past the last recognised chapter/episode keyword.
fn last_keyword_end(text: &str) -> Option<usize> {
    const KEYWORDS: [&str; 10] = [
        "chapter", "ch.", "ch ", "episode", "ep.", "ep ", "فصل", "حلقه", "話", "话",
    ];

    let mut best: Option<usize> = None;
    for keyword in KEYWORDS {
        let mut from = 0;
        while let Some(found) = text[from..].find(keyword) {
            let end = from + found + keyword.len();
            best = Some(best.map_or(end, |current| current.max(end)));
            from = end;
        }
    }
    best
}

fn is_year(value: f64) -> bool {
    value.fract() == 0.0 && (1900.0..=2100.0).contains(&value)
}

/// Conservative estimate used by the UI before a unit is opened. Reading speed
/// is a setting; the default is 45 seconds per page.
pub fn estimate_reading_seconds(pages: u32, seconds_per_page: u32) -> u64 {
    u64::from(pages) * u64::from(seconds_per_page.max(1))
}

// ---------------------------------------------------------------------------
// C ABI
//
// The Dart side loads these through `dart:ffi` on Android, iOS, and desktop.
// Strings are UTF-8 and never outlive the call. The length-returning variant
// lets Dart allocate exactly once instead of guessing a buffer size.
// ---------------------------------------------------------------------------

/// # Safety
/// `ptr` must point to `len` readable bytes for the duration of the call.
#[no_mangle]
pub unsafe extern "C" fn best_fnv1a64(ptr: *const u8, len: usize) -> u64 {
    if ptr.is_null() || len == 0 {
        return fnv1a64(&[]);
    }
    fnv1a64(std::slice::from_raw_parts(ptr, len))
}

/// # Safety
/// `ptr` must point to `len` readable bytes for the duration of the call.
#[no_mangle]
pub unsafe extern "C" fn best_parse_unit_number(ptr: *const u8, len: usize) -> f64 {
    if ptr.is_null() || len == 0 {
        return f64::NAN;
    }
    let bytes = std::slice::from_raw_parts(ptr, len);
    match std::str::from_utf8(bytes) {
        Ok(text) => parse_unit_number(text).unwrap_or(f64::NAN),
        Err(_) => f64::NAN,
    }
}

/// # Safety
/// `ptr` must point to `len` readable bytes. `out` must point to `capacity`
/// writable bytes. The return value is the number of bytes written, or the
/// required capacity when it does not fit (in which case nothing is written).
#[no_mangle]
pub unsafe extern "C" fn best_normalize_search(
    ptr: *const u8,
    len: usize,
    out: *mut u8,
    capacity: usize,
) -> usize {
    if ptr.is_null() || len == 0 {
        return 0;
    }
    let bytes = std::slice::from_raw_parts(ptr, len);
    let Ok(text) = std::str::from_utf8(bytes) else {
        return 0;
    };
    let normalized = normalize_search(text);
    if normalized.len() > capacity || out.is_null() {
        return normalized.len();
    }
    std::ptr::copy_nonoverlapping(normalized.as_ptr(), out, normalized.len());
    normalized.len()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fnv_matches_known_vector() {
        assert_eq!(fnv1a64(b""), 0xcbf2_9ce4_8422_2325);
        assert_eq!(fnv1a64(b"a"), 0xaf63_dc4c_8601_ec8c);
        assert_eq!(fnv1a64(b"foobar"), 0x8594_4171_f739_67e8);
    }

    #[test]
    fn arabic_folding_is_stable() {
        assert_eq!(normalize_search("  الفصلُ  الأول  "), "الفصل الاول");
        assert_eq!(normalize_search("إسراء"), "اسراء");
        assert_eq!(normalize_search("مدرسة"), "مدرسه");
        assert_eq!(normalize_search("على"), "علي");
        assert_eq!(normalize_search("١٢٣"), "123");
    }

    #[test]
    fn parses_common_labels() {
        assert_eq!(parse_unit_number("Chapter 12.5"), Some(12.5));
        assert_eq!(parse_unit_number("Ch. 12"), Some(12.0));
        assert_eq!(parse_unit_number("الفصل ١٢"), Some(12.0));
        assert_eq!(parse_unit_number("الحلقة 3"), Some(3.0));
        assert_eq!(parse_unit_number("第12話"), Some(12.0));
        assert_eq!(parse_unit_number("Vol. 2 Chapter 7"), Some(7.0));
        assert_eq!(parse_unit_number("EP 03"), Some(3.0));
    }

    #[test]
    fn rejects_years_and_noise() {
        assert_eq!(parse_unit_number("2024"), None);
        assert_eq!(parse_unit_number("Coming soon"), None);
        assert_eq!(parse_unit_number(""), None);
    }

    #[test]
    fn takes_the_first_number_of_a_range() {
        assert_eq!(parse_unit_number("Chapters 12-13"), Some(12.0));
        assert_eq!(parse_unit_number("12.5.1"), Some(12.5));
    }

    #[test]
    fn reading_estimate_is_bounded() {
        assert_eq!(estimate_reading_seconds(0, 45), 0);
        assert_eq!(estimate_reading_seconds(20, 45), 900);
        assert_eq!(estimate_reading_seconds(20, 0), 20);
    }

    #[test]
    fn ffi_round_trip() {
        let input = "الفصل ١٢".as_bytes();
        let value = unsafe { best_parse_unit_number(input.as_ptr(), input.len()) };
        assert_eq!(value, 12.0);

        let mut buffer = [0u8; 64];
        let written = unsafe {
            best_normalize_search(
                input.as_ptr(),
                input.len(),
                buffer.as_mut_ptr(),
                buffer.len(),
            )
        };
        assert_eq!(&buffer[..written], "الفصل 12".as_bytes());
    }
}
