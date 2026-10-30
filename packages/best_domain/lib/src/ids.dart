/// Stable identity for a work and for a unit inside it.
///
/// Identity is a plain string, not a 64-bit hash. Hashing saves a few bytes and
/// buys two real problems: collisions silently merge two works, and Dart web
/// integers lose precision above 2^53. `sourceId::url` is collision-free by
/// construction, readable in a database shell, and cheap to index. Source ids
/// are owned by the app and are guaranteed not to contain `::`.
String mediaIdOf(String sourceId, String url) {
  if (sourceId.isEmpty) {
    throw ArgumentError.value(sourceId, 'sourceId', 'A source id cannot be empty.');
  }
  if (sourceId.contains('::')) {
    throw ArgumentError.value(sourceId, 'sourceId', 'A source id cannot contain "::".');
  }
  if (url.isEmpty) {
    throw ArgumentError.value(url, 'url', 'A media url cannot be empty.');
  }
  return '$sourceId::$url';
}

String unitIdOf(String mediaId, String url) {
  if (mediaId.isEmpty) {
    throw ArgumentError.value(mediaId, 'mediaId', 'A media id cannot be empty.');
  }
  if (url.isEmpty) {
    throw ArgumentError.value(url, 'url', 'A unit url cannot be empty.');
  }
  return '$mediaId::$url';
}
