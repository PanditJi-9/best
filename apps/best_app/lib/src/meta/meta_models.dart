/// The public catalogues Best reads for its database screen.
///
/// These are not reading sources: they publish metadata, scores and news. A
/// work found here is opened in the browser or searched for in the person's
/// installed reading sources; nothing is scraped from a source that requires
/// an account.
enum MetaSource { anilist, myAnimeList, hwa, animeCorner }

extension MetaSourceInfo on MetaSource {
  String get label => switch (this) {
        MetaSource.anilist => 'AniList',
        MetaSource.myAnimeList => 'MyAnimeList',
        MetaSource.hwa => 'hwa.so',
        MetaSource.animeCorner => 'Anime Corner',
      };

  String get shortLabel => switch (this) {
        MetaSource.anilist => 'AniList',
        MetaSource.myAnimeList => 'MAL',
        MetaSource.hwa => 'hwa.so',
        MetaSource.animeCorner => 'Anime Corner',
      };

  String get homeUrl => switch (this) {
        MetaSource.anilist => 'https://anilist.co',
        MetaSource.myAnimeList => 'https://myanimelist.net',
        MetaSource.hwa => 'https://hwa.so',
        MetaSource.animeCorner => 'https://animecorner.me',
      };
}

enum MetaKind { anime, manga, manhwa, manhua, unknown }

/// A work in one of the public catalogues.
///
/// A single shape is used for all four providers. Fields a provider does not
/// publish stay null; the UI never fills them with a guess.
class MetaWork {
  const MetaWork({
    required this.id,
    required this.source,
    required this.title,
    this.kind = MetaKind.unknown,
    this.englishTitle,
    this.nativeTitle,
    this.coverUrl,
    this.bannerUrl,
    this.synopsis,
    this.genres = const [],
    this.score,
    this.scoreSource,
    this.votes,
    this.rank,
    this.popularityRank,
    this.favourites,
    this.format,
    this.status,
    this.episodes,
    this.chapters,
    this.duration,
    this.year,
    this.season,
    this.country,
    this.siteUrl,
    this.malId,
    this.anilistId,
    this.slug,
    this.authors = const [],
    this.artists = const [],
    this.studios = const [],
    this.publishers = const [],
    this.links = const [],
    this.tags = const [],
    this.recommendations = const [],
    this.nextEpisode,
    this.nextEpisodeAt,
    this.isAdult = false,
  });

  final String id;
  final MetaSource source;
  final MetaKind kind;
  final String title;
  final String? englishTitle;
  final String? nativeTitle;
  final String? coverUrl;
  final String? bannerUrl;
  final String? synopsis;
  final List<String> genres;

  /// Normalised to 0–10. Every provider publishes a different scale, so the
  /// app converts once and keeps the original source's name beside the number.
  final double? score;
  final String? scoreSource;
  final int? votes;
  final int? rank;
  final int? popularityRank;
  final int? favourites;
  final String? format;
  final String? status;
  final int? episodes;
  final int? chapters;
  final String? duration;
  final int? year;
  final String? season;
  final String? country;
  final String? siteUrl;
  final int? malId;
  final int? anilistId;
  final String? slug;
  final List<String> authors;
  final List<String> artists;
  final List<String> studios;
  final List<String> publishers;
  final List<MetaLink> links;
  final List<MetaTag> tags;
  final List<MetaWork> recommendations;
  final int? nextEpisode;

  /// Seconds since the epoch, as AniList reports it.
  final int? nextEpisodeAt;
  final bool isAdult;

  MetaKey get key => MetaKey(source, id);

  String get displayTitle {
    final english = englishTitle?.trim();
    if (english != null && english.isNotEmpty) return english;
    return title;
  }
}

class MetaKey {
  const MetaKey(this.source, this.id);

  final MetaSource source;
  final String id;

  @override
  bool operator ==(Object other) =>
      other is MetaKey && other.source == source && other.id == id;

  @override
  int get hashCode => Object.hash(source, id);

  @override
  String toString() => '${source.name}:$id';
}

class MetaLink {
  const MetaLink({required this.label, required this.url, this.kind = 'link'});

  final String label;
  final String url;

  /// `streaming`, `official`, `social` or `link`.
  final String kind;
}

class MetaTag {
  const MetaTag({required this.name, this.rank});

  final String name;
  final int? rank;
}

class MetaNews {
  const MetaNews({
    required this.title,
    required this.url,
    this.summary = '',
    this.imageUrl,
    this.category,
    this.author,
    this.publishedAt,
  });

  final String title;
  final String url;
  final String summary;
  final String? imageUrl;
  final String? category;
  final String? author;
  final DateTime? publishedAt;
}

/// Everything the database front page needs, with per-provider failures kept
/// separate. One catalogue being down must not hide the other three.
class MetaHome {
  const MetaHome({
    this.trending = const [],
    this.airing = const [],
    this.topMal = const [],
    this.topManhwa = const [],
    this.news = const [],
    this.failures = const {},
  });

  final List<MetaWork> trending;
  final List<MetaWork> airing;
  final List<MetaWork> topMal;

  /// A fallback shelf for tests and previews. The live shelf is loaded by
  /// `metaManhwaProvider`, because hwa.so answers far slower than the other
  /// catalogues and must not hold the page.
  final List<MetaWork> topManhwa;
  final List<MetaNews> news;
  final Map<MetaSource, String> failures;

  bool get isEmpty =>
      trending.isEmpty &&
      airing.isEmpty &&
      topMal.isEmpty &&
      topManhwa.isEmpty &&
      news.isEmpty;

  MetaWork? get hero {
    if (trending.isNotEmpty) return trending.first;
    if (airing.isNotEmpty) return airing.first;
    if (topMal.isNotEmpty) return topMal.first;
    if (topManhwa.isNotEmpty) return topManhwa.first;
    return null;
  }
}

class MetaSearchResults {
  const MetaSearchResults({
    required this.query,
    this.anime = const [],
    this.manhwa = const [],
    this.failures = const {},
  });

  final String query;

  /// AniList results first, then MAL-only results. A MAL title already present
  /// in AniList is not repeated.
  final List<MetaWork> anime;
  final List<MetaWork> manhwa;
  final Map<MetaSource, String> failures;

  bool get isEmpty => anime.isEmpty && manhwa.isEmpty;
}

enum MetaListKind { anilistTrending, anilistTop, anilistAiring, malTop, hwaTop }

extension MetaListKindInfo on MetaListKind {
  MetaSource get source => switch (this) {
        MetaListKind.anilistTrending ||
        MetaListKind.anilistTop ||
        MetaListKind.anilistAiring =>
          MetaSource.anilist,
        MetaListKind.malTop => MetaSource.myAnimeList,
        MetaListKind.hwaTop => MetaSource.hwa,
      };
}
