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

Schema v1: `media`, `unit`, `progress`, plus three indexes. Foreign keys are on.
The `DatabaseFactory` is injected, so the same schema runs on `sqflite` on a
phone and `sqflite_common_ffi` in a test.

`MemoryLibraryRepository` implements the same contract with the same merge
rules. It is the widget-test repository and the fallback when the database
cannot be opened — a failed open must not become a white screen.

## Sources

`SourceAdapter` is deliberately small: `popular`, `search`, `details`, `units`,
`resources`. Adding a method is a breaking change for every adapter, so the
surface stays thin. MangaDex is the first real adapter and maps its JSON onto
domain types; nothing above `best_data` knows the API exists.

The bundled `DemoSource` generates seven works, chapters and pages. It is
labelled as a guide, never presented as licensed content, and it exercises the
same reader path as a real source.

## State and navigation

Riverpod 3 without code generation. The repository emits on `changes` after
every successful write; the shelf watches that stream and re-runs its query.
Screens never mutate a local list to fake persistence.

`go_router` with a `StatefulShellRoute.indexedStack` for the four tabs. Series
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

- `best_domain`: pure rules, 18 tests.
- `best_data`: real SQLite in memory, merge cases, MangaDex against a mocked
  HTTP client, 13 tests.
- `best_core`: 7 Rust tests.
- `best_app`: a widget test that renders the shelf and flips the app to Arabic,
  asserting RTL.
- CI also builds a release APK, so a green run means the app compiles for a
  phone, not just for the analyzer.

## Failure policy

- A source failure is a typed error with a retry, not an empty list.
- A missing cover is a deterministic gradient with the first glyph.
- A details request is enrichment; the listing already on screen is enough to
  open the work.
- A failed database open falls back to memory for the session and retries next
  launch. Nothing is written over a corrupt file.
