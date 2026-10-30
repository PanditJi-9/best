# Source packs

Best reads catalogues through one interface, `SourceAdapter`. A catalogue can be
reached three ways, and they are deliberately separate tiers:

| Tier | Mechanism | Status |
|---|---|---|
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

Packs are per-device in 0.1.0. Export/import and a signed pack index arrive with
sync, so a pack never silently changes under a running library.
