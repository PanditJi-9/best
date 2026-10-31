# Playback

Best plays episodes in a native full-screen route, `/watch`. The screen is
outside the four-tab shell, so the bottom bar disappears while a video is on.
Chapters keep the page reader; `openUnit` chooses the engine from
`MediaKind.isReading`, and every entry point (series page, continue rail, deep
link) goes through it.

## What ships in 0.3.0

- `video_player` with ExoPlayer/Media3 on Android. HLS (`.m3u8`) and progressive
  MP4 both play.
- Resume in **seconds**, saved every five seconds and on pause, back and
  dispose.
- Completion at 95% of the runtime or the last five seconds. A completed
  episode restarts from zero when opened again.
- ±10 second seeking, 0.75×–2× speed, fullscreen landscape, keep-screen-on
  while playing, buffering and error states with retry.
- The bundled guide streams three public-domain films (Big Buck Bunny,
  Elephants Dream and Sintel) from Google's and Mux's public test buckets. The
  player labels them as samples instead of pretending they are licensed
  episodes.

## Why `video_player`, not `media_kit`

`media_kit` has broader codec coverage and better external subtitle support,
but it ships libmpv native libraries, grows the APK substantially and adds a
second media stack to maintain. `video_player` is the official Flutter plugin,
uses the platform player (ExoPlayer on Android, AVPlayer on iOS) and covers HLS
and MP4 — enough for the first real sources.

The screen depends on `WatchData` and `VideoResource`, not on a particular
plugin API outside `watch_screen.dart`. If subtitle rendering or codec coverage
becomes a hard requirement, `media_kit` can replace the engine behind the same
route and progress rules.

## Progress rules

`UnitProgress.position` is a page for reading and a **second** for video;
`total` is the runtime in seconds. The pure rules live in
`packages/best_domain/lib/src/playback.dart`:

- below three seconds, start at zero instead of seeking noise;
- a saved point at or beyond the reported duration restarts at zero;
- 95% or the last five seconds counts as finished;
- a completed row is never moved backwards by a replay. Replaying starts at
  zero and only writes again when the episode finishes.

The series page's primary button becomes "Continue watching" when a video row
has progress. The shelf's continue rail shows `position / duration` for
episodes and routes them to the player.

## Source contract

For an episode, `SourceAdapter.resources(unit)` returns a `VideoResource`:

```dart
VideoResource(
  url,
  headers: const {},
  subtitleUrl: null,
  mimeType: 'application/vnd.apple.mpegurl',
)
```

The player takes the first `VideoResource`. A source may later return several
qualities or audio tracks; a picker can be added without changing the domain
type. A unit with no video resource fails with a clear "This video could not be
played" screen and a retry, not a blank page.

Declarative source packs are image-only today. Opening an episode from a pack
shows the playback error until the pack format grows a video route.

## Limits

- **No offline video.** Episode rows hide the download control; chapter
  downloads are unchanged. Offline video is a separate phase (file layout,
  storage budget, codec licensing).
- No picture-in-picture, background audio or TV/desktop layout yet.
- One stream per unit; no quality or audio-track picker.
- `subtitleUrl` is modeled but not rendered yet. The next step is a small
  WebVTT/SRT parser and a CC toggle in the player chrome.
- The emulator uses software decoding, so playback there is slower than on a
  phone; the smoke gate checks that a stream opens and no fatal playback error
  is logged, not a frame rate.

## Verification

- `PlaybackProgress` unit tests cover resume, completion, clamping and an
  unknown duration.
- The guide data test asserts every watching work returns an HTTPS
  `VideoResource`, so the demo path cannot silently lose its streams.
- A widget test opens a drama and asserts it offers "Watch now", never "Start
  reading".
- `android-smoke.yml` installs the release APK, drives Browse → Neon Seoul →
  Watch now, taps the surface to reveal the controls, checks the player text,
  and fails on a fatal ExoPlayer/Android error. It uploads a screenshot.
