import 'package:best_domain/best_domain.dart';

import 'meta/meta_models.dart';

/// Every address in the app, in one place.
///
/// Source ids and work urls are query parameters, not path segments: a source
/// url can contain slashes and dots, and encoding it into a path is how a
/// deep link turns into a 404.
abstract final class Routes {
  static const String home = '/';
  static const String manga = '/manga';
  static const String database = '/database';
  static const String discover = '/discover';
  static const String metaSearch = '/meta/search';
  static const String library = '/library';
  static const String downloads = '/downloads';
  static const String history = '/history';
  static const String menu = '/menu';
  static const String browse = '/browse';
  static const String settings = '/settings';
  static const String about = '/about';
  static const String sources = '/sources';
  static const String stats = '/stats';
  static const String backup = '/backup';
  static const String sync = '/sync';
  static const String topRated = '/top-rated';
  static const String news = '/news';
  static const String contributors = '/contributors';

  static String browseSource(String sourceId) =>
      '$browse?${Uri(queryParameters: {'source': sourceId}).query}';

  static String browseQuery(String query) =>
      '$browse?${Uri(queryParameters: {'q': query}).query}';

  static String metaWork(MetaSource source, String id) =>
      '/meta/work?${Uri(queryParameters: {
            'source': source.name,
            'id': id
          }).query}';

  static String metaList(MetaListKind kind) =>
      '/meta/list?${Uri(queryParameters: {'kind': kind.name}).query}';

  static String series(String sourceId, String url) {
    final query = Uri(queryParameters: {'source': sourceId, 'url': url}).query;
    return '/series?$query';
  }

  static String reader({
    required String sourceId,
    required String url,
    required String unitUrl,
  }) {
    final query = Uri(
      queryParameters: {'source': sourceId, 'url': url, 'unit': unitUrl},
    ).query;
    return '/read?$query';
  }

  static String watch({
    required String sourceId,
    required String url,
    required String unitUrl,
  }) {
    final query = Uri(
      queryParameters: {'source': sourceId, 'url': url, 'unit': unitUrl},
    ).query;
    return '/watch?$query';
  }

  static String seriesOf(Media media) =>
      series(media.ref.sourceId, media.ref.url);

  /// The migration screen is keyed by the stored row id, not by source+url:
  /// the old source may be gone, and the entry is still what must be moved.
  static String migrate(String mediaId) =>
      '/migrate?${Uri(queryParameters: {'id': mediaId}).query}';

  static String migrateOf(Media media) => migrate(media.id);

  static String readerOf(Media media, MediaUnit unit) => reader(
        sourceId: media.ref.sourceId,
        url: media.ref.url,
        unitUrl: unit.url,
      );

  static String watchOf(Media media, MediaUnit unit) => watch(
        sourceId: media.ref.sourceId,
        url: media.ref.url,
        unitUrl: unit.url,
      );
}
