# Offline downloads

Best stores downloaded chapters as plain files in the app's documents
directory and records every transition in SQLite. There is no hidden cache and
nothing is downloaded without a tap.

## What a download is

A download is a `DownloadTask` row, keyed by `unitId` (`mediaId::unitUrl`). It
carries the source addresses, copied titles, page counts, bytes written and a
state:

```
queued ──► running ──► done
              │  ▲
              ▼  │
            paused
              │
              ▼
            failed ──► queued   (retry)
```

`cancel` deletes the row first, then the directory. A task that was `running`
when the process died is reset to `queued` on the next launch and continues
from the files already on disk.

## File layout

```
<app documents>/downloads/<16-hex-folder>/
  page_0001.img
  page_0002.img
  ...
```

- The folder name is a stable two-round FNV-1a hash of `unitId`, not
  `String.hashCode`, so it survives a restart and a platform change.
- Each page is written to `page_XXXX.img.part` and renamed. A half-written page
  is never visible to the reader.
- `page_XXXX` is zero-padded, so a plain filename sort is reading order.
- The extension is `.img`: Flutter decodes by content, not by suffix.

## Queue behaviour

- One chapter runs at a time; queued chapters wait in `updatedAt` order.
- Every page is persisted before the next request starts. A crash loses at
  most the request in flight.
- Bytes are counted as pages land and stored on the row. The Downloads screen
  shows each download's size and the total on the device; a row written before
  0.2.1 is backfilled from its directory on the next launch.
- "Download all" queues every chapter that is not finished, after a
  confirmation; "delete finished" removes them in one pass.
- A failed page is retried once. A chapter that still fails becomes `failed`
  with a readable message; `retry` starts from the first missing page.
- Pausing cannot cancel a request already in flight, so that page is kept and
  counted, then the task stops. Resuming skips it.
- Finished chapters are read through `FileResource`, never the network. If a
  source fails and a partial directory exists, the reader shows the pages that
  are already on disk instead of an error page.

## Policy: network and storage

Two app-level rules, both read through closures so changing a setting never
rebuilds the manager (and therefore never drops a unit in flight):

- **Wi-Fi only.** `mayDownload()` returns false on a metered connection, and the
  queue stops before starting the next unit. Pages already in flight finish, so
  a chapter is never left half-written. `NetworkKind.unknown` — a VPN, a missing
  plugin, a permission the person declined — never blocks a download; guessing
  "metered" would silently stop the app.
- **Storage cap.** `storageCap()` returns the limit in bytes, `0` for none. When
  a unit finishes, `evictIfNeeded` removes finished units oldest-first until the
  store fits. A unit that is still downloading is never evicted: that would undo
  a person's tap.

The Downloads screen groups finished units by work, shows each work's size, and
offers one control to reclaim it. `LibraryFilter.offline` reads the per-work
offline count that the shelf query already computes, so the filter costs no
extra query.

## Limits

- Downloads run while the app process is alive. A true background service
  (WorkManager/foreground service) is a later phase; the queue survives being
  killed and resumes, but it does not keep downloading while the app is gone.
- Video is not downloadable yet. Episode rows hide the download control; a
  chapter and an episode never share a queue entry.
- Only `ImageResource` pages are stored. Episode files need the playback engine.

## Tests

`packages/best_data/test/download_manager_test.dart` drives the real manager
against a `MockClient` and a temp directory: full chapter, pause/resume,
failure/retry, cancel, byte accounting, eviction under a cap, the Wi-Fi gate,
and restore-after-restart. `data_test.dart` covers the SQLite round-trip and the
schema 1 → 4 migrations.
