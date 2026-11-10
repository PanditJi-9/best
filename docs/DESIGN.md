# Best — identity and structure

Version 2.0 · "Ink & Ember"

Best is one shelf for manga, manhwa, manhua, webtoons, anime and Asian drama.
The design has to do something hard: feel premium next to Mihon and HikariManga,
stay readable in Arabic and English, and never let chrome outshout the artwork.

This document is the contract. If a screen disagrees with it, the screen is
wrong.

---

## 1. Design thesis

**Ink and ember.**

- **Ink** is the ground: warm near-black in dark mode and warm paper in light mode. The room should feel like a reading lamp, not a server rack.
- **Ember** is the primary action and the selected state: a sealed vermilion, warm and unmistakable. It should identify the next useful tap, not decorate every surface.
- **Amber** is the editorial accent: section numerals, quiet links and the second half of the signature gradient.
- **Gold** marks ratings and ranks. **Jade** is reserved for completed and offline states.
- Artwork carries most of the colour; controls stay quiet and readable in Arabic and English.

Best is a personal media shelf, not a storefront. Every screen should make the next action obvious, keep local progress visible, and use motion only to confirm a change. The identity is printed rather than neon: a warm page, a seal, a hairline — the artwork supplies the spectacle.

---

## 2. Tokens

All tokens live in `packages/best_ui/lib/src/tokens.dart`. A screen may not
invent a colour, radius or duration.

### Colour

All values below are sourced from `packages/best_ui/lib/src/tokens.dart`. Use
these tokens instead of introducing screen-specific colours.

| Token | Value | Use |
|-------|-------|-----|
| `inkDeep` | `#060508` | Dark hero and reader surfaces |
| `ink` | `#0A090D` | Dark app background |
| `inkRaised` / `inkElevated` | `#121016` / `#19161E` | Cards and inputs |
| `inkLift` / `inkLine` | `#241F28` / `#2E2733` | Selected rows, hairlines |
| `paper` / `paperRaised` | `#F7F2E9` / `#FFFCF7` | Warm light background and cards |
| `ember` | `#F25B4C` | Primary action and selected state (dark theme) |
| `emberDeep` | `#D63E31` | Primary action in the light theme |
| `amber` / `brass` | `#E8A45C` / `#CF8A4B` | Signature gradient and editorial accents |
| `gold` | `#F0C266` | Ratings and rank numerals |
| `jade` | `#45D6A4` | Progress and offline state |
| `danger` | `#FF7A70` | Errors and destructive actions |

The signature gradient `aurora = [ember, amber]` belongs on the mark and a
small number of meaningful progress moments. Never use it as a page background.
The legacy token names `blue`, `cyan` and `cinnabar` remain as aliases so older
screens keep their meaning while rendering the ember system.

---

### Type

The working UI uses the bundled IBM Plex Sans Arabic family for controls,
metadata and body text. **Amiri carries every display role**: the wordmark,
page titles and mastheads, so a screen opens like a printed page instead of a
settings panel. CJK native titles fall back to the system face.

- Page titles are strong and compact (34 px Amiri); section titles are 18 px.
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
- Radius: `4 / 7 / 10 / 14 / 20 / 26 / pill` (`xs … sheet`). The page is
  sharper than the old build: an editorial sheet, not a bubbly storefront. The
  pill is only for progress, status dots and the selected dock icon.
- Motion: `130 ms` fast, `210 ms` normal, `320 ms` slow, `easeOutCubic`. No
  spring, no bounce. Every decorative animation asks `BestMotionPolicy.reduced`
  first and stays still when the system has animations turned off.
- Gutter: `BestLayout.gutter` (20 dp). Rails bleed to the screen edge and carry
  the gutter on their own first and last item.
- Splash: `InkRipple` — the InkSparkle shader is missing in headless tests and
  some older GPUs, and a missing shader is a visible bug.

### Elevation

No drop shadows on cards. Separation comes from a one-pixel border
(`outlineVariant`) plus a slightly raised surface. Shadows are reserved for the
floating cover in the series hero, the spotlight artwork and the floating
navigation dock, which must read as lifted above the page.

---

## 3. Brand

- **Seal** — a vermilion-to-amber stamp holding an ivory four-point spark and
  an inset hairline, drawn with a `CustomPainter` (`BestMark`). It reads as a
  printed seal at 20 px and at 96 px.
- **Wordmark** — mark + localized product name in Amiri + optional tagline
  (`BestWordmark`), with zero tracking in Arabic.
- **Backdrop** — a blurred, dimmed cover behind a title (`BestBackdrop`). Used
  on series pages and error/empty states where a cover exists.
- **Stat strip** — three numbers in one bordered card (`StatStrip`). Values are
  tabular and scale down instead of overflowing.

The mark is the only place the full gradient is allowed at full strength.

---

## 4. Information architecture

Six content destinations share the floating dock. Settings is a pushed route
from the Home masthead, so the dock never spends a column on configuration.

| Tab | Route | Question it answers |
|-----|-------|---------------------|
| Home | `/` | What is new in the source I chose? |
| Library | `/library` | What do I own? |
| Updates | `/updates` | Which shelved work has new chapters? |
| Downloads | `/downloads` | What is offline right now? |
| Encyclopedia | `/database` | What exists beyond my installed sources? |
| History | `/history` | What did I read or watch recently? |

Routes: `/series?source=&url=`, `/read?source=&url=&unit=`,
`/watch?source=&url=&unit=`. Source ids and URLs are query parameters, never
path segments — a source URL can contain slashes and dots.

`openUnit` chooses `/read` or `/watch` from `MediaKind.isReading`; screens never
branch on a source name.

### Why these six

Home is source-first: a pinned source strip scopes one catalogue at a time, so
manga and anime never mix in one grid. The source itself declares its kind, so
there is no global Manga/Anime switch taking space from a reader who only uses
one half. Library is the shelf; Downloads owns the offline queue and its
history, so a finished chapter never turns the shelf into a transfer manager.
Updates is a short, explicit "new chapters" inbox. The Encyclopedia is the
optional external catalogue, and History is the activity trail. Settings is a
pushed screen, not a tab: identity before configuration.

All six sit on one floating bar. Six equal columns is the maximum that keeps
Arabic labels legible at 320 dp; a seventh would force a "More" sheet and make
the two least-used rooms undiscoverable.

### The index bar

- A floating, 66 px raised dock inset 12 px from the screen edges and 8 px from
  the safe area, with a 20 px radius, a hairline outline and one soft shadow.
  It is the only lifted surface in the app chrome.
- Six equal columns. The selected column puts its filled icon on a 46×28 ember
  pill (16% tint) that grows from the 36 px resting width, with an ember label
  and a 12 px ember tick underneath; the others use outlined icons and muted
  labels.
- The page behind the dock is warm ink at the foot with a breath of ember at
  the crown. The glow is atmosphere only, never a gradient behind text.
- Switching tabs gives a light haptic tick and eases the new page in with a
  210 ms fade (never a slide: tabs are peers, not steps).
- Labels stay visible and scale down when needed so English and Arabic fit on
  small phones. Keep the selected tab accessible through `Semantics`.

## 5. Screen blueprints

### Home — the front door

1. **Title page masthead** — the 44 px seal, the product name in Amiri, the
   role line in amber, and two circular actions (universal search, settings).
   This is the only global chrome on the page.
2. **Pinned source strip** — compact rounded chips with the source's own image
   open that catalogue directly, and the remembered source is restored on
   launch. A source declares whether it publishes manga or anime, so a reader
   who installs only manga sources never sees an anime control — and the same
   is true in reverse. Add source opens the directory without forcing a half.
3. **Latest / Popular** — two text tabs with a short animated ember rule, the
   editorial replacement for the old segmented pill. Infinite scroll pages
   past the first batch; pull to refresh.
4. **Long-press** — adds the work to the library, or removes it, without
   opening the details page.

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

1. **Hero** — a compact 216 px artwork block with a 124×186 cover. The primary
   reading action should not be pushed below a large decorative gap. The cover
   floats; the page beneath it stays warm ink.
2. **Identity** — centered title, native title, kind · year · status · offline
   count, author, genre pills.
3. **Actions** — a primary button naming the exact next chapter and saved
   position. Favorite and library remain on the app bar; refresh/source/migration
   are secondary menu actions. Removing from the shelf asks first.
4. **Stat strip** — units / offline / percent complete.
5. **Synopsis** — four lines with More/Less.
6. **Unit list** — chapter/episode search, view-only filters and sort, with
   naturally sized pinned controls and a count of shown/total rows. Bulk download
   applies to the shown list after confirmation.
   Each row is a card: progress ring or check, title, date · pages, download
   control, numbered chip.
7. **Adaptive layout** — below 840 dp use one column; wider layouts cap at 1120
   dp with a 340 dp overview pane and a separate chapter pane. A cached-data
   notice explains unavailable sources and leads to installed sources or downloads.

### Reader — pages

- Edge-to-edge black by default; charcoal, sepia and white are reader choices,
  not changes to the app's colour identity.
- Top chrome is a short ink gradient, not a panel: an editorial unit title over
  the work name, with previous/next chapter steps framed around the chapter
  picker. The single toolkit action stays separate. Offline status sits in the
  subtitle rather than competing with phone-width controls.
- A floating quick dock above the progress rule carries the five one-tap
  actions a reader reaches for: bookmark, page grid, chapters, paged/vertical
  mode and colour/display. Settings still holds the complete toolkit; wide
  screens also show OCR there, and the same OCR switch stays in settings on
  every viewport.
- Tapping the unit title opens the complete chapter picker at the current
  chapter. Numeric search accepts Arabic/Persian digits; finding current clears
  the search without reloading the chapter.
- Fit-screen scans page normally; fit-width scrolls tall scans; original size
  has explicit pinch/pan. A vertical webtoon strip keeps natural page heights.
- Two-page layouts require fit-screen and at least 600 dp of width. Adaptive
  mode additionally requires a landscape viewport at least 720 dp wide.
  Artwork order follows the reader direction independently of the UI locale.
- Page one may stand alone. A leftover final scan never crosses chapters.
- Settings starts with **App defaults / This work** scope and explains what is
  shared. Wake, preload and OCR are grouped as device-wide choices.
- Bottom chrome has a real source-page counter (or pair range), a live
  percentage, the scrubber and chapter navigation. Continuous mode adds a
  restrained auto-scroll control to the same 48 dp rule; a drag, pinch, page
  jump, mode change or chapter change stops it. A deliberate edge drag may
  change chapter; landing at an edge during the same drag never does.
- Progress saves 320 ms after a page change and again on dispose. Pairing never
  renumbers pages or bookmarks; completion accounts for the last visible scan.
- Partial downloads never count a prefix as the whole chapter. They retain the
  expected total and later saved position, warn clearly, and block automatic
  next-chapter flow until the full chapter is available.
- Unknown totals stay unknown in the footer, vertical HUD and page grid.
  Bookmarks outside the available prefix stay saved; their empty state explains
  page availability instead of falsely claiming no bookmarks exist.

### Watch — episodes

- `video_player` (ExoPlayer/Media3) with wakelock.
- Auto-hiding controls, center play/pause, 10-second skip, speed sheet,
  fullscreen, replay at the end.
- The title opens an episode picker, not a chapter-labelled list. Playback
  pauses while choosing; dismissal resumes only an episode that was already
  playing. A chosen episode replaces the route and releases the old player.
- Progress in seconds; resume at ≥3 s; finished at 95% or the last 5 s.
- Errors show the localized playback message, not a raw exception.

### Downloads — what is offline

- Title and on-device image bytes, with search and All / Offline / Failed /
  In progress filters kept above the scrolling list.
- Section "In progress" (queued, running, paused, failed) only. Finished
  chapters leave it for the download history, where each work is a card with
  its cover and title, and its chapters stay folded until the card is opened.
  Each tile shows the work, chapter, status and useful pause/resume/retry or
  open action. Its secondary menu offers local file checks and deletion.
- Check saved pages reports missing, empty or byte-changed files; it does not
  claim image decoding or source authenticity. Repair is a separate explicit
  action and preserves intact files and reader state.
- Finished-download cleanup applies only to the shown selection and confirms
  the affected count. Search and filters do not alter stored rows.
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
| `WorkCard` | `packages/best_ui/lib/src/work_card.dart` | Shared poster/row card with progress. The cover badge hugs its label; it never stretches across the cover. |
| `BestProgressRule` | `packages/best_ui/lib/src/progress_rule.dart` | Thin progress rule: a quiet track and the aurora fill. The one progress colour on covers, rows and continue cards; a finished download is jade. |
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
- **Success** — floating snackbar, never a full-screen toast. The snackbar is
  warm ink in both themes, with an ivory label.

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
- The reader uses image loading/retry states and a bounded warm-up of the next
  two scans and previous scan. Turning preload off stops new warm-ups. Extension
  image requests stay with their signing client instead of duplicating requests.
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
