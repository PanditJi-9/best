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
  page_0001.img.sha256
  page_0002.img
  page_0002.img.sha256
  ...
```

- The folder name is a stable two-round FNV-1a hash of `unitId`, not
  `String.hashCode`, so it survives a restart and a platform change.
- Each page is written to `page_XXXX.img.part` and renamed. A half-written page
  is never visible to the reader.
- Page names are one-based and zero-padded. The reader probes them in numeric
  order and stops at the first missing or empty file; a later scan cannot inherit
  the missing scan's number. A known total caps reading without deleting extras.
- The extension is `.img`: Flutter decodes by content, not by suffix.

## Queue behaviour

- One chapter runs at a time; queued chapters wait in `updatedAt` order.
- Every page is persisted before the next request starts. A crash loses at
  most the request in flight.
- Bytes are counted as pages land and stored on the row. The Downloads screen
  shows each download's size and the total on the device; a row written before
  0.2.1 is backfilled from its directory on the next launch.
- Image-byte accounting excludes checksum sidecars and unfinished `.part` files.
  Repair subtracts replaced bytes rather than counting a replacement twice.
- Bulk download and cleanup apply to the shown selection after confirmation.
  Search and the Failed filter never rewrite the queue or library records.
- A failed page is retried once. A chapter that still fails becomes `failed`
  with a readable message; `retry` starts from the first missing page.
- Pausing cannot cancel a request already in flight, so that page is kept and
  counted, then the task stops. Resuming skips it.
- Finished chapters are read through `FileResource`, never the network. If a
  source fails and a partial directory exists, the reader shows the pages that
  are already on disk instead of an error page.
- A partial chapter keeps its expected total and any later saved position. It
  cannot fabricate completion or automatically skip the missing part. Unknown
  totals remain unknown rather than becoming the length of the cached prefix.
  The vertical HUD and page grid follow the same rule; bookmarks outside the
  available prefix remain saved and are labelled unavailable, not nonexistent.
- Completing a partial download restores the saved scan in paged, paired and
  vertical layouts without counting the restoration as newly read pages. A new
  page-turn still records activity normally. Repaired file images are reloaded
  even when the path is unchanged.
- Per-unit mutation locks and cancellation generations prevent late responses
  from recreating deleted rows or writing into a requeued chapter. Source-list
  updates do not replace the live manager and start a competing writer.

## Check and repair

- Downloads and reader settings share the same **Check saved pages** dialog.
  Checking is local-only. Active tasks must be paused before their files are
  inspected.
- Each new page has an atomic SHA-256 sidecar. Missing files, empty files,
  malformed sidecars and checksum mismatches are reported by original page number.
  A damaged finished task leaves the Ready offline section rather than pretending
  to remain complete.
- **Legacy files without sidecars remain usable**, but are not described as
  checksum-verified. A resume/repair can adopt a baseline for intact legacy bytes;
  this is not authentication of their original content.
- Repair preserves intact images and fetches only missing, empty or changed
  ones, in the existing directory. If a short source response cannot supply the
  previously known total, the total is preserved and the chapter stays incomplete.
- Sources implementing `PageBytesSource` use their own signing/cookie-aware
  image client. A null result declines the request and uses ordinary HTTP;
  empty bytes are a failure, not a completed page.
- A complete interrupted task can be finalized locally even after source
  removal. Missing pages require reinstalling their source. No library, progress,
  bookmarks or presentation preferences are cleared as part of a repair.
- **This checks file presence and byte changes, not image decoding or content
  authenticity.** SHA-256 matches do not prove that an image can be rendered.

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
- Repair follows these same rules. An explicit cap can still evict completed
  units after a repair; a task that has become active again is not evicted from
  an old finished-task snapshot.

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

`download_manager_test.dart` and `download_integrity_test.dart` exercise real
files, checksums, signed-source fetching, selective repair, byte accounting,
network policy, short responses and cancellation/requeue races. App tests cover
shared controls, filtering, source-manager lifetime, reader recovery and
Arabic/English phone renders. SQLite migration/round-trip tests remain separate
from image-decoding and Android playback evidence.
