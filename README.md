# Best

One shelf for manga, manhwa, manhua, webtoons, anime and Asian drama.

Best is a Flutter application with a small Rust core. It is not a website and it
does not wrap one: the reader, the shelf and the progress engine are native
Flutter, and every source is an adapter behind one small interface.

**Status: 0.2.1 — the offline slice.** The shelf, the reader, the bilingual UI,
local progress, the bundled guide, one real catalogue (MangaDex), source packs
and the download queue are implemented and covered by tests. The video player,
the extension host and sync are scheduled, not pretended.

## What works today

- **A real shelf.** Add, remove, favorite, search, filter and sort. Counts and
  progress come from the local database, not from a widget's memory.
- **A real reader.** Page-by-page reading, zoom, page restore, completion
  tracking, and progress that survives a restart.
- **Arabic and English from day one.** Full RTL, localized strings, and a
  language switch that does not restart the app.
- **A first-run guide.** Seven generated works with chapters and pages, so a
  fresh install can be used before any source is configured.
- **MangaDex.** Search, details, chapter feed and page images through the public
  API. No scraping and no bundled credentials.
- **Source packs.** Install a third-party catalogue from a declarative JSON
  manifest (Settings → Source packs). Packs execute nothing: five routes, three
  field maps, validated before they are stored. See
  [docs/SOURCE-PACKS.md](docs/SOURCE-PACKS.md).
- **Merge-safe progress.** A stale write can never move a reader backwards, and
  a catalogue refresh can never erase a favorite or a finished chapter.
- **Real downloads.** Queue one chapter or every chapter from a series, watch
  per-page progress and storage use, pause, resume, retry or delete, and read
  with no connection. The queue is persisted, so closing the app resumes from
  the last saved page. See [docs/OFFLINE.md](docs/OFFLINE.md).
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

Requirements: Flutter stable (Dart 3.9+), Rust stable, Android SDK for the APK.

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
flutter analyze
flutter test
flutter build apk --release
```

Tagged builds are signed with a release key stored in Actions secrets
(`tool/configure_signing.sh`); a local build without that secret stays
debug-signed. The Android manifest opts out of Impeller because its Vulkan path
crashes before the first frame on a subset of GPU drivers — see
[the device matrix](docs/ROADMAP.md#device-matrix).

## CI

`.github/workflows/ci.yml` runs four gates on every push: domain tests, data
tests, Rust tests and formatting, then Flutter analyze, widget tests and a
release APK. The APK is uploaded as the `best-release-apk` artifact, and a `v*`
tag publishes it to Releases.

`.github/workflows/android-smoke.yml` is the on-demand launch gate: it boots an
API 30 emulator, installs the release APK, starts it, dumps the visible text and
a screenshot, and fails if the process is gone. A green build is not proof that
the app opens; this job is.

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

See [docs/ROADMAP.md](docs/ROADMAP.md),
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md),
[docs/OFFLINE.md](docs/OFFLINE.md),
[docs/SOURCE-PACKS.md](docs/SOURCE-PACKS.md) and the
[HikariManga reference study](docs/HIKARIMANGA-STUDY.md).
