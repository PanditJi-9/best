# Roadmap

Ordered by what removes the most risk for a reader, not by what is easiest to
demo. Each phase ends with a build that can be installed and used.

## 0. Foundation — shipped in 0.1.0

- Flutter app, four-tab shell, series and reader routes.
- Arabic + English, RTL, language and theme settings.
- SQLite shelf, merge-safe progress, continue-reading rail.
- Bundled guide with generated pages.
- MangaDex adapter (search, details, feed, pages).
- Rust core with tests and a C ABI, not yet on the FFI path.
- CI: analyze, tests, Rust, release APK artifact.

## 1. Library depth

- Import/export a JSON backup; restore on a new phone without an account.
- Custom lists, tags, and a "reading" / "planned" / "paused" state.
- Reading statistics (pages, minutes, streak) from local events.
- Bulk refresh of followed works with a per-source rate limit.
- Better Arabic metadata normalization (author names, status, genres).

## 2. Offline engine

- Download queue for chapter pages and episode files, pause/resume, Wi-Fi only.
- Storage accounting, per-work size, automatic eviction of finished downloads.
- Background isolate for downloads and image decoding.
- Integrity check per file; a corrupt page is re-fetched, not shown as blank.
- "Available offline" is a real filter on the shelf.

## 3. Playback

- Video engine evaluation: `media_kit` (libmpv) for codec coverage and subtitles
  versus `video_player` for platform integration.
- Resume by seconds, not pages; progress merges with the same rules.
- Subtitles, playback speed, PiP, and a TV/desktop layout.
- Anime and drama become first-class, not a card with a placeholder.

## 4. Sources and extensions

The honest constraint: Mihon/Tachiyomi extensions are Android/Kotlin code and
cannot run inside a pure Flutter isolate. Three options, in order of preference:

1. **Curated native adapters** behind `SourceAdapter` — highest quality, no
   execution of third-party code, slowest to add sources.
2. **QuickJS extension host** with a documented JavaScript source API — one
   sandbox, works on Android and iOS, needs a registry and a review process.
3. **Kotlin Android bridge** for drop-in Mihon extensions — only if users make
   it a hard requirement; it reintroduces the platform layer this plan removed.

Ship (1) now, prototype (2) next, treat (3) as a product decision with a real
cost, not a promise.

## 5. Sync

- Optional account or a user-owned backend (WebDAV, S3-compatible).
- End-to-end encrypted progress and library backup; the server sees ciphertext.
- Conflict resolution is `UnitProgress.merge`, already tested.
- No lock-in: export always works without the service.

## 6. Monetization

- Free: unlimited library, all sources, reader, limited downloads, both
  languages, no ads.
- **Best Pro** (yearly + one-time supporter): cloud sync, unlimited downloads,
  advanced statistics, extra themes, early builds. Regional pricing.
- Tipping for a single chapter/volume is deliberately avoided: it implies a
  commercial relationship with content the app does not host.
- No ads inside the reader. No sale of reading data.
- Store compliance: the app is a client; it hosts no licensed content. Sources
  are adapters, MangaDex is used through its public API, and a takedown path is
  documented before the first store submission.

## 7. Growth

- Arabic-first discovery: curated lists for manhwa/manhua that actually update.
- Import from MAL / AniList / Kitsu to make the first shelf non-empty in minutes.
- Shareable reading cards (progress, quote, cover) with the app mark.
- A public source-adapter guide so contributors add a source without touching
  the UI.
- ASO around "مانجا", "مانهوا", "أنمي" and "متابعة القراءة"; the store listing
  ships in Arabic and English.

## 8. Release engineering

- Signed AAB with a keystore in CI secrets; Play internal track first.
- Crash reporting with opt-in and PII scrubbing.
- Startup budget: cold start under 1.5 s on a mid-range phone.
- Performance budget: no frame over 32 ms while scrolling the shelf.
- F-Droid build after the dependency audit (no proprietary blobs).
- iOS after the Android release is stable; the domain and data layers are
  already platform-neutral.
