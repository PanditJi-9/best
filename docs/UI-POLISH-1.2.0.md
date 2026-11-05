# UI / UX polish pass (design contract 1.2.0)

Scope: visual system, shared components, shell, Home, Library, Browse, Menu,
Series (loading state) and Downloads (loading state). No behaviour, route,
provider or data change; no new dependency.

## Shared layer (`packages/best_ui`)

- `theme.dart`: zero letter spacing in every text role (Arabic joining), page
  transitions, scrollbar / tooltip / switch / slider / popup / expansion
  themes, selected-chip border, error borders on inputs.
- `tokens.dart`: larger minimum type sizes, `BestLayout` (gutter, max content
  width), `BestMotionPolicy` (reduced motion).
- `cover.dart`: fade-in, decode capped to painted width, no glyph flash.
- `skeleton.dart` (new): `BestPulse`, `PosterSkeleton`, `PosterRailSkeleton`,
  `SliverPosterGridSkeleton`, `HeroSkeleton`, `RowSkeleton`, `RowListSkeleton`.
- `press_scale.dart` (new): `BestTapScale`, `BestReveal`.
- `sections.dart`: `SectionHeader`, `PageMasthead`, `EmptyState` redesigned.
- `work_card.dart`, `media_card.dart`: one card language; scroll-aware press.
- `test/polish_test.dart` (new): widget tests for the above.

## App (`apps/best_app`)

- `app.dart`: text scale clamped to 0.9-1.35; themed lock screen.
- `screens/shell_screen.dart`: tab fade, haptic tick, pill indicator.
- `screens/home_screen.dart`: rails bleed to the screen edge, skeleton loading,
  unified headings, search entry, prompt cards.
- `screens/library_screen.dart`, `browse_screen.dart`, `downloads_screen.dart`,
  `series_screen.dart`: skeleton loading states.
- `screens/menu_screen.dart`: bordered cards, icon plates.
- All screens: non-zero `letterSpacing` now goes through
  `BestType.tracking(context, value)`; text below 10.5 px raised.

## Verification done

`best_ui/lib` and the edited screens were analysed with `dart analyze` against
Flutter 3.38.10 sources and `flutter_lints` (stubs for riverpod / go_router /
generated l10n): no findings in the edited code. Run `flutter analyze` and
`flutter test` in the real workspace before release; widget tests were not
executed.
