import 'dart:convert';

import 'package:best_domain/best_domain.dart';
import 'package:test/test.dart';

void main() {
  group('ReaderPreferences', () {
    test('old installations keep single-page defaults', () {
      final preferences = ReaderPreferences.fromJson(const {});
      expect(preferences, const ReaderPreferences());
      expect(preferences.spreadMode, ReaderSpreadMode.single);
      expect(preferences.coverAlone, isTrue);
    });

    test('every presentation choice survives a JSON round trip', () {
      const original = ReaderPreferences(
        mode: ReaderMode.vertical,
        direction: ReaderDirection.rtl,
        fit: ReaderFit.width,
        background: ReaderBackground.sepia,
        tapZones: false,
        webtoonGap: 16,
        filterMode: 'invert',
        brightness: -40,
        spreadMode: ReaderSpreadMode.adaptive,
        coverAlone: false,
      );
      final decoded =
          jsonDecode(jsonEncode(original.toJson())) as Map<String, Object?>;
      expect(ReaderPreferences.fromJson(decoded), original);
      expect(ReaderPreferences.fromJson(decoded).hashCode, original.hashCode);
    });

    test(
        'invalid fields fall back independently, not by throwing away the profile',
        () {
      final preferences = ReaderPreferences.fromJson(const {
        'mode': 'diagonal',
        'direction': 'rtl',
        'fit': 9,
        'background': 'neon',
        'tapZones': 'false',
        'webtoonGap': 999,
        'filterMode': 'unknown',
        'brightness': -999,
        'spreadMode': 'quadruple',
        'coverAlone': null,
      });
      expect(preferences.direction, ReaderDirection.rtl);
      expect(preferences.mode, ReaderMode.paged);
      expect(preferences.fit, ReaderFit.screen);
      expect(preferences.background, ReaderBackground.black);
      expect(preferences.tapZones, isTrue);
      expect(preferences.webtoonGap, 32);
      expect(preferences.brightness, -75);
      expect(preferences.filterMode, 'none');
      expect(preferences.spreadMode, ReaderSpreadMode.single);
      expect(preferences.coverAlone, isTrue);
    });

    test('non-integer gap and brightness values are ignored', () {
      final preferences = ReaderPreferences.fromJson(const {
        'webtoonGap': 8.5,
        'brightness': 'dark',
      });
      expect(preferences.webtoonGap, 0);
      expect(preferences.brightness, 0);
    });

    test('copying clamps gaps and dimming without changing the original', () {
      const original = ReaderPreferences(direction: ReaderDirection.rtl);
      final copy = original.copyWith(webtoonGap: -8, brightness: 50);
      expect(copy.webtoonGap, 0);
      expect(copy.brightness, 0);
      expect(copy.direction, ReaderDirection.rtl);
      expect(original, const ReaderPreferences(direction: ReaderDirection.rtl));
      expect(
          original.copyWith(webtoonGap: 100, brightness: -100).webtoonGap, 32);
      expect(original.copyWith(brightness: -100).brightness, -75);
    });

    test('changing the cover or spread mode changes value equality', () {
      const original = ReaderPreferences();
      expect(original.copyWith(), original);
      expect(original.copyWith(coverAlone: false), isNot(original));
      expect(original.copyWith(spreadMode: ReaderSpreadMode.adaptive),
          isNot(original));
    });

    test('single-page mode stays single even on a large landscape display', () {
      expect(const ReaderPreferences().usesSpreads(width: 1200, height: 800),
          isFalse);
    });

    test('adaptive spreads require wide landscape content space', () {
      const adaptive = ReaderPreferences(spreadMode: ReaderSpreadMode.adaptive);
      expect(adaptive.usesSpreads(width: 1000, height: 700), isTrue);
      expect(adaptive.usesSpreads(width: 720, height: 600), isTrue);
      expect(adaptive.usesSpreads(width: 700, height: 500), isFalse);
      expect(adaptive.usesSpreads(width: 800, height: 1000), isFalse);
      expect(adaptive.usesSpreads(width: 800, height: 800), isFalse);
    });

    test('explicit spreads work on a tablet but never shrink a portrait phone',
        () {
      const doublePage =
          ReaderPreferences(spreadMode: ReaderSpreadMode.doublePage);
      expect(doublePage.usesSpreads(width: 800, height: 1200), isTrue);
      expect(doublePage.usesSpreads(width: 390, height: 844), isFalse);
      expect(doublePage.usesSpreads(width: 599, height: 400), isFalse);
    });

    for (final fit in [ReaderFit.width, ReaderFit.original]) {
      test('$fit keeps its scroll/pan surface even with spreads selected', () {
        final preferences = ReaderPreferences(
          fit: fit,
          spreadMode: ReaderSpreadMode.doublePage,
        );
        expect(preferences.usesSpreads(width: 1200, height: 800), isFalse);
      });
    }

    test('webtoons never pair pages', () {
      const preferences = ReaderPreferences(
        mode: ReaderMode.vertical,
        spreadMode: ReaderSpreadMode.doublePage,
      );
      expect(preferences.usesSpreads(width: 1200, height: 800), isFalse);
    });

    test('invalid or unbounded viewport dimensions are rejected', () {
      const preferences =
          ReaderPreferences(spreadMode: ReaderSpreadMode.doublePage);
      expect(preferences.usesSpreads(width: double.infinity, height: 800),
          isFalse);
      expect(preferences.usesSpreads(width: double.nan, height: 800), isFalse);
      expect(preferences.usesSpreads(width: 900, height: 0), isFalse);
      expect(preferences.usesSpreads(width: 900, height: double.infinity),
          isFalse);
    });
  });

  group('ReaderPageLayout', () {
    test('empty chapters have no view or selectable page', () {
      const layout = ReaderPageLayout(pageCount: 0, doublePage: true);
      expect(layout.viewCount, 0);
      expect(layout.pagesForView(0), isEmpty);
      expect(layout.viewForPage(100), 0);
      expect(layout.lastVisiblePage(0), 0);
    });

    test('single pages map one to one', () {
      const layout = ReaderPageLayout(pageCount: 4);
      expect(layout.viewCount, 4);
      for (var page = 0; page < 4; page++) {
        expect(layout.viewForPage(page), page);
        expect(layout.pagesForView(page), [page]);
      }
    });

    test('the cover is alone and the remaining scans are paired', () {
      const layout = ReaderPageLayout(pageCount: 6, doublePage: true);
      expect(layout.viewCount, 4);
      expect(layout.pagesForView(0), [0]);
      expect(layout.pagesForView(1), [1, 2]);
      expect(layout.pagesForView(2), [3, 4]);
      expect(layout.pagesForView(3), [5]);
    });

    test('pairing may start at the first scan when cover-alone is disabled',
        () {
      const layout = ReaderPageLayout(
        pageCount: 5,
        doublePage: true,
        coverAlone: false,
      );
      expect(layout.viewCount, 3);
      expect(layout.pagesForView(0), [0, 1]);
      expect(layout.pagesForView(1), [2, 3]);
      expect(layout.pagesForView(2), [4]);
    });

    test('both pages of a spread map to the same viewport', () {
      const layout = ReaderPageLayout(pageCount: 7, doublePage: true);
      expect(layout.viewForPage(1), 1);
      expect(layout.viewForPage(2), 1);
      expect(layout.viewForPage(3), 2);
      expect(layout.viewForPage(4), 2);
      expect(layout.lastVisiblePage(3), 4);
      expect(layout.lastVisiblePage(5), 6);
    });

    test('one-page chapters are valid in either pairing mode', () {
      for (final coverAlone in [false, true]) {
        final layout = ReaderPageLayout(
          pageCount: 1,
          doublePage: true,
          coverAlone: coverAlone,
        );
        expect(layout.viewCount, 1);
        expect(layout.pagesForView(0), [0]);
        expect(layout.lastVisiblePage(0), 0);
      }
    });

    test('out-of-range jumps are clamped in source page coordinates', () {
      const layout = ReaderPageLayout(pageCount: 5, doublePage: true);
      expect(layout.viewForPage(-1), 0);
      expect(layout.viewForPage(99), 2);
      expect(layout.pagesForView(-1), [0]);
      expect(layout.pagesForView(99), [3, 4]);
    });

    test('rotation never changes the bookmark or resume page number', () {
      const portrait = ReaderPageLayout(pageCount: 30);
      const landscape = ReaderPageLayout(pageCount: 30, doublePage: true);
      for (var page = 0; page < 30; page++) {
        expect(landscape.pagesForView(landscape.viewForPage(page)),
            contains(page));
        expect(portrait.pagesForView(portrait.viewForPage(page)), [page]);
      }
    });

    test(
        'every source page appears exactly once for odd and even chapter sizes',
        () {
      for (var count = 0; count < 200; count++) {
        for (final paired in [false, true]) {
          for (final coverAlone in [false, true]) {
            final layout = ReaderPageLayout(
              pageCount: count,
              doublePage: paired,
              coverAlone: coverAlone,
            );
            final pages = [
              for (var view = 0; view < layout.viewCount; view++)
                ...layout.pagesForView(view),
            ];
            expect(pages, List<int>.generate(count, (index) => index));
            for (var view = 0; view < layout.viewCount; view++) {
              for (final page in layout.pagesForView(view)) {
                expect(layout.viewForPage(page), view);
              }
            }
          }
        }
      }
    });

    test('layout identity includes pairing and cover alignment', () {
      const layout = ReaderPageLayout(pageCount: 4, doublePage: true);
      expect(layout, const ReaderPageLayout(pageCount: 4, doublePage: true));
      expect(layout, isNot(const ReaderPageLayout(pageCount: 4)));
      expect(
          layout,
          isNot(const ReaderPageLayout(
            pageCount: 4,
            doublePage: true,
            coverAlone: false,
          )));
    });
  });
}
