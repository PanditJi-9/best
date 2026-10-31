# Competitor study — 170 apps and projects

Research for Best's 0.4 "Ink & Jade" redesign. The goal was not to copy a
single app but to find which patterns survive across the whole market, which
ones are noise, and where a small Arabic-first app can be clearly better.

**Method.** GitHub's repository search API was queried for manga readers, anime
streaming, webtoon, comic readers, light novels, self-hosted libraries and
trackers (star counts below are from those queries, October 2026). Commercial
apps were reviewed from their public product pages and store listings. The five
HikariManga screenshots supplied by the owner were analysed separately in
`docs/HIKARIMANGA-STUDY.md`; HikariManga is treated as a visual reference, not
as a source of code or assets.

**Legend.** *Adopt* = a pattern Best should use. *Avoid* = a pattern that costs
users time, trust or battery. Signal is GitHub stars where measured; `—` means a
commercial product or an unmeasured repository.

---

## A. Open-source manga and comic readers

| # | App / project | Link | Signal | Adopt / avoid |
|---|---------------|------|--------|----------------|
| 1 | Mihon | https://github.com/mihonapp/mihon | 24.9k | Adopt: extension catalogue as the product's spine; migrate/backup flow. |
| 2 | Kotatsu | https://github.com/KotatsuApp/Kotatsu | 8.9k | Adopt: suggestions and "continue" on one screen; avoid its dense filter sheets. |
| 3 | Komikku | https://github.com/komikku-app/komikku | 5.0k | Adopt: per-source display settings; avoid settings that need a manual. |
| 4 | Yokai | https://github.com/null2264/yokai | 1.9k | Adopt: library-wide download queue; avoid burying it three levels deep. |
| 5 | Tachiyomi (archived) | https://github.com/tachiyomiorg/tachiyomi | — | The baseline information architecture every Android reader inherits. |
| 6 | TachiyomiSY | https://github.com/jobobby04/TachiyomiSY | — | Adopt: feed of new chapters; avoid feature creep in the reader chrome. |
| 7 | TachiyomiJ2K | https://github.com/Jays2Kings/tachiyomiJ2K | — | Adopt: edge-to-edge reading; avoid custom themes that fight the artwork. |
| 8 | Neko | https://github.com/CarlosEsco/Neko | — | Adopt: clean library grid; the archived status is a warning about bus factor. |
| 9 | Tachidesk Sorayomi | https://github.com/Suwayomi/Tachidesk-Sorayomi | 1.6k | Adopt: one server, many clients; proves the sync model users expect. |
| 10 | Mangayomi | https://github.com/kodjodevf/mangayomi | — | Adopt: one Flutter shell for manga, anime and novels; avoid mixing all three in one list. |
| 11 | Usagi | https://github.com/UsagiApp/Usagi | 288 | Adopt: low-end-device focus; avoid the dated Material 2 look. |
| 12 | Kototoro | https://github.com/Kototoro-app/Kototoro | 656 | Adopt: manga, novel and video in one reader; strong validation of Best's scope. |
| 13 | AniLabX | https://github.com/AniLabX/AniLabX | 286 | Adopt: anime and comics in one app; avoid a launcher-like home. |
| 14 | Zangetsu | https://github.com/Spyou/Zangetsu | 471 | Adopt: multi-media home; avoid a wall of equal-weight posters. |
| 15 | OtakuWorld | https://github.com/jakepurple13/OtakuWorld | 638 | Adopt: shared design system across three apps; avoid duplicated settings. |
| 16 | MangaReader (React Native) | https://github.com/youniaogu/MangaReader | 2.8k | Adopt: gesture reader; avoid a web view disguised as a native screen. |
| 17 | Rulia | https://github.com/RuliaReader/Rulia | 377 | Adopt: Windows reader polish; the desktop-first layout does not translate to phones. |
| 18 | Seeneva | https://github.com/Seeneva/seeneva-reader-android | 370 | Adopt: smart comic panels; avoid requiring a cloud account for local files. |
| 19 | Yomikiru | https://github.com/mienaiyami/yomikiru | 572 | Adopt: offline-first local library; avoid a file-picker-first onboarding. |
| 20 | OpenComic | https://github.com/ollm/OpenComic | 2.0k | Adopt: reading modes (LTR/RTL/webtoon); avoid Electron weight on mobile. |
| 21 | Houdoku | https://github.com/xgi/houdoku | 1.1k | Adopt: extension manager UI; avoid hiding which extension owns a series. |
| 22 | Comic Looms | https://github.com/MapoMagpie/comic-looms | 811 | Adopt: low-load reading; avoid an austere UI with no personality. |
| 23 | Manga TUI | https://github.com/josueBarretogit/manga-tui | 953 | Adopt: keyboard navigation; irrelevant for touch but good for accessibility thinking. |
| 24 | ACBR | https://github.com/binarynonsense/comic-book-reader | 430 | Adopt: format breadth (CBZ/CBR/EPUB); avoid a modal-heavy settings tree. |
| 25 | Villain | https://github.com/btzr-io/Villain | 273 | Adopt: web reader that feels native; avoid tiny tap targets. |
| 26 | Comigo | https://github.com/yumenaka/comigo | 385 | Adopt: cross-platform reader; avoid a terminal aesthetic leaking into mobile. |
| 27 | ComicFlow | https://github.com/swisspol/ComicFlow | 363 | Adopt: local-only simplicity; avoid a frozen design language. |
| 28 | Comimi | https://github.com/yui540/comimi | 479 | Adopt: reusable reader component; avoid dependency on a single framework. |
| 29 | eso | https://github.com/mabDc/eso | 1.8k | Adopt: manga, novel, audio and video in one; avoid a feature list as a home screen. |
| 30 | ComicReader (android-cjj) | https://github.com/android-cjj/ComicReader | 518 | Adopt: simple source abstraction; avoid hard-coded source lists. |
| 31 | iComicReader | https://github.com/Jiang-Fallen/iComicReader | 278 | Adopt: chapter cache; avoid a demo-grade visual system. |
| 32 | ComicReaderApp MVI | https://github.com/hoc081098/ComicReaderApp_MVI_Coroutine_RxKotlin_Jetpack | 293 | Adopt: MVI state discipline; avoid architecture demos that ignore content design. |
| 33 | ExHentai Manga Manager | https://github.com/SchneeHertz/exhentai-manga-manager | 1.8k | Adopt: local tag manager; avoid metadata screens that assume one source. |
| 34 | work_crawler | https://github.com/kanasimi/work_crawler | 4.3k | Adopt: many-source crawler; avoid scraping fragility as a product promise. |

## B. Open-source anime, drama and light-novel apps

| # | App / project | Link | Signal | Adopt / avoid |
|---|---------------|------|--------|----------------|
| 35 | Aniyomi | https://github.com/aniyomiorg/aniyomi | — | Adopt: anime extensions and tracker sync; avoid a reader UI with video bolted on. |
| 36 | CloudStream | https://github.com/recloudstream/cloudstream | — | Adopt: provider plugins; avoid a provider-first home that confuses new users. |
| 37 | Streambert | https://github.com/truelockmc/streambert | 6.4k | Adopt: instant playback; avoid desktop-only assumptions. |
| 38 | Hakuneko | https://github.com/manga-download/hakuneko | 6.4k | Adopt: bulk download UX; avoid a desktop grid on a phone. |
| 39 | Mangal | https://github.com/metafates/mangal | 1.7k | Adopt: a delightful CLI; not a mobile reference. |
| 40 | mangadex-downloader | https://github.com/mansuf/mangadex-downloader | 937 | Adopt: reliable chapter naming; avoid a tool-only mindset. |
| 41 | Kaizoku | https://github.com/oae/kaizoku | 681 | Adopt: server-side queue; avoid making the phone do server work. |
| 42 | LNReader | https://github.com/lnreader/lnreader | 2.9k | Adopt: novel typography and themes; avoid a reader with no chapter progress. |
| 43 | LightNovelReader | https://github.com/dmzz-yyhyy/LightNovelReader | 2.3k | Adopt: EPUB export and custom backgrounds; avoid deep settings before first read. |
| 44 | Wenku8 Android | https://github.com/MewX/light-novel-library_Wenku8_Android | 3.2k | Adopt: a single-source app done well; avoid lock-in. |
| 45 | Taiga | https://github.com/erengy/taiga | 2.3k | Adopt: automatic episode detection; avoid Windows-only patterns. |
| 46 | Nekome | https://github.com/Chesire/Nekome | 522 | Adopt: list tracking without streaming; useful for a future "track only" mode. |
| 47 | Shiru | https://github.com/RockinChaos/Shiru | 652 | Adopt: personal library manager; avoid a spreadsheet feel. |
| 48 | TaiYaKiAnime | https://github.com/Michael24884/TaiYaKiAnime | 592 | Adopt: MAL/SIMKL/AniList sync; avoid three competing progress models. |
| 49 | Kitsune | https://github.com/Dovakiin0/Kitsune | 586 | Adopt: ad-free playback; avoid an empty state with no explanation. |
| 50 | animestream | https://github.com/frostnova721/animestream | 445 | Adopt: download + stream in one; avoid low-contrast dark text. |
| 51 | GoAnime | https://github.com/alvarorichard/GoAnime | 1.1k | Adopt: terminal search; avoid CLI assumptions in mobile UX. |
| 52 | akuse | https://github.com/akuse-app/akuse | 1.1k | Adopt: a calm anime browser; avoid an app that looks like a file manager. |
| 53 | animity | https://github.com/kl3jvi/animity | 1.1k | Adopt: focused "watch" flow; avoid missing offline state. |
| 54 | Zenshin | https://github.com/hitarth-gg/zenshin | 777 | Adopt: AniList-driven discovery; avoid a web wrapper. |
| 55 | Unyo | https://github.com/K3vinb5/unyo-app | 670 | Adopt: combined anime + manga desktop; avoid a cramped three-column layout. |
| 56 | JiruHub | https://github.com/jephersonRD/JiruHub | 313 | Adopt: modern desktop shell; avoid copying desktop density to phones. |
| 57 | Moopa | https://github.com/Ani-Moopa/Moopa | 346 | Adopt: AniList integration; avoid ads-first monetisation. |
| 58 | animeflix | https://github.com/chirag-droid/animeflix | 620 | Adopt: discovery rails; avoid a website that claims to be an app. |
| 59 | migu | https://github.com/NoCrypt/migu | 486 | Adopt: instant torrent streaming; avoid piracy-first positioning. |
| 60 | toru | https://github.com/sweetbbak/toru | 387 | Adopt: fast start; avoid a CLI-only audience. |
| 61 | notify.moe | https://github.com/animenotifier/notify.moe | 350 | Adopt: community ratings; avoid social features before core playback. |
| 62 | AL-chan | https://github.com/zend10/AL-chan | 324 | Adopt: AniList client focus; avoid a thin API wrapper. |
| 63 | Adolla | https://github.com/AdollaApp/Adolla | 320 | Adopt: browser-based reading; avoid no offline story. |
| 64 | AniWorld Downloader | https://github.com/phoenixthrush/AniWorld-Downloader | 347 | Adopt: download queue; avoid legal ambiguity in the product name. |
| 65 | Kaguya | https://github.com/subject-f/guyamoe | 492 | Adopt: clean web reading; avoid a desktop-only information density. |
| 66 | Light-Novel-Yuedu-Source | https://github.com/ZWolken/Light-Novel-Yuedu-Source | 450 | Adopt: source packs as data; avoid opaque source code. |
| 67 | source-j-legado | https://github.com/jiwangyihao/source-j-legado | 673 | Adopt: declarative source rules; avoid runtime scripting without a sandbox. |

## C. Self-hosted libraries, servers and tools

| # | App / project | Link | Signal | Adopt / avoid |
|---|---------------|------|--------|----------------|
| 68 | Kavita | https://www.kavitareader.com | — | Adopt: server + OPDS; avoid a web-admin-first onboarding. |
| 69 | Komga | https://komga.org | — | Adopt: clean library API; avoid assuming a desktop browser. |
| 70 | Ubooquity | https://vaemendis.net/ubooquity | — | Adopt: simple self-hosting; avoid a dated UI. |
| 71 | Mylar3 | https://github.com/mylar3/mylar3 | — | Adopt: automated pull lists; avoid comic-vine complexity. |
| 72 | Kapowarr | https://github.com/Casvt/Kapowarr | — | Adopt: volume/issue model; avoid a downloader-only identity. |
| 73 | Readarr | https://readarr.com | — | Adopt: wanted-list automation; avoid book-only metadata. |
| 74 | Suwayomi-Server | https://github.com/Suwayomi/Suwayomi-Server | — | Adopt: headless source engine; avoid requiring a server for first use. |
| 75 | Tachidesk-Server | https://github.com/Suwayomi/Tachidesk-Server | — | Adopt: one library, many clients; avoid a second-class mobile client. |
| 76 | TachiWeb-Server | https://github.com/TachiWeb/TachiWeb-Server | 420 | Adopt: web access to a library; avoid stale dependencies. |
| 77 | Codex | https://github.com/ajslater/codex | 327 | Adopt: archive browser; avoid a file-manager home. |
| 78 | Mango | https://github.com/getmango/Mango | 1.8k | Adopt: self-hosted web reader; avoid a bare-bones mobile web view. |
| 79 | Teemii | https://github.com/dokkaner/teemii | 556 | Adopt: agent-based metadata; avoid slow first paint. |
| 80 | librarr | https://github.com/JeremiahM37/librarr | 296 | Adopt: multi-source search; avoid a settings wall. |
| 81 | Polaris | https://github.com/simon-ding/polaris | 387 | Adopt: TV/movie tracking + downloads; adjacent, not core. |
| 82 | Jellyfin | https://jellyfin.org | — | Adopt: open media server; avoid a plugin ecosystem as the only path. |
| 83 | Emby | https://emby.media | — | Adopt: polished playback; avoid closed ecosystem lock-in. |
| 84 | Calibre | https://calibre-ebook.com | — | Adopt: metadata editing; avoid desktop-scale dialogs on mobile. |
| 85 | KCC | https://github.com/ciromattia/kcc | 5.9k | Adopt: device-aware conversion; avoid making conversion the product. |
| 86 | Kobo | https://www.kobo.com | — | Adopt: reading typography; avoid store-first navigation. |
| 87 | Hoopla | https://www.hoopladigital.com | — | Adopt: library-card borrowing; a future legal content path. |

## D. Commercial manga, webtoon and novel services

| # | App / project | Link | Signal | Adopt / avoid |
|---|---------------|------|--------|----------------|
| 88 | WEBTOON | https://www.webtoons.com | — | Adopt: vertical-scroll reader and daily schedule; avoid an ad between every episode. |
| 89 | Tapas | https://tapas.io | — | Adopt: creator-forward discovery; avoid coin popups mid-chapter. |
| 90 | Manta | https://manta.net | — | Adopt: subscription clarity; avoid hiding the price until the last tap. |
| 91 | Piccoma | https://piccoma.com | — | Adopt: chapter-first merchandising; avoid a casino-like reward UI. |
| 92 | KakaoPage | https://page.kakao.com | — | Adopt: strong series pages; avoid a dense storefront on first open. |
| 93 | Naver Series | https://series.naver.com | — | Adopt: clean episode lists; avoid a web page inside an app shell. |
| 94 | Tappytoon | https://www.tappytoon.com | — | Adopt: mature-romance catalogue rails; avoid paywall ambiguity. |
| 95 | Lezhin | https://www.lezhin.com | — | Adopt: age-gate clarity; avoid a confusing coin economy. |
| 96 | Toomics | https://toomics.com | — | Adopt: genre landing pages; avoid autoplay teasers with sound. |
| 97 | Bilibili Comics | https://www.bilibilicomics.com | — | Adopt: manhua catalogue breadth; avoid region-locked dead ends. |
| 98 | Kuaikan | https://www.kuaikanmanhua.com | — | Adopt: fast vertical reader; avoid an account wall for browsing. |
| 99 | Tencent Dongman | https://ac.qq.com | — | Adopt: chapter thumbnails; avoid visual clutter. |
| 100 | MANGA Plus | https://mangaplus.shueisha.co.jp | — | Adopt: "latest chapter free" model; avoid a countdown that feels punitive. |
| 101 | VIZ Manga | https://www.viz.com | — | Adopt: publisher-grade metadata; avoid a slow catalogue. |
| 102 | Kodansha | https://kodansha.us | — | Adopt: curated imprint pages; avoid a blog-like store. |
| 103 | MangaBox | https://www.mangabox.me | — | Adopt: free daily chapters; avoid a confusing unlock timer. |
| 104 | Comico | https://www.comico.jp | — | Adopt: original-series promotion; avoid a busy home. |
| 105 | LINE Manga | https://manga.line.me | — | Adopt: strong ranking rails; avoid notification spam. |
| 106 | Renta! | https://www.renta.papy.co.jp | — | Adopt: rental clarity; avoid a checkout maze. |
| 107 | BookWalker | https://global.bookwalker.jp | — | Adopt: publisher catalogue depth; avoid desktop-style grids on phones. |
| 108 | Kindle | https://www.amazon.com/kindle | — | Adopt: sync across devices; avoid a store-first reading app. |
| 109 | Google Play Books | https://play.google.com/books | — | Adopt: upload-your-own-file flow; avoid generic Material chrome. |
| 110 | Apple Books | https://www.apple.com/apple-books | — | Adopt: typographic calm; avoid platform-only thinking. |
| 111 | Libby | https://libbyapp.com | — | Adopt: library-card onboarding; a model for legal free content. |
| 112 | Marvel Unlimited | https://www.marvel.com/unlimited | — | Adopt: guided reading orders; avoid infinite catalogue paralysis. |
| 113 | DC Universe Infinite | https://www.dcuniverseinfinite.com | — | Adopt: character/arc browsing; avoid a subscription wall before discovery. |
| 114 | MangaPlaza | https://mangaplaza.com | — | Adopt: genre filters; avoid tiny type. |
| 115 | Azuki | https://azuki.co | — | Adopt: curated indie manga; avoid a thin catalogue presented as endless. |
| 116 | Manga UP! | https://manga-up.com | — | Adopt: chapter release calendar; avoid aggressive monetisation. |
| 117 | Comikey | https://comikey.com | — | Adopt: simultaneous release labels; avoid a confusing lock model. |
| 118 | Coolmic | https://coolmic.me | — | Adopt: genre taxonomy; avoid a dated visual system. |
| 119 | INKR Comics | https://inkr.com | — | Adopt: publisher partnerships; avoid an app that is really a web wrapper. |
| 120 | Webnovel | https://www.webnovel.com | — | Adopt: chapter comments; avoid gamified noise on every screen. |
| 121 | Wuxiaworld | https://www.wuxiaworld.com | — | Adopt: novel chapter navigation; avoid a forum-first home. |
| 122 | Royal Road | https://www.royalroad.com | — | Adopt: serial fiction discovery; avoid a web-only reading experience. |
| 123 | Wattpad | https://www.wattpad.com | — | Adopt: creator community; avoid algorithmic feed overload. |
| 124 | Radish | https://radishfiction.com | — | Adopt: episodic fiction; avoid paywall friction. |
| 125 | NovelUpdates | https://www.novelupdates.com | — | Adopt: release tracking; avoid a database-first UI. |

## E. Commercial anime, drama and players

| # | App / project | Link | Signal | Adopt / avoid |
|---|---------------|------|--------|----------------|
| 126 | Crunchyroll | https://www.crunchyroll.com | — | Adopt: simulcast calendar and watchlist; avoid autoplay trailers with sound. |
| 127 | HIDIVE | https://www.hidive.com | — | Adopt: niche catalogue curation; avoid a dated player. |
| 128 | Netflix | https://www.netflix.com | — | Adopt: resume row and trailer previews; avoid autoplay that ignores intent. |
| 129 | Prime Video | https://www.primevideo.com | — | Adopt: "continue watching" across devices; avoid mixing rent/buy confusion. |
| 130 | Disney+ | https://www.disneyplus.com | — | Adopt: brand-led rails; avoid hiding subtitles settings. |
| 131 | Hulu | https://www.hulu.com | — | Adopt: next-episode flow; avoid ad volume. |
| 132 | Max | https://www.max.com | — | Adopt: cinematic hero art; avoid slow startup. |
| 133 | Viki | https://www.viki.com | — | Adopt: timed subtitles and language learning; ideal for K-drama. |
| 134 | Kocowa | https://www.kocowa.com | — | Adopt: K-drama catalogue focus; avoid region-locked dead ends. |
| 135 | iQIYI | https://www.iq.com | — | Adopt: Asian drama breadth; avoid a cluttered storefront. |
| 136 | WeTV | https://wetv.vip | — | Adopt: vertical drama shorts; adjacent trend worth watching. |
| 137 | Youku | https://www.youku.com | — | Adopt: episode thumbnails; avoid aggressive upsell. |
| 138 | Bilibili | https://www.bilibili.com | — | Adopt: danmaku community; avoid covering the video by default. |
| 139 | RetroCrush | https://www.retrocrush.tv | — | Adopt: curated classics; avoid a thin catalogue with no context. |
| 140 | Tubi | https://tubitv.com | — | Adopt: free ad-supported access; avoid ad density. |
| 141 | Pluto TV | https://pluto.tv | — | Adopt: linear channels; avoid a TV-guide UI on mobile. |
| 142 | Plex | https://www.plex.tv | — | Adopt: personal media + discovery; avoid account complexity. |
| 143 | Stremio | https://www.stremio.com | — | Adopt: addon model; avoid legal ambiguity. |
| 144 | Kodi | https://kodi.tv | — | Adopt: playback engine depth; avoid configuration as a first-run experience. |
| 145 | VLC | https://www.videolan.org/vlc | — | Adopt: format support; avoid a desktop control layout on phones. |
| 146 | MX Player | https://www.mxplayer.in | — | Adopt: gesture controls; avoid ad-heavy chrome. |
| 147 | mpv | https://mpv.io | — | Adopt: quality and subtitle control; avoid an expert-only UI. |
| 148 | Just Player | https://github.com/moneytoo/Player | — | Adopt: a player that does one thing; avoid feature sprawl. |
| 149 | Next Player | https://github.com/anilbeesetti/nextplayer | — | Adopt: modern Material 3 video UI; direct reference for Watch. |
| 150 | Fermata | https://github.com/AndreyPavlenko/Fermata | — | Adopt: media3-first playback; avoid a TV-only layout. |
| 151 | Moon+ Reader | https://www.moondownload.com | — | Adopt: reading themes and paging; avoid a settings tree with 200 switches. |
| 152 | Librera | https://librera.mobi | — | Adopt: format breadth; avoid a busy toolbar. |
| 153 | KOReader | https://koreader.rocks | — | Adopt: typography and dictionary; avoid a power-user-only surface. |
| 154 | Perfect Viewer | https://play.google.com/store/apps/details?id=com.rookiestudio.perfectviewer | — | Adopt: panel zoom; avoid a 2012 visual language. |
| 155 | CDisplayEx | https://www.cdisplayex.com | — | Adopt: fast local opening; avoid desktop density. |
| 156 | YACReader | https://www.yacreader.com | — | Adopt: library + reader split; avoid a desktop-only flow. |
| 157 | Panels | https://panels.app | — | Adopt: iOS reading polish; avoid platform exclusivity. |
| 158 | ComicRack | https://comicrack.cyolito.com | — | Adopt: metadata power; avoid an abandoned-product risk. |

## F. Trackers and discovery

| # | App / project | Link | Signal | Adopt / avoid |
|---|---------------|------|--------|----------------|
| 159 | AniList | https://anilist.co | — | Adopt: rich metadata and lists; avoid social feed as the default tab. |
| 160 | MyAnimeList | https://myanimelist.net | — | Adopt: the canonical status model; avoid a dated web UI. |
| 161 | Shikimori | https://shikimori.one | — | Adopt: community scores; avoid a forum-first home. |
| 162 | Kitsu | https://kitsu.app | — | Adopt: cross-media library; avoid slow catalogue pages. |
| 163 | Trakt | https://trakt.tv | — | Adopt: scrobbling; avoid requiring an account to play local files. |
| 164 | Simkl | https://simkl.com | — | Adopt: automatic tracking; avoid import friction. |
| 165 | Bangumi | https://bgm.tv | — | Adopt: deep anime metadata; avoid an encyclopedic first screen. |
| 166 | AniDB | https://anidb.net | — | Adopt: episode-level data; avoid a database UI. |
| 167 | IMDb | https://www.imdb.com | — | Adopt: cast/crew depth; avoid ads and autoplay. |
| 168 | JustWatch | https://www.justwatch.com | — | Adopt: "where to watch" clarity; a future availability layer. |
| 169 | Reelgood | https://reelgood.com | — | Adopt: cross-service search; avoid account-first browsing. |
| 170 | Letterboxd | https://letterboxd.com | — | Adopt: tasteful editorial typography; avoid review-first onboarding. |

---

## What the market says

Five patterns appear in almost every successful app and are now part of Best:

1. **Resume beats browse.** Netflix, Prime Video, Mihon and Kotatsu all put the
   unfinished thing within one tap. Best's Home moves the continue rail above
   trending as soon as there is progress.
2. **Artwork is the interface.** The apps that feel premium (Max, Manta, Panels)
   let covers carry the colour and keep chrome near-black or near-white. Best's
   "Ink & Jade" palette is deliberately four colours, not twelve.
3. **Chapter rows are the real product.** Readers spend their time in the unit
   list. The best ones (Mihon, TachiyomiSY, Manga UP!) show read state, download
   state and the number in one row; Best now does the same with a progress ring,
   download control and a numbered chip.
4. **Offline is a first-class tab, not a settings toggle.** Yokai, Aniyomi and
   Netflix all make downloads visible. Best gives Downloads its own destination
   and a storage strip.
5. **A source is a pill, not a form.** Kotatsu, Mangayomi and CloudStream all
   let people switch catalogues with one tap. Best's Browse uses source pills and
   keeps search scoped to the selected source.

Four patterns are common but were deliberately rejected:

- **Storefront-first home.** Piccoma, KakaoPage and WEBTOON open on a shop.
  Best opens on the user's own progress; the store is one tab away.
- **Notification and coin pressure.** Countdown timers, daily reward badges and
  mid-chapter popups were the most cited complaints in store reviews. Best has
  no such surface.
- **Dense desktop grids.** Houdoku, OpenComic and YACReader look great at
  1440px and unreadable at 320px. Best's grids are sized from the viewport.
- **Chrome that competes with art.** Neon gradients, glass everywhere and five
  accent colours make covers look cheap. Best uses one gradient, one accent and
  one warm highlight, and reserves vermilion for "new/live".

## Where Best can be clearly better

- **Arabic and English are equal citizens**, not a translation layer. Every
  layout is built with `EdgeInsetsDirectional`, logical alignment and RTL tests.
- **One library for reading and watching.** Most competitors pick one medium.
  Best's unit model already unifies chapters and episodes, and the reader/watch
  router chooses by media kind.
- **A real offline story from day one.** Chapter downloads, a persistent queue,
  storage accounting and resume-from-page are core, not a premium feature.
- **Calm by default.** No ads, no coin timers, no autoplay sound. Motion is
  short (140–220 ms) and only confirms an action.
- **A source pack is declarative JSON.** No code runs, the host is pinned, and a
  bad pack fails with a readable error instead of a crash.

The full identity and layout blueprint is in `docs/DESIGN.md`.
