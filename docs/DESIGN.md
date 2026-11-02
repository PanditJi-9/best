# Best — identity and structure

Version 0.10.0 · "Ink & Ember"

Best is one shelf for manga, manhwa, manhua, webtoons, anime and Asian drama.
The design has to do something hard: feel premium next to Mihon and HikariManga,
stay readable in Arabic and English, and never let chrome outshout the artwork.

This document is the contract. If a screen disagrees with it, the screen is
wrong.

---

## 1. Design thesis

**Ink, ember, and brass.**

- **Ink** is the ground. Warm near-black, not pure black, so OLED phones still
  show the difference between a card and the page.
- **Ember** (`cinnabar`) is action. It marks the one thing to tap and the one
  thing that moved forward.
- **Brass** is for ranks, ratings, section numbers and the second half of the
  signature gradient. It is never a button colour.
- **Jade** is now reserved for progress and offline state. It is the quiet
  counterpoint to the warm chrome, not the primary action colour.

The interface is editorial, not a storefront: a masthead, a numbered section,
a title, a sentence, a cover. The old five-tab skeleton stays, but the page is
printed rather than assembled from floating Material pills.

**Three rules**

1. Artwork carries the colour; chrome stays neutral.
2. Every screen answers "what do I do next?" in one glance.
3. Motion confirms; it never performs.

---

## 2. Tokens

All tokens live in `packages/best_ui/lib/src/tokens.dart`. A screen may not
invent a colour, radius or duration.

### Colour

| Token | Dark | Light | Use |
|-------|------|-------|-----|
| `ink` | `#07080B` | — | App ground (dark) |
| `inkRaised` | `#101218` | — | Cards, nav bar |
| `inkElevated` | `#161922` | — | Inputs, chips, raised rows |
| `inkLine` | `#232733` | — | Hairline borders |
| `paper` | — | `#F7F5F0` | App ground (light) |
| `paperRaised` | — | `#FFFFFF` | Cards, nav bar |
| `paperLine` | — | `#E6E1D7` | Hairline borders |
| `cinnabar` | `#E05A3C` | `#A93620` | Primary action, selected state |
| `brass` | `#CFA85A` | same | Ranks, numbers, rules, gradient end |
| `jade` | `#57B394` | `#2F735C` | Progress and offline state only |
| `danger` | `#E2604D` | same | Destructive and error |
| `rankGold` / `rankSilver` / `rankBronze` | — | — | Leaderboard numerals |

The signature gradient `aurora = [cinnabar, brass]` appears on the wordmark,
the spotlight mark and the profile card. It is **never** a page background.

### Type

Two bundled faces, both OFL:

- **BestDisplay — Amiri.** Display, screen titles, section titles, card titles
  and the wordmark. It gives Arabic and Latin one editorial serif voice.
- **BestText — IBM Plex Sans Arabic.** Body, metadata, labels, controls and
  long Arabic prose. It keeps dense screens legible.

- `displaySmall` — 700, `1.0` height. Masthead titles only.
- `headlineMedium` — 700, `1.08`. Series and secondary titles.
- `headlineSmall` — 700, `1.12`. Spotlight title, card emphasis.
- `titleLarge` — 700, `1.15`. Section titles and stat values.
- `titleMedium` — 600, `0`. Buttons, compact labels.
- `titleSmall` — 600, `1.3`. Card titles.
- `labelLarge` — 700, `0.2`. Buttons.
- `labelMedium` — 600, `0.2`. Metadata.
- `labelSmall` — 600, `0.25`. Section numbers, badges, progress labels.

Arabic and Latin share the scale; every layout uses logical alignment, so no
mirrored stylesheet is needed. CJK native titles fall back to the system face.

### Space, radius, motion

- Space: `4 / 8 / 12 / 16 / 24 / 32` (`BestSpace.xs … xxl`).
- Radius: `6 / 10 / 16 / 22 / pill` (`sm / md / lg / xl / pill`). The page is
  sharper than a typical Material app; the pill is only for progress and
  status dots.
- Motion: `140 ms` fast, `220 ms` normal, `easeOutCubic`. No spring, no bounce.
- Splash: `InkRipple` — the InkSparkle shader is missing in headless tests and
  some older GPUs, and a missing shader is a visible bug.

### Elevation

No drop shadows on cards. Separation comes from a one-pixel border
(`outlineVariant`) plus a slightly raised surface. Shadows are reserved for the
floating cover in the series hero and the spotlight artwork.

---

## 3. Brand

- **Mark** — a four-point sparkle cut from the ember-to-brass gradient, drawn
  with a `CustomPainter` (`BestMark`). The tile is squared off and hairlined.
- **Wordmark** — mark + product name + optional tagline (`BestWordmark`), set in
  Amiri with zero tracking in Arabic. The name is localized (`بست`), so the
  lockup never looks like a translation bolted on.
- **Backdrop** — a blurred, dimmed cover behind a title (`BestBackdrop`). Used
  on series pages and error/empty states where a cover exists.
- **Stat strip** — three numbers in one bordered card (`StatStrip`). Values are
  tabular and scale down instead of overflowing.

The mark is the only place the full gradient is allowed at full strength.

---

## 4. Information architecture

Five destinations. Anything deeper is a pushed route.

| Tab | Route | Question it answers |
|-----|-------|---------------------|
| Home | `/` | What should I do now? |
| Library | `/library` | What do I own? |
| Browse | `/browse` | What exists? |
| Downloads | `/downloads` | What is offline? |
| Settings | `/settings` | How does Best behave? |

Routes: `/series?source=&url=`, `/read?source=&url=&unit=`,
`/watch?source=&url=&unit=`. Source ids and URLs are query parameters, never
path segments — a source URL can contain slashes and dots.

`openUnit` chooses `/read` or `/watch` from `MediaKind.isReading`; screens never
branch on a source name.

### Why five, not four

The previous build had four tabs (Library, Browse, Downloads, Settings). It
forced the app to open on an empty shelf, which is the worst first impression a
media app can make. Home earns the first slot by giving a fresh install a
spotlight, the sample films and one obvious "open the guide" action. Downloads
keeps its own tab because offline is a promise, not a preference.

### The index bar

- 64 px tall (plus the safe-area inset), flat, with a one-pixel
  `outlineVariant` hairline and the page surface behind it. No floating pill,
  no shadow.
- Five equal columns. The selected column gets a 2 px ember rule at its top
  edge, a filled icon and an ember label; the other four use outlined icons and
  muted labels.
- Labels are always shown at 9.5 px with **zero tracking**, wrapped in a
  `FittedBox` so "Downloads", "التنزيلات" and large text scales stay on one
  line on a 320 dp phone. A widget test at 320×640 pins that layout.
- The selected tab is a `Semantics(selected: true)` button; the label is the
  accessible name, not the icon.

---

## 5. Screen blueprints

### Home — the front door

1. **Masthead** — localized wordmark + tagline, a squared search button, and a
   hairline that closes the band.
2. **Search prompt** — a tappable field that jumps to Browse. It looks like an
   input but is a route, so there is no half-working search on Home.
3. **Spotlight** — 4:5 editorial card: cover, warm scrim, printed kind label,
   mark, title in Amiri, native title, year · status · author, a primary
   "Start reading/watching" bar and a squared arrow. One work only.
4. **Continue rail (01)** — 302×164 slips with cover, title, progress rule and
   a page/clock label. Appears only when there is progress.
5. **Picks (02)** — the curated shelf, unranked.
6. **Trending (03)** — ranked horizontal rail; outlined brass numerals sit on
   the artwork.
7. **Sample films (04)** — public-domain streams so the player is reachable in
   two taps without a source pack.
8. **Library-waiting card** — shown only when the shelf is empty; explains the
   guide and offers one button.

Refresh invalidates the guide, continue and library providers together.

### Library — what you own

- Masthead `02`: title + `librarySummary(count)` + sort action.
- Search field with a 240 ms debounce.
- Continue rail (same `ContinueCard` as Home, same label helper).
- Filter chips: All / Unread / In progress / Completed / Favorites.
- Sort menu: title, recently read, recently added.
- Responsive grid of `MediaCard`s; no repeated "Library" section header.
- Empty state: guide action, not a dead end.

### Browse — what exists

- Masthead `03`: title + `browseSubtitle(sourceCount)` + mark.
- Source chips: selected chip uses `primaryContainer`, a check icon and an
  ember border. A source is one tap away, never a form.
- Search field scoped to the selected source.
- Result count, then a responsive grid sized from the viewport
  (`columns = width / 170`, clamped 2–6).
- Pull to refresh re-fetches the current query.

### Series — the work

1. **Hero** — 300 px blurred cover, scrim to the page colour, and a 124×186
   cover floating half-in/half-out. No negative margins, no overflow.
2. **Identity** — centered title, native title, kind · year · status · offline
   count, author, genre pills.
3. **Actions** — primary continue/start button, circular favorite and library
   buttons. All 52×52.
4. **Stat strip** — units / offline / percent complete.
5. **Synopsis** — four lines with More/Less.
6. **Unit list** — section header with count and a "download all" action.
   Each row is a card: progress ring or check, title, date · pages, download
   control, numbered chip.
7. **Floating glass back button** over the hero.

### Reader — pages

- Pure black, edge-to-edge.
- App bar: 14 px blur over 45% black, unit title + series title, offline badge.
- `PageView` with `InteractiveViewer` (1–4×) for images, `Image.file` for
  offline pages.
- Bottom overlay (ignores pointer events): page x of y — or "End of this unit"
  with a jade check on the last page — the series name, a 3 px jade progress
  bar, and safe-area padding.
- Progress saves 320 ms after a page change and again on dispose. Completed at
  the last page; a completed row never moves backwards.

### Watch — episodes

- `video_player` (ExoPlayer/Media3) with wakelock.
- Auto-hiding controls, center play/pause, 10-second skip, speed sheet,
  fullscreen, replay at the end.
- Progress in seconds; resume at ≥3 s; finished at 95% or the last 5 s.
- Errors show the localized playback message, not a raw exception.

### Downloads — what is offline

- Masthead `04`: title + storage line, clear-finished action.
- `StatStrip`: offline / in progress / storage.
- Section "In progress" (queued, running, paused, failed) and "Ready offline"
  (done). Each tile: status tile, media + unit, progress or error, pause/resume/
  retry/delete, open.
- Empty state: explanation + a Browse button.
- The queue lives in the shell, so leaving the tab never pauses a download.

### Settings — your copy of Best

- Masthead `05`: title + "Make Best yours".
- **Profile card**: mark, name, tagline, "Reader" badge, and works / offline /
  sources. Identity before configuration.
- **Language**: segmented System / English / العربية.
- **Appearance**: segmented System / Light / Dark.
- **Sources**: built-in MangaDex and Best Guide, installed packs, add-pack
  action. A pack is declarative JSON; nothing executes.
- **About**: mark, name, tagline, version note, verified icon.

---

## 6. Components

| Component | File | Contract |
|-----------|------|----------|
| `BestMark`, `BestWordmark`, `BestBackdrop`, `StatStrip` | `brand.dart` | Brand surfaces; no app strings except a passed label. |
| `SpotlightCard`, `ContinueCard` | `cards.dart` | Editorial hero and resume card. |
| `MediaCard` | `media_card.dart` | Shelf card with badge, rank numeral and optional progress. |
| `SectionHeader`, `PageMasthead`, `EmptyState` | `sections.dart` | Numbered section; page masthead `02–05`; empty state with eyebrow + action. |
| `BestCover` | `cover.dart` | Deterministic gradient fallback when art is missing. |
| `bestTheme` | `theme.dart` | One builder for both brightnesses. |

`best_ui` never imports the app's localization. Every visible string is passed
in, which keeps the package reusable and testable.

---

## 7. States and feedback

- **Loading** — a centered spinner only for the first paint of a provider.
  Pull-to-refresh keeps the old content visible.
- **Error** — `EmptyState` with a plain-language title, the technical detail in
  small text, and a Retry button. No red-on-black framework banner.
- **Empty** — eyebrow, icon in an ember/brass plate, title, one sentence, one
  action.
- **Offline** — jade badge in the reader; offline counts on the series page.
- **Destructive** — confirmation dialog with the count of affected items.
- **Success** — floating snackbar, never a full-screen toast.

---

## 8. Arabic, RTL and accessibility

- Every layout uses `EdgeInsetsDirectional`, `PositionedDirectional`,
  `AlignmentDirectional` and `MainAxisAlignment`-independent spacing.
- No hard-coded left/right for anything that carries meaning.
- Numbers stay Western in both languages: a scrubber and a page counter are
  number lines, not prose.
- Dates use `YYYY-MM-DD`; storage uses `KB/MB/GB`.
- Minimum tap target 44×44; primary buttons 52 high; icon buttons 42–52.
- Semantic labels on cards (`Semantics(button: true, label: title)`).
- Contrast: ember on ink ≥ 5:1, onSurfaceVariant on ink ≥ 4.6:1, dark ink on
  ember ≥ 5:1.
- Text scales: cards use `maxLines` + ellipsis rather than fixed heights where
  possible; the stat strip scales values down instead of clipping.

---

## 9. Performance rules

- No `BackdropFilter` on scrolling lists; only on the reader app bar and modal
  sheets.
- The reader uses `Image.network` with a loading builder and an error icon; no
  full-resolution decode of off-screen pages beyond `PageView`'s cache.
- The download queue is a single manager watched by the shell; tiles read from
  the same provider, never poll.
- Grid extents are computed from `MediaQuery.sizeOf`, so a tablet gets more
  columns instead of stretched cards.
- Motion never exceeds 220 ms and never blocks input.

---

## 10. What we rejected

- **A sixth "Profile" tab.** HikariManga puts profile in the nav; Best's profile
  is the top of Settings. Five is the maximum before labels collide in Arabic.
- **A store-first home.** The shop is Browse. Home is yours.
- **Coin timers and daily rewards.** They convert, but they make a reading app
  feel like a game.
- **Dynamic colour.** A wallpaper-derived seed would erase the identity. The
  palette is fixed until a real-device review says otherwise.
- **Drift/ORM.** SQLite through `sqflite_common` is enough for the current
  schema and keeps startup predictable.
- **A carousel on Home.** One spotlight is editorial; five auto-rotating covers
  are noise.

---

## 11. Implementation map

```
packages/best_ui/lib/src/
  tokens.dart      palette, space, radius, motion
  theme.dart       Material 3 scheme + component themes
  brand.dart       mark, wordmark, backdrop, stat strip
  cards.dart       spotlight, continue card
  media_card.dart  shelf card
  sections.dart    section header, empty state
apps/best_app/lib/src/
  navigation.dart  routes
  router.dart      shell branches (Home first)
  screens/         home, library, browse, series, reader, watch,
                   downloads, settings, shell
  progress_label.dart  shared page/clock label
  l10n/            EN + AR ARB files
```

Gates for every release: `flutter analyze` clean, package tests green, release
APK built in CI, emulator smoke reaching the player, and a browser/device render
check with a clean console.
