# Architecture

## The shape

```
┌─────────────────────────────────────────────────────────────┐
│ apps/best_app                                               │
│   MaterialApp.router · go_router · Riverpod · ARB (ar/en)   │
├─────────────────────────────────────────────────────────────┤
│ packages/best_ui                                            │
│   tokens · theme · cover · card · empty state               │
├─────────────────────────────────────────────────────────────┤
│ packages/best_data                                          │
│   SQLite schema · repositories · MangaDex · guide           │
├─────────────────────────────────────────────────────────────┤
│ packages/best_domain                                        │
│   Media · MediaUnit · UnitProgress · LibraryPolicy · ports  │
├─────────────────────────────────────────────────────────────┤
│ rust/best_core (optional, isolated)                         │
│   search folding · unit number parsing · reading time · C ABI│
└─────────────────────────────────────────────────────────────┘
```

`best_domain` has no Flutter and no I/O. `best_data` has no Flutter either, so
every storage and adapter rule is testable with plain `dart test`.
`best_app` is the only package that knows about widgets, routing or locale.

## Identity

A work is `sourceId::url`; a unit is `mediaId::unitUrl`. Both are strings, not
64-bit hashes. Hashing saves a few bytes and buys two real problems: collisions
silently merge two works, and Dart web integers lose precision above 2^53.
The separator is rejected inside a source id, so the key is unambiguous and
readable in a database shell.

## Progress

`UnitProgress.merge` is the only place where two writes meet:

- the later `updatedAt` wins the position;
- `completed` is a union — finishing a chapter is a fact a stale backup must
  not erase;
- `total` is the largest ever reported, because sources only get more accurate;
- a position can never point past the last page.

The SQLite repository reads the stored row, merges, then writes. A refresh from
a source uses `ON CONFLICT ... DO UPDATE` with `MAX`/`COALESCE`, so it can add
metadata but cannot erase a favorite, an `addedAt`, or history.

## Storage

Schema v4: `media`, `unit`, `progress`, `downloads`, `activity`, plus indexes.
Foreign keys are on. Older databases are upgraded in place: v2 adds the
downloads table, v3 adds byte accounting, v4 adds `media.state`, `media.tags`
and the `activity` table. Every migration is additive, so a database written by
an older build keeps its rows. The `DatabaseFactory` is injected, so the same
schema runs on `sqflite` on a phone and `sqflite_common_ffi` in a test.

`activity` is one row per local day (`pages`, `minutes`, `units`). It is a total,
not a log: importing a backup takes the larger value per field, which makes a
restore idempotent. `ReadingStats` derives the streak and the seven-day bars
from those rows; nothing about reading leaves the device.

`MemoryLibraryRepository` implements the same contract with the same merge
rules. It is the widget-test repository and the fallback when the database
cannot be opened — a failed open must not become a white screen.

## Offline downloads

`DownloadManager` owns the queue and is the only writer of download rows. It
takes a `LibraryRepository`, a `SourceRegistry`, an `http.Client` and a root
`Directory`, so a plain Dart test can run it against a mock client and a temp
folder. It runs one chapter at a time, persists after every page, and treats a
`running` row found at launch as queued work to resume.

Finished pages are `FileResource` objects, a fourth `MediaResource` variant. The
reader does not know whether a page came from a CDN or from the phone; it only
sees the sealed type. The provider checks for a finished download first and
never calls the source, which is what makes offline reading real rather than a
cache with a network fallback. Details in [OFFLINE.md](OFFLINE.md).

## Playback

An episode is a `VideoResource` returned by the same `SourceAdapter.resources`
call that returns page images. `watchProvider` resolves the catalogue rows and
takes the first video; `WatchScreen` owns one `VideoPlayerController`
(`video_player`, ExoPlayer on Android) and one progress row.

`PlaybackProgress` in `best_domain` is the only place that decides where to
resume, when a video is finished and how to clamp a position. It stores seconds
in the existing `progress` table — no schema change, and the same merge rules
apply. A completed row is never moved backwards by a replay.

Captions are `SubtitleCue`s parsed by `Subtitles` from WebVTT or SRT. The parser
is pure and total: a malformed file yields an empty list, never an exception
mid-film. `VideoResource.subtitleUrl` is either `asset://` (bundled, works with
the network off) or an HTTP URL; the player reads it once per stream and shows
the line whose cue covers the current position.

The player is a pushed route outside the shell, so the bottom bar disappears
while watching. It is dark in both themes, keeps the screen awake while playing,
and restores the system UI and orientation when it closes. Details in
[PLAYBACK.md](PLAYBACK.md).

## Sources

`SourceAdapter` is deliberately small: `popular`, `search`, `details`, `units`,
`resources`. Adding a method is a breaking change for every adapter, so the
surface stays thin. MangaDex is the first real adapter and maps its JSON onto
domain types; nothing above `best_data` knows the API exists.

The bundled `DemoSource` generates seven works, chapters and pages, plus three
public-domain sample films for the watching works. It is labelled as a guide,
never presented as licensed content, and it exercises the same reader and
player paths as a real source.

### Source packs

A pack is declarative JSON — five route templates and three field maps — with no
code to execute, so installing one cannot read the library, the filesystem or a
host it did not name. Format 2 adds `routes.watch` and `map.video`: a pack can
be a streaming catalogue with caption tracks, not only pages. `SourcePack.parse`
validates the whole document (id shape, HTTPS base, required placeholders, size)
and refuses a format it does not understand instead of guessing. `encode()`
returns the canonical document, which is what a backup and a sync carry.

### Backup and sync

`LibraryBackup` (format 2) is a JSON document with the shelf, units, positions,
activity and the installed packs. It is written and read by `best_data`; the
domain's `LibrarySnapshot` and `restoreInto` decide what a restore means: every
write goes through the normal merge rules, so a restore can only add.

`SyncCipher` seals that document with AES-256-GCM and a PBKDF2-HMAC-SHA256 key
(150,000 iterations, salt and iteration count in the envelope). `WebDavSync`
puts the sealed blob on any WebDAV folder with Basic auth and refuses plain
`http://` outside loopback. The passphrase is never persisted; the server only
ever holds ciphertext.

## State and navigation

Riverpod 3 without code generation. The repository emits on `changes` after
every successful write; the shelf watches that stream and re-runs its query.
Screens never mutate a local list to fake persistence.

`go_router` with a `StatefulShellRoute.indexedStack` for the five tabs. Series
and reader are pushed routes outside the shell, so the bottom bar disappears
while reading. Source ids and urls travel as query parameters, not path
segments: a url with slashes must not become a 404.

## Localization

Flutter `gen-l10n` with `app_en.arb` and `app_ar.arb`. Arabic drives RTL through
the normal `Directionality` machinery. The locale is a setting, not a restart:
`MaterialApp.router` rebuilds with the new `locale` and the router keeps its
stack. Every new string lands in both files in the same commit.

## Rust boundary

`best_core` is pure: FNV-1a, Arabic-aware search folding, chapter number
parsing, reading-time estimate. It exposes a C ABI and compiles as
`cdylib`/`staticlib`/`rlib`, but the app does not require it yet. Dart has a
tested fallback for every routine, so the product works before FFI is wired and
a broken toolchain cannot block a release. The FFI call site will be one adapter
behind an interface, not a dependency spread through the UI.

## Why Flutter, not Kotlin

One UI codebase reaches Android now and iOS later without a second design
system. The platform-channel layer that a Kotlin-first plan required was
dropped: it added a second language, a second build, and a second place for
bugs, while the parts that actually need the platform (downloads, playback,
background work) have mature Flutter plugins. Kotlin remains an option for a
future Android-only extension host, behind a narrow interface, only if drop-in
Mihon compatibility becomes a hard requirement.

## Testing

- `best_domain`: pure rules, 29 tests, including playback resume/completion.
- `best_data`: real SQLite in memory, merge cases, MangaDex against a mocked
  HTTP client, download queue and guide streams, 36 tests.
- `best_core`: 7 Rust tests.
- `best_app`: 7 tests: the shelf in English and Arabic/RTL, downloads, the guide
  reader, a drama offering the player, a source pack, clock formatting and the
  watch route.
- CI also builds a release APK, so a green run means the app compiles for a
  phone, not just for the analyzer.

## Failure policy

- A source failure is a typed error with a retry, not an empty list.
- A missing cover is a deterministic gradient with the first glyph.
- A details request is enrichment; the listing already on screen is enough to
  open the work.
- A failed database open falls back to memory for the session and retries next
  launch. Nothing is written over a corrupt file.
