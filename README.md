# Best

One shelf for manga, manhwa, manhua, webtoons, anime and Asian drama.

Best is a Flutter application with a small Rust core. It is not a website and it
does not wrap one: the reader, the shelf and the progress engine are native
Flutter, and every source is an adapter behind one small interface.

**Status: 1.5.1 build 26 in development — clean downloads, a restored encyclopedia.**
Build 26 passed Flutter analysis, 172 serial widget and unit tests, 62 Python
tool tests, the extension runtime JVM gate, and signed four-APK generation in
[CI](https://github.com/PanditJi-9/best/actions/runs/42332008960). The universal,
arm64-v8a, armeabi-v7a and x86_64 APKs share one application id, version and
signing certificate. This build rearranges the shell around five content tabs —
Home, Library, Downloads, Encyclopedia and History — with Settings pushed from
the home masthead. Downloads are no longer folded into the Library: they have a
quiet grouped screen, one download-history control and a chronological history
screen, while the Library keeps a single filter control instead of a chip row.
The encyclopedia returns as a visible destination, named Encyclopedia in
English. See [the build notes](docs/releases/1.5.1-build26.md).
No 1.5.1 release has been published.

The shelf, the reader, the video player with captions, the bilingual UI, local
progress, statistics, JSON backup/restore, one real catalogue (MangaDex),
declarative source packs (format 2, including streaming packs) and the native
Mihon/Komikku extension host (with Aniyomi anime bundles) are implemented and
covered by tests. Home and Browse open on the live catalogue, one search box
covers every installed source, and a hand-picked shelf ships with the app and
refreshes itself without a store release. 1.2.0 added **categories with names,
hidden categories and bulk selection on the shelf**, source/language labels on
every card, and **moving a work to another source with its reading progress**.
1.3.0 rebuilds the reader around how manga is actually read: **right-to-left
paged chapters**, fit-screen/fit-width/original scaling, tap zones with a
centring control toggle, auto-hiding immersive chrome, keep-screen-on,
black/charcoal/sepia/white backgrounds, a persisted colour filter with dimming,
failed-page retry, and **previous/next chapter navigation** with a next-chapter
prompt at the end. A second pass adds a **visual page grid**, **persistent page
bookmarks**, **chapter search and sort**, **page preloading**, **webtoon
spacing**, **chapter download from the reader**, edge-of-chapter flow and
**keyboard shortcuts**. Every new reader string exists in Arabic and English.
Suwayomi remains as an optional alternative for readers who already run one.

## What works today

- **A source-first front door.** Home shows one installed source at a time,
  never a mixed manga/anime grid. Each source already knows what it publishes,
  so a manga-only reader never sees an anime control, and an anime-only reader
  never sees a manga one. Pinned source chips use the site's own icon, with
  Latest/Popular feeds, infinite scroll, and long-press to shelve a poster.
  Four tabs: Home, Library, History, Settings.
- **Offline belongs to the shelf.** Finished downloads appear in a Ready
  offline rail above the Library, while active and failed transfers collapse
  into one banner that opens the download manager. There is no separate
  Downloads tab.
- **One search, every source.** Browse opens on **All sources** and searches
  them in parallel, so a slow pack cannot hold back the catalogue.
- **Best picks, without a store update.** A curated shelf (`assets/curated.json`)
  ships inside the app so the first launch has an editorial front page, and the
  app refreshes it from the project repository every 12 hours. Each pick is
  resolved through its own adapter — the list names a work, it never copies
  one.
- **The Mihon/Komikku catalogue, hosted by Best.** Extensions are Android APKs
  compiled against Mihon's `source-api`; Best ships that runtime as real Kotlin
  (`tool/android/kotlin/eu/kanade/tachiyomi/`) and mounts each installed APK with
  a `DexClassLoader` whose parent is the app's own loader. Sources → **Extension
  directory** lists community packages, and installing one is an explicit tap;
  nothing is installed on first launch. Browse then lists every source the
  package exposes, and the reader opens its chapters. Best still bundles no
  scraper: the extension is the program.
  See [docs/SOURCE-PACKS.md](docs/SOURCE-PACKS.md).
- **Suwayomi, if you already run one.** Settings → **Suwayomi server** takes one
  address (`http://192.168.1.20:4567`) and Browse gains that server's sources
  over REST. Manga only, off by default.
- **One visual system.** "Ink & Aurora": blue-black ink, blue for action, gold
  for ranks and jade kept for progress and offline state. Amiri and IBM Plex
  Sans Arabic carry the editorial voice. The mark,
  masthead, numbered sections, cards and reader chrome are shared components,
  not per-screen styling. See [docs/DESIGN.md](docs/DESIGN.md).
- **A real shelf.** Add, remove, favorite, search, filter and sort. Counts and
  progress come from the local database, not from a widget's memory. Started
  first-page sessions remain resumable; Not started and In progress do not
  contradict each other.
- **Categories, hidden categories, bulk edits.** A category is a named tag, so
  old backups restore with all of them. Hide one to clear it from the shelf,
  reveal hidden ones from the same row, long-press a cover to select several
  works and favorite, categorize or remove them together. Cards name the source
  and language they came from.
- **Move a work to another source.** Search other sources from the work's page;
  chapters are matched by number then by normalised title, matched chapters
  carry the reading position, unmatched ones are reported, and downloads stay
  with the old source. Nothing is written before confirmation.
- **A real reader.** Right-to-left manga pages or a vertical webtoon scroll,
  fit-screen/fit-width/original scaling, RTL-aware tap zones and a centre
  control toggle, auto-hiding immersive chrome, keep-screen-on,
  black/charcoal/sepia/white backgrounds, a persisted colour filter with
  dimming, pinch zoom and panning in original size, retry for failed pages,
  page restore, completion tracking, and previous/next chapter controls. The
  page grid jumps anywhere with thumbnails, bookmarks persist per chapter,
  chapter search/sort handles long serials, upcoming pages preload, webtoon
  spacing is adjustable, and the current chapter can be downloaded without
  leaving the reader. A work can remember its own presentation without changing
  another title; wide viewports support paired scans with an optional solo
  cover. Portrait phones and pan/fit-width modes keep one page. See
  [docs/releases/1.4.0.md](docs/releases/1.4.0.md).
- **A real video player.** Episodes open a full-screen player with resume in
  seconds, ±10 s seeking, playback speed, fullscreen and an episode picker that
  pauses while choosing and resumes only if playback was already running. Anime and drama are
  first-class, not a card with a placeholder. See
  [docs/PLAYBACK.md](docs/PLAYBACK.md).
- **Arabic and English from day one.** Full RTL, localized strings, and a
  language switch that does not restart the app.
- **A first-run guide.** Seven generated works with chapters, pages and three
  public-domain sample films, so a fresh install can be used — and watched —
  before any source is configured.
- **MangaDex.** Search, details, a language-aware chapter feed and page images
  through the public API. Arabic chapters come first when the interface is
  Arabic; English is the fallback track. No scraping and no bundled credentials.
- **Source packs.** Install a third-party catalogue from a declarative JSON
  manifest (Settings → Source packs). Packs execute nothing: five routes, three
  field maps, validated before they are stored. See
  [docs/SOURCE-PACKS.md](docs/SOURCE-PACKS.md).
- **Merge-safe progress.** A stale write can never move a reader backwards, and
  a catalogue refresh can never erase a favorite or a finished chapter.
- **Real downloads.** Queue one chapter or every chapter from a series, watch
  per-page progress and storage use, pause, resume, retry or delete, and read
  with no connection. The queue is persisted, so closing the app resumes from
  the last saved page. A partial prefix is not marked as a complete chapter,
  and stored pages can open after removing their source. See
  [docs/OFFLINE.md](docs/OFFLINE.md).
- **A backup you can actually keep.** Export JSON through the system sharing
  boundary or copy it; local copies are clearly labelled app-local. Reader
  defaults, per-work profiles, bookmarks and empty category names travel with
  the library. Existing styles are preserved on merge, device credentials are
  excluded, and plain exports are labelled unencrypted.
- **Offline-first storage.** SQLite through `sqflite`; an in-memory repository
  keeps the app usable if the database cannot be opened.

## Layout

```
apps/best_app        Flutter application (UI, routing, state, l10n)
packages/best_domain Pure Dart entities and rules, zero Flutter imports
packages/best_data   SQLite, repositories and source adapters
packages/best_ui     Design tokens and shared widgets
rust/best_core       Search folding, number parsing, reading-time estimate
tool/                Android platform bootstrap and owned manifest
```

The dependency direction is one-way: `best_app` → `best_data` → `best_domain`.
`best_ui` depends on Flutter and `best_domain` only. `best_data` never imports
Flutter, which is why its storage tests run in plain Dart on CI.

## Build

Requirements: Flutter stable (Dart 3.10+), Rust stable, Android SDK for the APK.

```sh
# Dart packages
cd packages/best_domain && dart pub get && dart test
cd ../best_data && dart pub get && dart test

# Rust core
cd ../../rust/best_core && cargo test

# App
cd ../../apps/best_app
sh ../../tool/bootstrap_android.sh   # creates android/ once
flutter pub get
flutter gen-l10n
flutter analyze --no-pub
flutter test --no-pub
python3 ../../tool/android_apks.py build  # ARM64, ARM32, x86_64 + Universal, once
```

The `CI` workflow runs these steps on pushes to `main` and on pull requests,
and uploads four standalone APK alternatives: ARM64, ARM32, x86_64 and
Universal. They come from one assembly, share the same update identity, and
each manifest/ABI/signature is checked before upload. Gradle caching, bounded
parallel work and the memory-safe 3G/2G profile avoid unnecessary compilation.
See [Android builds](docs/ANDROID-BUILDS.md) for files and build-time boundaries.

Tagged builds are signed with a release key stored in Actions secrets
(`tool/configure_signing.sh`); a local build without that secret stays
debug-signed. The Android manifest opts out of Impeller because its Vulkan path
crashes before the first frame on a subset of GPU drivers — see
[the device matrix](docs/ROADMAP.md#device-matrix).

## CI

`.github/workflows/ci.yml` runs five gates on every push: a ranged probe of
every demo stream in the bundled guide, domain tests, data tests, Rust tests and
formatting, then Flutter analyze, widget tests and four release APKs. Universal
keeps the `best-release-apk` artifact name; the three smaller variants append
their ABI names. A `v*` tag publishes all four to Releases. The stream probe
exists because a hard-coded demo URL that starts
answering 403 turns the first-run play button into an error screen; it fails in
seconds instead of after an emulator boot.

`.github/workflows/android-smoke.yml` is the on-demand launch gate: it boots an
API 30 emulator, installs the release APK, starts it, dumps the visible text and
a screenshot, and fails if the process is gone. It reuses successful CI output
only for the exact same commit, avoiding another compile/JVM pass; otherwise it
builds and tests afresh. A green build is not proof that the app opens; this job
is.

## Design rules

1. The database is the source of truth. Screens re-read a query; they never
   patch a list by hand.
2. A write is explicit. Opening a work is not the same as adding it to the
   shelf, and nothing is downloaded without a tap.
3. A missing image is a designed fallback, never a broken icon.
4. A source is an adapter, not a dependency. Nothing above `best_data` knows
   MangaDex exists.
5. The UI ships in Arabic and English together; a new string is added to both
   ARB files in the same commit.

## Roadmap

Start with the [design blueprint](docs/DESIGN.md) and the
[170-app competitor study](docs/COMPETITORS.md). Then:
[roadmap](docs/ROADMAP.md), [architecture](docs/ARCHITECTURE.md),
[offline](docs/OFFLINE.md), [playback](docs/PLAYBACK.md),
[source packs](docs/SOURCE-PACKS.md) and the
[HikariManga reference study](docs/HIKARIMANGA-STUDY.md).
