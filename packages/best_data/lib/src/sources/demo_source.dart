import 'package:best_domain/best_domain.dart';

/// The offline guide that ships inside the app.
///
/// It exists so a fresh install is never an empty room: a person can open a
/// title, turn pages, and see progress survive a restart before configuring any
/// account or source. Its pages are generated, and the UI labels it as a guide
/// rather than pretending it is licensed content.
class DemoSource implements SourceAdapter {
  const DemoSource();

  static const String sourceId = 'guide';

  @override
  String get id => sourceId;

  @override
  String get name => 'Best Guide';

  @override
  String get language => 'ar';

  /// Public-domain films streamed from Mux and Blender test buckets. The guide
  /// exists to prove the player end to end; every episode of a work points at
  /// one sample so a fresh install has something real to watch.
  ///
  /// These are checked by the emulator smoke job. Google's `gtv-videos-bucket`
  /// samples were made private and now answer 403, which is exactly the kind of
  /// rot a hard-coded demo URL is prone to: replace a dead one here rather than
  /// leaving a broken "play" button in a fresh install.
  static const String _sintelTrailer =
      'https://download.blender.org/durian/trailer/sintel_trailer-720p.mp4';
  static const String _hlsSample =
      'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8';
  static const String _hlsAlternate =
      'https://test-streams.mux.dev/pts_shift/master.m3u8';

  /// Captions that ship inside the app, so the subtitle overlay works with the
  /// network switched off. The player treats `asset://` as a bundled file and
  /// everything else as a URL.
  static const String _subtitleSample =
      'asset://assets/subtitles/guide.vtt';

  static const List<_GuideWork> _works = [
    _GuideWork(
      slug: 'forest-shadow',
      title: 'ظل الغابة',
      nativeTitle: '숲의 그림자',
      kind: MediaKind.manhwa,
      author: 'نور الحكيم',
      year: 2025,
      genres: ['فانتازيا', 'دراما', 'غموض'],
      synopsis:
          'حارسٌ شاب يكتشف أن الغابة التي يحميها تتذكر كل خطوة خطاها فيها. ليلة واحدة تكفي ليعرف أن الذاكرة ليست نعمة.',
      units: 12,
      pages: 18,
    ),
    _GuideWork(
      slug: 'paper-kingdom',
      title: 'Paper Kingdom',
      nativeTitle: '紙の王国',
      kind: MediaKind.manga,
      author: 'Ren Aoki',
      year: 2024,
      genres: ['Adventure', 'Fantasy'],
      synopsis:
          'A cartographer folds a kingdom out of a single sheet of paper, then has to live inside it when the fold starts to tear.',
      units: 9,
      pages: 22,
    ),
    _GuideWork(
      slug: 'moon-tale',
      title: 'حكاية القمر',
      nativeTitle: '月の物語',
      kind: MediaKind.manhua,
      author: 'ليان',
      year: 2026,
      genres: ['تاريخي', 'رومانسي'],
      synopsis:
          'فتاة تعمل في مرصد قديم تكتشف أن القمر يخفي مدينة كاملة، وأن خريطتها على وشك أن تصبح بابًا.',
      units: 15,
      pages: 20,
    ),
    _GuideWork(
      slug: 'neon-seoul',
      title: 'Neon Seoul',
      nativeTitle: '네온 서울',
      kind: MediaKind.drama,
      author: 'Studio Han',
      year: 2025,
      genres: ['Drama', 'Thriller'],
      synopsis:
          'A night-shift courier in Seoul delivers a package that should not exist, and every district it passes through forgets her name.',
      units: 8,
      pages: 0,
      video: _sintelTrailer,
      subtitle: _subtitleSample,
    ),
    _GuideWork(
      slug: 'silent-orbit',
      title: 'Silent Orbit',
      nativeTitle: '静かな軌道',
      kind: MediaKind.anime,
      author: 'Orbit Works',
      year: 2026,
      genres: ['Sci-Fi', 'Slice of Life'],
      synopsis:
          'The last maintenance crew on a dying space station decides to keep the lights on for one more winter.',
      units: 12,
      pages: 0,
      video: _hlsSample,
    ),
    _GuideWork(
      slug: 'tea-house',
      title: 'بيت الشاي',
      nativeTitle: '찻집',
      kind: MediaKind.drama,
      author: 'مينا كيم',
      year: 2024,
      genres: ['دراما', 'عائلي'],
      synopsis:
          'ثلاثة أجيال تدير بيت شاي صغير في مدينة تتغير أسرع من وصفاتهم. كل كوب يحمل اعترافًا مؤجلًا.',
      units: 10,
      pages: 0,
      video: _hlsAlternate,
    ),
    _GuideWork(
      slug: 'magic-orbit',
      title: 'مدار السحر',
      nativeTitle: '마법의 궤도',
      kind: MediaKind.webtoon,
      author: 'سلمى',
      year: 2026,
      genres: ['فانتازيا', 'أكشن'],
      synopsis:
          'في مدينة تطفو فوق السحاب، تُقاس المكانة بعدد الدوائر التي تستطيع رسمها في الهواء. بطلة واحدة ترسم دائرة مفتوحة.',
      units: 24,
      pages: 16,
    ),
    _GuideWork(
      slug: 'last-chapter',
      title: 'الفصل الأخير',
      nativeTitle: '最後の章',
      kind: MediaKind.manga,
      author: 'K. Sato',
      year: 2023,
      genres: ['Drama', 'Mystery'],
      synopsis:
          'An editor receives the final chapter of a manga whose author died ten years ago, written in her own handwriting.',
      units: 6,
      pages: 26,
    ),
  ];

  @override
  Future<List<Media>> popular({int page = 1}) async {
    if (page > 1) return const [];
    return _works.map(_toMedia).toList(growable: false);
  }

  @override
  Future<List<Media>> search(String query, {int page = 1}) async {
    if (page > 1) return const [];
    return _works
        .where((work) =>
            SearchText.matches(work.title, query) ||
            SearchText.matches(work.nativeTitle, query) ||
            SearchText.matches(work.author, query))
        .map(_toMedia)
        .toList(growable: false);
  }

  @override
  Future<Media> details(Media media) async => media;

  @override
  Future<List<MediaUnit>> units(Media media) async {
    final work = _workFor(media);
    final kind = work.kind.isReading ? UnitKind.chapter : UnitKind.episode;
    return List.generate(work.units, (index) {
      final number = index + 1;
      return MediaUnit(
        mediaId: media.id,
        url: 'unit-$number',
        number: number.toDouble(),
        title: kind == UnitKind.chapter ? 'Chapter $number' : 'Episode $number',
        kind: kind,
        publishedAt: DateTime(2026, 1, 1)
            .add(Duration(days: index * 7))
            .millisecondsSinceEpoch,
        pageCount: work.pages,
      );
    }, growable: false);
  }

  @override
  Future<List<MediaResource>> resources(MediaUnit unit) async {
    if (unit.kind == UnitKind.episode) {
      // The unit id is namespaced (`guide::slug::unit-1`), so the work's
      // sample stream is recoverable without asking the catalogue again.
      final slug = unit.mediaId.split('::').skip(1).join('::');
      for (final work in _works) {
        if (work.slug == slug && work.video != null) {
          return [
            VideoResource(work.video!, subtitleUrl: work.subtitle),
          ];
        }
      }
      return const [];
    }

    final pages = unit.pageCount;
    if (pages <= 0) {
      return const [];
    }
    return List.generate(
      pages,
      (index) =>
          SyntheticPage(index, '${unit.displayTitle} · صفحة ${index + 1}'),
      growable: false,
    );
  }

  Media _toMedia(_GuideWork work) {
    return Media(
      ref: SourceRef(sourceId, work.slug),
      title: work.title,
      nativeTitle: work.nativeTitle,
      kind: work.kind,
      author: work.author,
      year: work.year,
      status: MediaStatus.ongoing,
      genres: work.genres,
      synopsis: work.synopsis,
    );
  }

  _GuideWork _workFor(Media media) {
    return _works.firstWhere(
      (work) => work.slug == media.ref.url,
      orElse: () => _works.first,
    );
  }
}

class _GuideWork {
  const _GuideWork({
    required this.slug,
    required this.title,
    required this.nativeTitle,
    required this.kind,
    required this.author,
    required this.year,
    required this.genres,
    required this.synopsis,
    required this.units,
    required this.pages,
    this.video,
    this.subtitle,
  });

  final String slug;
  final String title;
  final String nativeTitle;
  final MediaKind kind;
  final String author;
  final int year;
  final List<String> genres;
  final String synopsis;
  final int units;
  final int pages;
  final String? video;
  final String? subtitle;
}
