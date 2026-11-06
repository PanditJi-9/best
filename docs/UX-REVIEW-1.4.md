# Best 1.4 — real-life UX review

## Scope and evidence

This pass focuses on the user journeys already supported by Best. It does not
claim that every third-party source works, that downloading survives Android
killing the process, or that an APK build proves device usability.

Public user requests reviewed:

- [Mihon #3050](https://github.com/mihonapp/mihon/issues/3050), March 2026:
  downloaded chapters disappeared or duplicated after metadata refresh. Best's
  directories are keyed by stable unit IDs, not changing titles or scanlator
  labels; checks and repairs keep valid files instead of clearing the library.
  A genuinely changed source URL is still a different identity, not silently
  merged with another edition by chapter number.

- [Mihon #3247](https://github.com/mihonapp/mihon/issues/3247), April 2026:
  a filtered chapter could send a reader backwards. Best keeps display filters
  separate from the full navigation sequence and tests it through GoRouter.
- [Mihon #4167](https://github.com/mihonapp/mihon/issues/4167), October 2026:
  repeated chapter groups and partial source coverage make bulk downloads
  confusing. Best deduplicates exact IDs, preserves signing memo, keeps distinct
  editions, and downloads only the shown selection after confirmation. It does
  not silently combine unrelated sources by chapter number.
- [Mihon reader settings](https://mihon.app/docs/guides/reader-settings):
  direction, scaling and webtoon-specific choices are part of the reading
  experience. Best adds explicit per-work scope and tablet pairing without
  changing the phone's device-wide policies.
- [Aniyomi #408](https://github.com/aniyomiorg/aniyomi/issues/408):
  quality selection is important. It remains a separate task requiring source
  quality metadata and real player/device tests; this pass does not relabel the
  first returned stream as a verified best-quality choice.
- [share_plus API](https://pub.dev/packages/share_plus): a system share sheet is
  a user-chosen export boundary, not proof of delivery or automatic cloud backup.

## Decisions

| Scenario | Behaviour and why |
| --- | --- |
| Return after stopping on page one | A real saved first-page session counts as started. It stays in continuation and does not also appear as an unstarted title. |
| Several partial chapters | Continue selects the latest progress, not the first partial row in a source feed. The button names the exact chapter and saved position. |
| Save several times or return to another tab | Database events use distinct revisions; repeated void/null events cannot be swallowed as equal values by Riverpod. Read-only queries refresh without re-fetching the source. |
| Finish every chapter | Replay is explicit and starts from the beginning. Normal resume still honours a saved position. |
| Source is removed or temporarily offline | Stored metadata, chapter rows and progress stay visible. Downloaded pages are resolved before requiring an installed source. |
| Only a chapter prefix is downloaded | The reader keeps the expected total, warns about partial content, preserves a later saved position, and does not fabricate completion or skip missing pages automatically. |
| A stored page is missing, empty or changed | Local checks report original page numbers. Explicit repair keeps intact files, uses the source's signed image client when available, and follows device network/storage policy. |
| A partial download finishes while the reader is open | Restore the saved scan after layout in paged, paired or vertical mode; the restoration does not inflate reading statistics, including the neighbouring scan of a pair. New page turns still count normally. |
| A partial archive has an unknown total or inaccessible bookmarks | Footer, HUD and page grid never treat the available prefix as the whole chapter. Saved bookmarks outside that prefix are described as unavailable, not missing from the user's data. |
| Find chapter 240 in a long series | Open at the current chapter, search normalized Arabic/Persian numbers, and return to current without reloading it. Episode lists use episode wording and player navigation. |
| Choose an episode or leave the player | Pause while choosing; resume the same episode only if it was already playing. Cache the repository before disposal so final progress does not depend on a deactivated widget. |
| Search or filter a chapter list | Only presentation changes. Progress, the source list, and chapter navigation are not rewritten. |
| Tablet or split-screen | Overview and chapter tools use separate panes on wide viewports; narrow viewports remain one column. Search/filter controls pin naturally without guessed fixed heights. |
| Keep a backup | Export goes to the system chooser. A local copy is described as app-local, and plain JSON is explicitly labelled unencrypted. |
| Restore on a new phone | Marks merge by union; existing work styles remain unchanged; defaults fill only an unset device. Empty category names survive. Device protection, network policies and credentials are not imported. |
| Remove an item from the shelf | Ask before removal; progress and downloaded files are retained. Opening a work still does not add it implicitly. |
| Favorite a newly discovered title | The action adds it to the shelf deliberately so the favorite can be found later. |

## Release gates

- Pure Dart policy/serialization tests, real repository tests, Flutter
  compilation and widget tests, Arabic/English parity and formatting.
- Actual widget renders inspected for phone/tablet layouts and Arabic large text,
  not only a successful test counter. Test pictures use explicit guide fixtures.
- CI Flutter analysis, full test suite, signed release APK and runtime ABI tests.
- Android smoke and a real-device review remain distinct from build evidence.

No public release tag should be created merely because the UI work is finished.
