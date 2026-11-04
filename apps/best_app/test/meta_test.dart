import 'package:best_app/src/l10n/generated/app_localizations_en.dart';
import 'package:best_app/src/meta/meta_labels.dart';
import 'package:best_app/src/meta/meta_models.dart';
import 'package:best_app/src/navigation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final l10n = AppLocalizationsEn();

  group('status labels', () {
    test('maps each provider vocabulary to one sentence', () {
      expect(metaStatusLabel(l10n, 'RELEASING'), 'Airing');
      expect(metaStatusLabel(l10n, 'FINISHED'), 'Finished');
      expect(metaStatusLabel(l10n, 'Finished Airing'), 'Finished');
      expect(metaStatusLabel(l10n, 'NOT_YET_RELEASED'), 'Upcoming');
      expect(metaStatusLabel(l10n, 'completed'), 'Completed');
      expect(metaStatusLabel(l10n, 'ongoing'), 'Ongoing');
      expect(metaStatusLabel(l10n, 'hiatus'), 'On hiatus');
      expect(metaStatusLabel(l10n, 'announced'), 'Announced');
    });

    test('keeps an unknown provider value instead of guessing', () {
      expect(metaStatusLabel(l10n, 'ON BREAK'), 'ON BREAK');
      expect(metaStatusLabel(l10n, null), '');
    });
  });

  group('numbers', () {
    test('formats counts without inventing precision', () {
      expect(metaCount(null), '—');
      expect(metaCount(0), '—');
      expect(metaCount(999), '999');
      expect(metaCount(1500), '1.5K');
      expect(metaCount(1540000), '1.5M');
    });

    test('a missing score stays missing', () {
      expect(metaScoreText(null), '—');
      expect(metaScoreText(8.46), '8.5');
    });
  });

  test('genres are translated only when a translation exists', () {
    expect(metaGenreLabel('Action', true), 'أكشن');
    expect(metaGenreLabel('Action', false), 'Action');
    expect(metaGenreLabel('Unmapped Genre', true), 'Unmapped Genre');
  });

  test('seasons read as a season and a year', () {
    expect(metaSeasonLabel('FALL', 2026, false), 'Fall 2026');
    expect(metaSeasonLabel('FALL', 2026, true), 'الخريف 2026');
    expect(metaSeasonLabel(null, 2019, false), '2019');
  });

  test('meta routes carry the source and id as query parameters', () {
    expect(
      Routes.metaWork(MetaSource.myAnimeList, '52991'),
      '/meta/work?source=myAnimeList&id=52991',
    );
    expect(
      Routes.metaList(MetaListKind.hwaTop),
      '/meta/list?kind=hwaTop',
    );
  });

  test('a work falls back to its romaji title when English is absent', () {
    const work = MetaWork(
      id: '1',
      source: MetaSource.anilist,
      title: 'Sousou no Frieren',
      kind: MetaKind.anime,
    );
    expect(work.displayTitle, 'Sousou no Frieren');

    const translated = MetaWork(
      id: '2',
      source: MetaSource.anilist,
      title: 'Sousou no Frieren',
      englishTitle: 'Frieren: Beyond Journey’s End',
      kind: MetaKind.anime,
    );
    expect(translated.displayTitle, 'Frieren: Beyond Journey’s End');
  });
}
