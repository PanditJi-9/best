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

## Identity and Home — shipped in 0.4.0

- [x] "Ink & Jade" design tokens, one theme builder, and a shared `best_ui`
  layer: mark, wordmark, backdrop, stat strip, spotlight, continue card.
- [x] Five destinations with Home first: Home, Library, Browse, Downloads,
  Settings. Home opens on a spotlight, the resume rail, ranked trending and
  three sample films.
- [x] Series, Browse, Downloads, Settings and the reader chrome rebuilt on the
  shared components.
- [x] Arabic-first ICU plurals for works, sources, results, units and pages.
- [x] A 170-app competitor study and a written design contract, so the next
  screen has a rule to follow instead of a taste debate.
- [ ] Per-screen motion polish (shared-element cover transitions) once the
  routes are stable.
- [ ] Tablet layout: the grids scale, but the series page still assumes one
  column.

## 1. Library depth

- Import/export a JSON backup; restore on a new phone without an account.
- Custom lists, tags, and a "reading" / "planned" / "paused" state.
- Reading statistics (pages, minutes, streak) from local events.
- Bulk refresh of followed works with a per-source rate limit.
- Better Arabic metadata normalization (author names, status, genres).

## 2. Offline engine — first slice in 0.2.0

- [x] Download queue for chapter pages, pause/resume/retry/delete, persisted
  across launches.
- [x] Bulk "download all chapters" with a confirmation, and "delete finished".
- [x] The reader prefers finished downloads and falls back to partial pages when
  the source is unreachable.
- [x] Storage accounting: bytes per download and total used on the Downloads
  screen, backfilled for downloads written before 0.2.1.
- [ ] Wi-Fi-only scheduling.
- [ ] Per-work size and automatic eviction of finished downloads.
- [ ] Background isolate for downloads and image decoding; the current queue
  runs while the app process is alive.
- [ ] Video downloads; episode rows hide the download control until the player
  can store a stream.
- [ ] Integrity check per file; today a page is written atomically and a
  missing page is fetched again on resume, but a corrupt image is not detected.
- [ ] "Available offline" is a real filter on the shelf.

## 3. Playback — first slice in 0.3.0

- [x] `video_player` (ExoPlayer/Media3 on Android) for HLS and MP4. `media_kit`
  remains the fallback if codec coverage or subtitle rendering becomes a hard
  requirement; see [PLAYBACK.md](PLAYBACK.md).
- [x] Resume by seconds, not pages; progress merges with the same rules.
- [x] ±10 s seeking, 0.75×–2× speed, fullscreen, keep-screen-on, buffering and
  retry states.
- [x] Anime and drama are first-class: the series CTA, continue rail and routes
  choose the player by media kind.
- [ ] Subtitle tracks (WebVTT/SRT) and a CC toggle.
- [ ] Quality and audio-track picker; a source may return several
  `VideoResource`s.
- [ ] PiP, background audio and a TV/desktop layout.
- [ ] Offline video downloads with the same queue guarantees as chapters.

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

### Device matrix

The launch gate is `android-smoke.yml` (API 30, x86_64, clean install). Real
devices still differ by GPU and vendor ROM, so every release records the devices
it was opened on:

| Device | Android | Renderer | Result |
|---|---|---|---|
| CI emulator | 11 (API 30) | Skia (Impeller opted out) | opens, shelf renders |
| Owner phone | to be recorded | to be recorded | v0.1.2 pending |
| CI emulator (playback) | 11 (API 30) | Skia | v0.3.0 pending |

Impeller is opted out in `tool/android/AndroidManifest.xml` because its Vulkan
path closed the app before the first frame on a real device while the same APK
opened on the emulator. Skia is the compatibility path and Flutter marks the
opt-out as deprecated: re-test on a device with `EnableImpeller=true`, and remove
the opt-out once the matrix is green without it.
