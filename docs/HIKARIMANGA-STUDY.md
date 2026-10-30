# Reference study: HikariManga 1.4.2

A local reconstruction of **HikariManga / هيكاري مانجا** lives at
`/storage/emulated/0/MaxManger/HikariManga-main/HikariManga-main`. It is the
decompiled and documented build of `com.jxj.hikarimanga` 1.4.2 — Kotlin +
Jetpack Compose, Supabase for accounts and sync, and a JavaScript source engine
running inside a `WebView`.

It is a **reference, not a dependency**. No code, asset or key from it is copied
into Best; its licence and provenance are its own. What follows is what the study
changed in this project.

## What the study confirmed

1. **Content is source-driven, not backend-driven.** In 1.4.2 every REST content
   call returns `SERVER_NOT_AVAILABLE`; the catalogue arrives from
   `SourceManager` scripts and is mapped into the same models. A single shelf
   therefore has to sit on an adapter boundary, exactly as `SourceAdapter` does.
2. **The source contract has five scopes**: home rows, search, details, chapters,
   pages — plus per-source tabs and links. Best's pack routes mirror those five
   names one-to-one, so a scripted extension can be projected onto a pack later
   without reshaping the domain.
3. **Arabic needs more than translation.** The original runs ML Kit OCR, an
   on-device translator, then an `ArabicTranslationPolisher`, an idiom dictionary
   and name transliteration, and caches OCR per page. That pipeline, not the
   model choice, is what makes Arabic output readable.
4. **Downloads are a first-class state machine**, not a spinner: chapter and
   custom-range workers, a foreground service, and pause/resume/cancel from the
   notification.
5. **Library limits are a product decision.** Separate favorite and library
   types with per-type caps is how the original monetizes without paywalling
   reading. Best keeps the separation and defers the caps to phase 6.
6. **Monetization is layered**: reading coins, rewarded ads, VIP offers, avatar
   frames, leaderboards. Ads are a later layer, never a prerequisite for the
   reader.

## What Best deliberately does differently

| HikariManga | Best | Reason |
|---|---|---|
| Supabase as the account and data backend | provider-agnostic sync, local-first | no project keys or vendor lock-in in the client |
| JS sources inside a `WebView` in the UI process | QuickJS isolate with a host allowlist (phase 4) | a source must not be able to touch the app or its cookies |
| Native signature/root/Frida guards | none | Best is open and reproducible; guards only fight its own users |
| Content and account on the same server | content adapters + optional sync | a dead server must not empty the shelf |
| Ads and coins in the first release | phase 6, after retention | monetizing an empty library teaches users to leave |

## Parity map

Status values: **shipped**, **next**, **planned**, **rejected**.

| Domain | HikariManga | Best | Phase |
|---|---|---|---|
| Browse | server rows, tabs, search | shipped: sources, popular, search | 0 |
| Library | favorites + typed library, caps | shipped: shelf, favorite, filters; caps planned | 0 / 6 |
| Reader | pages, webtoon slicing, resume | shipped: pages, zoom, resume; slicing next | 0 / 1 |
| OCR + translation | ML Kit + Arabic polisher | planned: on-device OCR, then translate | 3 |
| Source engine | JS in WebView, encrypted packs | shipped: declarative JSON packs; script host planned | 0 / 4 |
| Downloads | WorkManager, notifications | planned: queue, pause/resume, offline reading | 2 |
| Accounts | email/Google, OTP reset | planned: optional, sync only | 5 |
| Community | comments, votes, reports | planned, after sync | 7 |
| Coins + store | reading/rewarded coins, VIP, frames | planned: coins from reading first, no ads in reader | 6 |
| Leaderboards | reading deltas, ranks | planned with sync | 5 |
| Notifications | FCM + in-app list | planned: new chapters only, opt-in | 5 |
| Protection | signature/root/hook checks | rejected | — |
| Monetization | AppLovin MAX mediation | planned: one rewarded placement, no interstitials | 6 |

## Immediate consequence

The first concrete transfer is the pack engine in
[`SOURCE-PACKS.md`](SOURCE-PACKS.md): five routes, three field maps, validation
before install, and no execution. It gives the app real third-party catalogues
today while leaving the scripted tier a clean contract to implement against.
