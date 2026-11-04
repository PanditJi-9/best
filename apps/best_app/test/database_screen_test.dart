import 'package:best_app/src/l10n/generated/app_localizations.dart';
import 'package:best_app/src/meta/meta_models.dart';
import 'package:best_app/src/meta/meta_providers.dart';
import 'package:best_app/src/screens/database_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const MetaWork _frieren = MetaWork(
  id: '52991',
  source: MetaSource.myAnimeList,
  kind: MetaKind.anime,
  title: 'Sousou no Frieren',
  englishTitle: 'Frieren: Beyond Journey’s End',
  score: 9.24,
  scoreSource: 'MyAnimeList',
  rank: 1,
  votes: 1540103,
  format: 'TV',
  episodes: 28,
  status: 'Finished Airing',
  year: 2023,
  genres: ['Adventure', 'Drama', 'Fantasy'],
  synopsis: 'An elf mage outlives her party and learns to know humans.',
);

const MetaWork _solo = MetaWork(
  id: 'solo-leveling',
  source: MetaSource.hwa,
  kind: MetaKind.manhwa,
  title: 'Solo Leveling',
  nativeTitle: '나 혼자만 레벨업',
  score: 8.5,
  scoreSource: 'MangaUpdates',
  status: 'completed',
  year: 2018,
  genres: ['Action'],
);

const MetaNews _news = MetaNews(
  title: 'A new anime adaptation is announced',
  url: 'https://animecorner.me/example/',
  summary: 'The studio revealed a teaser and a cast list.',
  category: 'Anime News',
  author: 'Ken Pueyo',
);

/// The real app puts this screen inside the shell's Scaffold; the test does
/// the same so ink widgets find their Material ancestor.
Future<ProviderContainer> _pump(
  WidgetTester tester,
  MetaHome home, {
  Locale? locale,
  List<MetaWork>? manhwa,
}) async {
  final container = ProviderContainer(
    overrides: [
      metaHomeProvider.overrideWith((ref) async => home),
      // The shelf is its own provider in production; the harness feeds it the
      // same fixture so no test touches the network.
      metaManhwaProvider.overrideWith((ref) async => manhwa ?? home.topManhwa),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: DatabaseScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _reveal(WidgetTester tester, String text) async {
  await tester.scrollUntilVisible(
    find.text(text),
    280,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the database shows every provider section with its own score', (
    tester,
  ) async {
    await _pump(
      tester,
      const MetaHome(
        trending: [_frieren],
        airing: [_frieren],
        topMal: [_frieren],
        topManhwa: [_solo],
        news: [_news],
      ),
    );

    expect(find.text('The Database'), findsOneWidget);

    // The same work leads the hero and the MAL ranking, so the title appears
    // more than once. The hero already carries its community's score.
    expect(find.text('Frieren: Beyond Journey’s End'), findsWidgets);
    expect(find.text('9.2'), findsWidgets);

    // The hero badge also says "Trending now", so scroll to the rail's
    // subtitle to land on the section itself.
    await _reveal(tester, 'By AniList');
    expect(find.text('Trending now'), findsWidgets);
    await _reveal(tester, 'Top on MyAnimeList');
    expect(find.text('Full ranking'), findsOneWidget);

    await _reveal(tester, 'Manhwa spotlight');
    expect(find.text('Solo Leveling'), findsWidgets);
    expect(find.text('hwa.so'), findsWidgets);
    expect(find.textContaining('MangaUpdates'), findsWidgets);

    await _reveal(tester, 'Anime news');
    expect(find.text('A new anime adaptation is announced'), findsOneWidget);

    // The attribution note closes the page, after the last rail.
    await tester.scrollUntilVisible(
      find.textContaining('Each community keeps its own score'),
      280,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Each community keeps its own score'),
      findsOneWidget,
    );
  });

  testWidgets('a provider failure is named without hiding the rest', (
    tester,
  ) async {
    await _pump(
      tester,
      const MetaHome(
        topManhwa: [_solo],
        failures: {
          MetaSource.anilist: 'AniList rate limit reached.',
          MetaSource.myAnimeList: 'Request timed out.',
        },
      ),
    );

    await _reveal(tester, 'AniList · MyAnimeList');
    expect(find.text('Solo Leveling'), findsWidgets);
  });

  testWidgets('the database reads right-to-left in Arabic', (tester) async {
    await _pump(
      tester,
      const MetaHome(topManhwa: [_solo]),
      locale: const Locale('ar'),
    );

    expect(find.text('الموسوعة'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.text('الموسوعة'))),
      TextDirection.rtl,
    );
  });

  testWidgets('the manhwa shelf fills from its own provider', (tester) async {
    // hwa.so is slower than the other catalogues, so the shelf must arrive on
    // its own without holding back the rest of the page.
    await _pump(
      tester,
      const MetaHome(trending: [_frieren]),
      manhwa: const [_solo],
    );

    expect(find.text('The Database'), findsOneWidget);
    await _reveal(tester, 'Manhwa spotlight');
    expect(find.text('Solo Leveling'), findsWidgets);
    expect(find.textContaining('MangaUpdates'), findsWidgets);
  });
}
