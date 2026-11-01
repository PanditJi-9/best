# Source packs

Best reads catalogues through one interface, `SourceAdapter`. A catalogue can be
reached three ways, and they are deliberately separate tiers:

| Tier | Mechanism | Status |
|---|---|---|
| 0 | **Suwayomi server** — the reader's own server runs the Mihon/Komikku extension APKs; Best speaks its REST API | shipped in 0.9.0 |
| 1 | **Declarative JSON pack** — routes plus field paths | shipped in 0.1.0 |
| 2 | **Sandboxed script host** — JS/QuickJS with a reviewed bridge | planned, phase 3 |
| 3 | **Native adapter** — compiled Dart, e.g. `MangaDexSource` | shipped for MangaDex |

A pack is a manifest, not a program. It cannot read the library, the filesystem,
the clipboard or any host it does not name, because nothing in it executes.

## Format

```json
{
  "id": "example",
  "name": "Example",
  "language": "ar",
  "baseUrl": "https://api.example.com",
  "kind": "manhwa",
  "unitKind": "chapter",
  "headers": { "referer": "https://example.com" },
  "routes": {
    "popular": "/popular?page={page}",
    "search": "/search?q={query}&page={page}",
    "details": "/series/{id}",
    "chapters": "/series/{id}/chapters",
    "pages": "/chapter/{id}/pages"
  },
  "map": {
    "media": {
      "list": "data",
      "id": "slug",
      "title": "title",
      "nativeTitle": "originalTitle",
      "cover": "cover",
      "synopsis": "description",
      "author": "author",
      "status": "status",
      "genres": "genres",
      "kind": "type"
    },
    "unit": {
      "list": "chapters",
      "id": "id",
      "number": "number",
      "title": "title",
      "date": "publishedAt",
      "pages": "pageCount"
    },
    "page": { "list": "pages", "url": "url" }
  }
}
```

### Format 2 — a streaming pack

Version 2 adds `routes.watch` and `map.video`; everything else is unchanged. A
pack is either a page pack or a video pack, never both, because a work is either
read or watched.

```json
{
  "version": 2,
  "id": "example-video",
  "name": "Example Video",
  "language": "ar",
  "baseUrl": "https://api.example.com",
  "kind": "anime",
  "unitKind": "episode",
  "routes": {
    "popular": "/shows?page={page}",
    "search": "/shows?q={query}&page={page}",
    "chapters": "/shows/{id}/episodes",
    "pages": "/unused",
    "watch": "/episodes/{id}/stream"
  },
  "map": {
    "media": { "list": "data", "id": "id", "title": "title" },
    "unit": {
      "list": "episodes",
      "id": "id",
      "number": "number",
      "title": "title"
    },
    "page": { "list": "pages", "url": "url" },
    "video": { "list": "sources", "url": "file", "subtitle": "captions" }
  }
}
```

`map.video.subtitle` is optional. When present it points at a WebVTT or SRT
track, and the player offers the CC toggle. `routes.watch` must contain `{id}`.

### Rules

- `id` — 2–40 characters, `[a-z0-9._-]`, cannot be `demo` or `mangadex`.
- `baseUrl` — absolute, **https only**; `http` is accepted for `localhost` and
  `127.0.0.1` so a self-hosted catalogue can be tested.
- `routes.popular` must contain `{page}`, `routes.search` must contain
  `{query}`. `{id}` is the source's own key for a work, never a title.
- `map.media.list`, `map.unit.list`, `map.page.list` are dot paths into the
  response. An empty string means "the response root is the list".
- `map.unit.number` is optional: without it, the position in the list is the
  number. Fractional numbers are supported (`12.5`).
- Relative covers and page URLs resolve against `baseUrl`.
- `details` is optional. When absent, the listing is the detail.
- `headers` are sent with every request and every image load.

### Limits

| Limit | Value | Why |
|---|---|---|
| Pack document | 48 KB | a manifest, not a database |
| Catalogue response | 8 MB | a phone should not buffer more |
| Items per listing | 120 | pagination is the source's job |
| Units per work | 2,000 | guards a broken endpoint |
| Pages per unit | 2,000 | same |
| Request timeout | 20 s | a stalled host must not freeze a screen |

## Tier 0 — a Suwayomi server

The extensions Mihon, Komikku and Aniyomi install are Android APK files. They
run inside a Kotlin app, so a Flutter app cannot load them, and shipping them
inside Best would mean shipping scrapers for sites that host unlicensed scans.

[Suwayomi](https://github.com/Suwayomi/Suwayomi-Server) is the missing half: an
open-source server that runs those same extensions and exposes them over REST.
Best talks to it, and nothing else changes about the app.

```
Settings → Suwayomi server → http://192.168.1.20:4567
```

What that buys the reader:

- **Hundreds of manga sources**, the same catalogue the Mihon/Komikku family
  uses, each with its own popular list, search and filters.
- **Updates without an app release.** The server installs and updates the
  extensions; Best re-reads `/api/v1/source/list` and shows whatever is there.
- **No credentials in Best.** The address is the only thing stored, in
  `SharedPreferences` under `suwayomi_url`. Nothing is proxied through us.

What it costs:

- **One setup step.** A server has to run somewhere — a computer, a NAS, a
  Raspberry Pi, a VPS. The server's own docs cover Docker and native installs.
- **Manga only.** Suwayomi runs Tachiyomi/Komikku extensions; Aniyomi's anime
  extensions are a different engine and are not supported here.
- **The reader's network, the reader's rules.** Best ships no extension and no
  scraper. Whether a given source is lawful in a given country is between the
  reader and that source, exactly as it is for Mihon.

Endpoints Best uses, all under `/api/v1`:

| Call | Path | Used for |
|---|---|---|
| source list | `/source/list` | Browse pills, and the adapter's name/language/icon |
| popular | `/source/{id}/popular/{page}` | the source's front page |
| search | `/source/{id}/search?searchTerm=&pageNum=` | search inside one source |
| details | `/manga/{id}/full` | cover, author, synopsis, status |
| chapters | `/manga/{id}/chapters` | the chapter list (`index` is 1-based) |
| chapter | `/manga/{id}/chapter/{index}` | `pageCount`, and it makes the server fetch pages |
| page | `/manga/{id}/chapter/{index}/page/{n}` | the image itself |

Relative thumbnails and icons are resolved against the server's own base URL, so
a server behind a reverse proxy with a path prefix works. Home and the "All
sources" search deliberately skip `suwayomi:` adapters: asking hundreds of
sources at once on every refresh would hammer the server, so a server source is
one tap away in Browse instead.

Client and adapter: `packages/best_data/lib/src/sources/suwayomi_source.dart`.
Tests: `packages/best_data/test/suwayomi_source_test.dart`.

## What a pack cannot do

- Scrape HTML. That needs selectors and a DOM, which is tier 2's job.
- Solve Cloudflare, decrypt a payload or sign a request.
- Run JavaScript, read files or call another host.

Those are exactly the features that make scripted extension engines powerful and
dangerous. Tier 2 will ship with a QuickJS isolate, a host allowlist per
extension, no filesystem bridge, and a review checklist — the same boundary
HikariManga draws around its WebView runner (`JsScraperRunner`,
`nativeHttpGet`/`nativeHttpPost`, `CloudflareBypassManager`), but outside the
UI process.

## Where it lives

- Engine and validation: `packages/best_data/lib/src/sources/source_pack.dart`
- Tests: `packages/best_data/test/source_pack_test.dart`
- Install UI: Settings → Source packs → Add a source pack
- Storage: `SharedPreferences` key `source_packs_v1`, raw documents only, no
  credentials.

Packs travel: a backup exports each one in its canonical form, and an encrypted
sync uploads them with the shelf, so a new phone gets the library and the sources
that made it. A signed pack index — one URL that lists reviewed packs — is the
next step, not a promise.

## What ships built in

| Source | Kind | Why it is built in |
|---|---|---|
| **MangaDex** | native adapter | A documented public API, a catalogue of tens of thousands of works, free chapters in many languages, and a takedown process the app can point at. |
| **Best Guide** | native adapter | Seven generated works and three public-domain films. Offline, no network, no account: it exists so a fresh install can open a chapter before anything is configured. |
| **Your packs** | declarative JSON | Whatever catalogue you add in Settings. |
| **A Suwayomi server** | REST client (tier 0) | Optional, off until the reader pastes an address. It runs the Mihon/Komikku extensions, so the catalogue updates without a Best release. |

Best does **not** bundle scrapers for manga aggregators or pirate sites. That is
a deliberate product decision, not a missing feature: a scraper for a site that
hosts unlicensed scans is both a legal risk and a maintenance treadmill, and it
is the first thing a store review removes. The pack format exists so a catalogue
that publishes a JSON API can be added without shipping code, and the sandboxed
script host (tier 2) is the path for sites that only publish HTML.
