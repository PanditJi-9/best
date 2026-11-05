# Best — identity and structure

Version 1.2.0 · "Ink & Aurora"

Best is one shelf for manga, manhwa, manhua, webtoons, anime and Asian drama.
The design has to do something hard: feel premium next to Mihon and HikariManga,
stay readable in Arabic and English, and never let chrome outshout the artwork.

This document is the contract. If a screen disagrees with it, the screen is
wrong.

---

## 1. Design thesis

**Ink and aurora.**

- **Ink** is the ground: deep blue-black in dark mode and cool paper in light mode.
- **Blue** is the primary action and the selected state. It should identify the next useful tap, not decorate every surface.
- **Cyan** supports the blue in the mark and occasional progress emphasis.
- **Gold** marks ratings and ranks. **Jade** is reserved for completed and offline states.
- Artwork carries most of the colour; controls stay quiet and readable in Arabic and English.

Best is a personal media shelf, not a storefront. Every screen should make the next action obvious, keep local progress visible, and use motion only to confirm a change.

---

## 2. Tokens

All tokens live in `packages/best_ui/lib/src/tokens.dart`. A screen may not
invent a colour, radius or duration.

### Colour

All values below are sourced from `packages/best_ui/lib/src/tokens.dart`. Use
these tokens instead of introducing screen-specific colours.

| Token | Value | Use |
|-------|-------|-----|
| `inkDeep` | `#05080F` | Dark hero and reader surfaces |
| `ink` | `#070B14` | Dark app background |
| `inkRaised` / `inkElevated` | `#0C1322` / `#111A2B` | Cards and inputs |
| `paper` / `paperRaised` | `#F5F7FA` / `#FFFFFF` | Light background and cards |
| `blue` | `#3B82F6` | Primary action and selected state |
| `cyan` | `#22D3EE` | Signature gradient and secondary emphasis |
| `gold` | `#F5B942` | Ratings and rank numerals |
| `jade` | `#34D399` | Progress and offline state |
| `danger` | `#F87171` | Errors and destructive actions |

The signature gradient `aurora = [blue, cyan]` belongs on the mark and a small
number of meaningful progress moments. Never use it as a page background.

---

### Type

The app UI uses the bundled IBM Plex Sans Arabic family for headings, controls,
metadata, and body text. It stays readable in Arabic and English and avoids
turning every catalogue title into a decorative headline. Amiri is reserved for
small display moments and the deterministic cover fallback. CJK native titles
fall back to the system face.

- Page titles are strong and compact; section titles are 17–21 px.
- Poster titles are 14 px, with up to two lines. Metadata is 11.5 px and body
  copy on cards 12.5 px. Nothing outside the reader and player overlays is set
  below 10.5 px: Arabic needs more optical size than Latin to stay legible.
- Metadata is muted but remains readable against both surfaces.
- **Letter spacing is zero in every theme text role.** Flutter turns off letter
  joining as soon as `letterSpacing != 0`, which breaks the cursive connection
  inside Arabic words. Latin tracking is applied per role through
  `BestType.tracking(context, value)`, which returns 0 in RTL. A screen never
  writes a bare non-zero `letterSpacing` on text that can be Arabic.
- Text truncates at deliberate line boundaries. The app clamps the system text
  scale to 0.9–1.35 so fixed-height rails and grid cells never clip a title.

### Space, radius, motion

- Space: `4 / 8 / 12 / 16 / 24 / 32` (`BestSpace.xs … xxl`).
- Radius: `6 / 10 / 16 / 22 / pill` (`sm / md / lg / xl / pill`). The page is
  sharper than a typical Material app; the pill is only for progress and
  status dots.
- Motion: `140 ms` fast, `220 ms` normal, `340 ms` slow, `easeOutCubic`. No
  spring, no bounce. Every decorative animation asks `BestMotionPolicy.reduced`
  first and stays still when the system has animations turned off.
- Gutter: `BestLayout.gutter` (20 dp). Rails bleed to the screen edge and carry
  the gutter on their own first and last item.
- Splash: `InkRipple` — the InkSparkle shader is missing in headless tests and
  some older GPUs, and a missing shader is a visible bug.

### Elevation

No drop shadows on cards. Separation comes from a one-pixel border
(`outlineVariant`) plus a slightly raised surface. Shadows are reserved for the
floating cover in the series hero and the spotlight artwork.

---

## 3. Brand

- **Mark** — a four-point sparkle cut from the blue-to-cyan gradient, drawn
  with a `CustomPainter` (`BestMark`). The tile is squared off and hairlined.
- **Wordmark** — mark + localized product name + optional tagline
  (`BestWordmark`), set in the app UI face with zero tracking in Arabic.
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
| Database | `/database` | What is worth discovering? |
| Library | `/library` | What do I own? |
| Downloads | `/downloads` | What is offline? |
| Menu | `/menu` | Where are the rest of my tools? |

Routes: `/series?source=&url=`, `/read?source=&url=&unit=`,
`/watch?source=&url=&unit=`. Source ids and URLs are query parameters, never
path segments — a source URL can contain slashes and dots.

`openUnit` chooses `/read` or `/watch` from `MediaKind.isReading`; screens never
branch on a source name.

### Why these five

Home gives a fresh install a clear next step. Database is for broad metadata
discovery; Browse is a pushed screen for searching installed sources. Library
and Downloads stay one tap away, while Menu groups settings, backups, history,
and supporting tools instead of crowding the main navigation.

### The index bar

- 64 px tall plus the safe-area inset, flat, with a one-pixel outline and no
  shadow.
- Five equal columns. The selected column puts its filled icon on a 52×30 blue
  pill (16% tint) that grows from the 40 px resting width, with a blue label;
  the other four use outlined icons and muted labels.
- Switching tabs gives a light haptic tick and eases the new page in with a
  220 ms fade (never a slide: tabs are peers, not steps).
- Labels stay visible and scale down when needed so English and Arabic fit on
  small phones. Keep the selected tab accessible through `Semantics`.

## 5. Screen blueprints

### Home — the front door

1. **Wordmark** — localized Best mark and tagline, with a quiet news action.
2. **Unified search** — one obvious entry point for title discovery.
3. **Continue hero** — artwork fills a wide card; the title, exact chapter or
   episode, progress and next action sit on a strong bottom scrim. Reading and
   watching use the correct action label.
4. **Your sources** — compact source chips open directly into that catalogue;
   Add source stays at the end of the rail.
5. **Discover** — a small set of media-kind filters followed by recent source
   updates and personalized picks. Empty and error states always offer a next
   action.

The hero adapts its height to the available width. On wide layouts the tab
content is centered and capped instead of stretching text and cards edge to edge.

### Library — what you own

- Title, library count, view toggle, and sort action share one compact header.
- Search and filters stay visible while the shelf scrolls.
- Continue rail appears only for the unfiltered library.
- Grid and row modes use the same `WorkCard` language and preserve progress.
- Grid sizing follows the actual sliver width, including split-screen and
  tablet layouts.
- Empty and filtered-empty states explain the difference and offer a useful
  action.

### Browse — what exists

- Search spans all installed sources by default; selecting a source scopes it.
- Source chips stay one tap away, long names truncate cleanly, and the chosen
  source is always visible. Add source stays at the end of the rail.
- Results use a poster grid sized from the actual available width; pull to
  refresh repeats the same query.
- A no-match state names the searched title and gives a short recovery hint.
- Empty installs lead directly to the source directory; errors identify the
  failed source and offer retry or its settings when supported.

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

### Menu — the rest of Best

- A numbered masthead and a centered 760 dp reading column keep the tools easy
  to scan on phones and wide screens.
- Source tools and device tools are grouped into quiet cards with clear
  subtitles and full-row tap targets.
- Discovery links stay in one expandable group; About and the local-data note
  remain visible at the end.

### Settings — your copy of Best

- Masthead `09`: title + "Make Best yours".
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
| `ReadingCard` | `apps/best_app/lib/src/reading_card.dart` | Resume hero and compact continue row. |
| `WorkCard` | `packages/best_ui/lib/src/work_card.dart` | Shared poster/row card with progress. |
| `MediaCard` | `media_card.dart` | Metadata card with badge, rank numeral and optional progress. |
| `SectionHeader`, `PageMasthead`, `EmptyState` | `sections.dart` | Section with an accent tick, title and a "text + chevron" action (no closing hairline); page masthead `02–05`; centred empty state with glow, eyebrow and action. |
| `BestCover` | `cover.dart` | Deterministic gradient fallback when art is missing. |
| `BestTapScale`, `BestReveal` | `press_scale.dart` | Press feedback (scroll-aware, driven by `InkWell.onHighlightChanged`) and a one-shot, timer-free entrance. |
| `BestPulse`, `PosterSkeleton`, `PosterRailSkeleton`, `SliverPosterGridSkeleton`, `HeroSkeleton`, `RowSkeleton`, `RowListSkeleton` | `skeleton.dart` | Loading placeholders. One shared opacity pulse per group. |
| `bestTheme` | `theme.dart` | One builder for both brightnesses. |

`best_ui` never imports the app's localization. Every visible string is passed
in, which keeps the package reusable and testable.

---

## 7. States and feedback

- **Loading** — a skeleton with the same silhouette as the loaded content
  (poster rail, poster grid, row list, series page) for the first paint of a
  provider, so the layout does not jump when data arrives. A spinner is kept
  only inside buttons and for download progress. Pull-to-refresh keeps the old
  content visible.
- **Error** — `EmptyState` with a plain-language title, the technical detail in
  small text, and a Retry button. No red-on-black framework banner.
- **Empty** — icon in a restrained blue plate, title, one sentence, one clear
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
- Keep body text at strong contrast on both surfaces. Never use the saturated
  action colour for long copy or small metadata.
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
- Main tab content is capped at 1120 dp and centered on wide displays. Grid
  extents are computed from the sliver viewport, so split-screen and tablets
  get useful columns without stretched covers.
- Motion never exceeds 340 ms and never blocks input.
- `BestCover` caps image decoding to the width it is painted at (and never
  above 1080 px), so a large source never costs full-resolution memory inside
  a small tile. While loading it shows a still sunken surface and fades the
  image in; it does not pulse.
- Skeleton groups run one opacity animation each, never a shader sweep.

---

## 10. What we rejected

- **A sixth "Profile" tab.** HikariManga puts profile in the nav; Best's profile
  is the top of Settings. Five is the maximum before labels collide in Arabic.
- **A storefront-first home.** Home is for personal progress and discovery, not
  a rotating promotion wall.
- **Coin timers and daily rewards.** They convert, but they make a reading app
  feel like a game.
- **Dynamic colour.** A wallpaper-derived seed would erase the identity. The
  palette is fixed until a real-device review says otherwise.
- **Drift/ORM.** SQLite through `sqflite_common` is enough for the current
  schema and keeps startup predictable.
- **Auto-rotating banners.** The home rails are manually browsed, so the user
  stays in control and artwork never changes under a tap.

---

## 11. Implementation map

```
packages/best_ui/lib/src/
  tokens.dart      palette, space, radius, motion
  theme.dart       Material 3 scheme + component themes
  brand.dart       mark, wordmark, backdrop, stat strip
  cards.dart       discovery spotlight and continue card
  work_card.dart   poster and row cards
  media_card.dart  metadata card
  sections.dart    section header, empty state
apps/best_app/lib/src/
  navigation.dart  routes
  router.dart      shell branches (Home first)
  screens/         home, library, browse, series, reader, watch,
                   downloads, settings, shell
  progress_label.dart  shared page/clock label
  l10n/            EN + AR ARB files
```

Release checks: `flutter analyze` clean, package tests green, release APK built
in CI, and Android smoke reaching the reader and player. A real-device review
checks Arabic, light/dark themes, small phones, and tablet layout.
