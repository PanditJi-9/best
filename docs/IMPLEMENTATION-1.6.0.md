# Best 1.6.0 — execution contract

Requested scope: background downloads, a stronger player, optional AniList/MAL
tracking, scheduled followed-work updates, automatic encrypted sync, migration
and local CBZ import, and explicit links between library works and metadata.

All analysis, tests, Android assembly and emulator checks run on GitHub Actions.
No Flutter, Dart, Gradle or Rust verification runs on the phone.

## Invariants

- One download manager owns SQLite transitions and the existing page files.
  Android keeps that engine alive; it must not run a second downloader against
  those same rows. Interrupted requests keep the existing recovery guarantees.
- No silent source change or automatic merge based only on a title.
- Existing library, progress, downloads, profiles and backups stay readable.
- External account connections are optional. Tokens never enter backups, logs
  or plain preferences. OAuth client identifiers must belong to Best, not a
  competing application. Missing configuration is an explicit state.
- Scheduled work is opt-in and respects network policy. Notifications are
  evidence of new units, not a marketing feed.
- A failed operation stays failed until verified recovery; no placeholder
  control or simulated third-party success is described as complete.
- Four APKs share `app.best.best_app`, one version/build and the existing key.

## Delivery gates

- [ ] Download lifetime service: single cached engine, real pause action,
  interrupted-process recovery, no alternate file layout.
- [ ] Player: explicit stream/quality/audio selection, subtitles and PiP;
  switches preserve position and previous paused state.
- [ ] Optional authenticated trackers and per-work confirmed matching.
- [ ] Scheduled library refresh with a persisted updates feed and quiet alerts.
- [ ] Automatic encrypted sync with safe conflict handling and protected keys.
- [ ] Preview-first competitor backup import and bounded, safe CBZ import.
- [ ] Confirmed library/metadata/source associations, usable offline.
- [ ] Unit/widget/JVM gates, four signatures and emulator regression checks.
- [ ] Published build facts and four verified files in Downloads.

Checked boxes require verification, not merely a source edit. A build is not
evidence of a physical-device test or an authenticated external-account test.
