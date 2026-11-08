import 'package:best_app/src/extension_host.dart';
import 'package:best_app/src/providers.dart';
import 'package:best_data/best_data.dart';
import 'package:best_domain/best_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Media _media(
  String url, {
  required String title,
  List<String> genres = const [],
  double? rating,
}) =>
    Media(
      ref: SourceRef('mangadex', url),
      title: title,
      kind: MediaKind.manga,
      genres: genres,
      rating: rating,
    );

ExtensionEntry _entry({
  required String name,
  required String repository,
  required String kind,
  required List<ExtensionSite> sites,
}) =>
    ExtensionEntry(
      name: name,
      packageName: 'pkg.$name',
      apkUrl: 'https://example.test/$name.apk',
      language: sites.isEmpty ? 'all' : sites.first.language,
      version: '1.0',
      nsfw: false,
      kind: kind,
      sources: sites,
      repositoryUrl: repository,
    );

void main() {
  test('publishers group the directory by the account that signs it', () async {
    const kei = 'https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.json';
    const yuzono = 'https://raw.githubusercontent.com/yuzono/anime-repo/repo/index.min.json';
    final directory = ExtensionDirectory(
      entries: [
        _entry(
          name: 'MangaDex',
          repository: kei,
          kind: 'manga',
          sites: const [
            ExtensionSite(
              name: 'MangaDex EN',
              language: 'en',
              homeUrl: 'https://mangadex.org',
            ),
            ExtensionSite(
              name: 'MangaDex AR',
              language: 'ar',
              homeUrl: 'https://mangadex.org',
            ),
          ],
        ),
        _entry(
          name: 'MangaLeek',
          repository: kei,
          kind: 'manga',
          sites: const [
            ExtensionSite(
              name: 'مانجا ليك',
              language: 'ar',
              homeUrl: 'https://mangalik.net',
            ),
          ],
        ),
        _entry(
          name: 'AniZone',
          repository: yuzono,
          kind: 'anime',
          sites: const [
            ExtensionSite(
              name: 'AniZone',
              language: 'en',
              homeUrl: 'https://anizone.to',
            ),
          ],
        ),
      ],
    );

    final container = ProviderContainer(
      overrides: [
        extensionDirectoryProvider.overrideWith((ref) async => directory),
      ],
    );
    addTearDown(container.dispose);

    final publishers = await container.read(publishersProvider.future);

    expect(publishers.extensions, 3);
    expect(publishers.sources, 4);
    expect(publishers.items.map((item) => item.name), ['keiyoushi', 'yuzono']);
    final keiyoushi = publishers.items.first;
    expect(keiyoushi.extensions, 2);
    expect(keiyoushi.sources, 3);
    expect(keiyoushi.languages, ['ar', 'en']);
    expect(keiyoushi.hasAnime, isFalse);
    expect(publishers.items.last.hasAnime, isTrue);
    expect(publishers.items.last.url, 'https://github.com/yuzono');
  });

  test('recommendations intersect the shelf genres with the live pool',
      () async {
    final owned = _media('owned', title: 'Owned', genres: ['Fantasy']);
    final fantasy = _media('fantasy', title: 'Fantasy', genres: ['Fantasy'],
        rating: 9);
    final romance = _media('romance', title: 'Romance', genres: ['Romance'],
        rating: 8.5);
    final fresh = _media('fresh', title: 'Fresh', genres: ['Fantasy']);
    final repository = MemoryLibraryRepository();
    addTearDown(repository.close);
    await repository.saveMedia(owned.copyWith(inLibrary: true));

    final container = ProviderContainer(
      overrides: [
        repositoryProvider.overrideWithValue(repository),
        rankingsProvider.overrideWith(
          (ref) async => Rankings(
            works: [fantasy, owned, romance],
            live: true,
          ),
        ),
        discoverProvider.overrideWith(
          (ref) async => DiscoverFeed(
            works: [fresh],
            latest: const [],
            live: true,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final recs = await container.read(recommendationsProvider.future);

    expect(recs.personalised, isTrue);
    expect(recs.genres, ['fantasy']);
    expect(recs.works.map((work) => work.title), ['Fantasy', 'Fresh']);
  });

  test('recommendations fall back to the top rated list without a shelf',
      () async {
    final top = _media('top', title: 'Top', rating: 9.2);
    final repository = MemoryLibraryRepository();
    addTearDown(repository.close);
    final container = ProviderContainer(
      overrides: [
        repositoryProvider.overrideWithValue(repository),
        rankingsProvider.overrideWith(
          (ref) async => Rankings(works: [top], live: true),
        ),
        discoverProvider.overrideWith(
          (ref) async => const DiscoverFeed(works: [], live: false),
        ),
      ],
    );
    addTearDown(container.dispose);

    final recs = await container.read(recommendationsProvider.future);

    expect(recs.personalised, isFalse);
    expect(recs.works.single.title, 'Top');
  });

  test('weekly rewards derive badges from real activity', () async {
    final container = ProviderContainer(
      overrides: [
        readingStatsProvider.overrideWith(
          (ref) async => ReadingStats(
            works: 4,
            completedUnits: 12,
            pages: 640,
            streakDays: 4,
            week: [
              DailyActivity(day: '2026-11-01', pages: 120),
              DailyActivity(day: '2026-11-02', pages: 90),
            ],
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final rewards = await container.read(weeklyRewardsProvider.future);

    expect(rewards.weekPages, 210);
    expect(rewards.goal, 300);
    expect(rewards.progress, closeTo(0.7, 0.001));
    expect(
      rewards.earned,
      containsAll([
        RewardBadge.firstUnit,
        RewardBadge.streak3,
        RewardBadge.pages100,
        RewardBadge.pages300,
      ]),
    );
    expect(rewards.earned, isNot(contains(RewardBadge.pages1000)));
    expect(rewards.earned, isNot(contains(RewardBadge.streak7)));
  });
}
