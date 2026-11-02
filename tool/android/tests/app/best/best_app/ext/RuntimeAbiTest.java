package app.best.best_app.ext;

import eu.kanade.tachiyomi.animesource.model.SAnime;
import eu.kanade.tachiyomi.animesource.model.SEpisode;
import eu.kanade.tachiyomi.animesource.model.FetchType;
import eu.kanade.tachiyomi.animesource.model.Video;
import eu.kanade.tachiyomi.animesource.model.Hoster;
import eu.kanade.tachiyomi.animesource.model.ChapterType;
import eu.kanade.tachiyomi.animesource.online.AnimeHttpSource;
import eu.kanade.tachiyomi.source.online.HttpSource;
import eu.kanade.tachiyomi.source.model.FilterList;
import eu.kanade.tachiyomi.source.model.MangasPage;
import eu.kanade.tachiyomi.source.model.Page;
import eu.kanade.tachiyomi.source.model.SChapter;
import eu.kanade.tachiyomi.source.model.SManga;
import kotlin.jvm.internal.DefaultConstructorMarker;
import okhttp3.CacheControl;
import okhttp3.Headers;
import okhttp3.Request;
import okhttp3.Response;
import java.util.Collections;
import java.util.List;
import org.junit.Test;
import static org.junit.Assert.*;

/** Pin the JVM contract that real extension dex uses, not merely Kotlin syntax. */
public class RuntimeAbiTest {
    @Test public void animeModelsAreInterfacesWithRealFactories() {
        assertTrue(SAnime.class.isInterface());
        assertTrue(SEpisode.class.isInterface());
        SAnime anime = SAnime.Companion.create();
        anime.setUrl("/anime/one");
        anime.setTitle("One");
        assertEquals("/anime/one", anime.getUrl());
        assertEquals("One", anime.getTitle());
        assertEquals(FetchType.Episodes, anime.getFetch_type());
        assertNotNull(anime.getMemo());
    }

    @Test public void episodeNumberIsFloatAndCopyKeepsMetadata() throws Exception {
        assertEquals(float.class, SEpisode.class.getMethod("getEpisode_number").getReturnType());
        SEpisode episode = SEpisode.Companion.create();
        episode.setUrl("/episode/1");
        episode.setName("Episode 1");
        episode.setEpisode_number(1.5f);
        episode.setFillermark(true);
        SEpisode copy = SEpisode.Companion.create();
        copy.copyFrom(episode);
        assertEquals(episode.getUrl(), copy.getUrl());
        assertEquals(1.5f, copy.getEpisode_number(), 0.0f);
        assertTrue(copy.getFillermark());
    }

    @Test public void okhttpExportsTheDurationMethodsCurrentBundlesLinkAgainst() throws Exception {
        for (String name : new String[] {"maxAge-LRDsOJo", "maxStale-LRDsOJo", "minFresh-LRDsOJo"}) {
            assertEquals(CacheControl.Builder.class,
                CacheControl.Builder.class.getMethod(name, long.class).getReturnType());
        }
    }

    @Test public void legacyVideoUsesTheThirdArgumentAsTheStreamNotThePage() {
        Video video = new Video("https://site.test/watch/1", "720p",
            "https://cdn.test/episode.m3u8", null, Collections.emptyList(), Collections.emptyList());
        assertEquals("https://cdn.test/episode.m3u8", video.getVideoUrl());
        assertEquals("https://site.test/watch/1", video.getUrl());
        assertEquals("720p", video.getVideoTitle());
        assertEquals("720p", video.getQuality());
    }

    @Test public void modernVideoKeepsItsTitleAndDefaultConstructorMasks() throws Exception {
        Video video = Video.class.getConstructor(String.class, String.class, Integer.class,
            Integer.class, Headers.class, boolean.class, List.class, List.class, List.class,
            List.class, List.class, List.class, String.class, boolean.class,
            int.class, DefaultConstructorMarker.class).newInstance(
                "https://cdn.test/episode.mp4", "1080p", null, null, null, false,
                null, null, null, null, null, null, null, false, 0x3ffc, null);
        assertEquals("1080p", video.getVideoTitle());
        assertEquals("https://cdn.test/episode.mp4", video.getVideoUrl());
        assertNotNull(video.getSubtitleTracks());
        assertNotNull(video.getFfmpegStreamArgs());
    }

    @Test public void hosterOrderAndDefaultsMatchTheExtensionStub() throws Exception {
        Hoster hoster = Hoster.class.getConstructor(String.class, String.class, List.class,
            String.class, boolean.class, int.class, DefaultConstructorMarker.class)
            .newInstance(null, "Mirror", null, "opaque-data", false, 0x15, null);
        assertEquals("", hoster.getHosterUrl());
        assertEquals("Mirror", hoster.getHosterName());
        assertEquals("opaque-data", hoster.getInternalData());
        assertNull(hoster.getVideoList());
        assertFalse(hoster.getLazy());
    }

    @Test public void introOutroMarkersUseTheExactEnumNamesInExtensionDex() {
        assertNotNull(ChapterType.valueOf("Opening"));
        assertNotNull(ChapterType.valueOf("Ending"));
        assertNotNull(ChapterType.valueOf("Recap"));
        assertNotNull(ChapterType.valueOf("MixedOp"));
        assertNotNull(ChapterType.valueOf("Other"));
    }

    @Test public void animeAndEpisodePathsKeepTheSlashExtensionsConcatenate() {
        AnimeUrlFixture source = new AnimeUrlFixture("https://animekai.to");
        SAnime anime = SAnime.Companion.create();
        SEpisode episode = SEpisode.Companion.create();
        source.setUrlWithoutDomain(anime, "https://animekai.to/watch/one?lang=en#episodes");
        source.setUrlWithoutDomain(episode, "https://animekai.to/episode/1?server=2");
        assertEquals("/watch/one?lang=en#episodes", anime.getUrl());
        assertEquals("/episode/1?server=2", episode.getUrl());
        assertEquals(source.getAnimeUrl(anime), source.getBaseUrl() + anime.getUrl());
        assertEquals(source.getEpisodeUrl(episode), source.getBaseUrl() + episode.getUrl());
    }

    @Test public void animeUrlsRoundTripWithTrailingBaseSlashAndExistingPaths() {
        AnimeUrlFixture source = new AnimeUrlFixture("https://animexin.dev/");
        SEpisode episode = SEpisode.Companion.create();
        for (String value : new String[] {"https://animexin.dev/episode/1", "/episode/1"}) {
            source.setUrlWithoutDomain(episode, value);
            assertEquals("/episode/1", episode.getUrl());
            assertEquals("https://animexin.dev/episode/1", source.getEpisodeUrl(episode));
        }
        source.setUrlWithoutDomain(episode, "https://cdn.test/episode/1");
        assertEquals("https://cdn.test/episode/1", source.getEpisodeUrl(episode));
    }

    @Test public void mangaAndChapterPathsAlsoKeepTheSlash() {
        MangaUrlFixture source = new MangaUrlFixture();
        SManga manga = SManga.Companion.create();
        SChapter chapter = SChapter.Companion.create();
        source.setUrlWithoutDomain(manga, "https://manga.test/title/one?lang=ar");
        source.setUrlWithoutDomain(chapter, "https://manga.test/chapter/1#page2");
        assertEquals("/title/one?lang=ar", manga.getUrl());
        assertEquals("/chapter/1#page2", chapter.getUrl());
        assertEquals(source.getMangaUrl(manga), source.getBaseUrl() + manga.getUrl());
        assertEquals(source.getChapterUrl(chapter), source.getBaseUrl() + chapter.getUrl());
    }

    private static final class AnimeUrlFixture extends AnimeHttpSource {
        private final String base;
        AnimeUrlFixture(String base) { this.base = base; }
        @Override public String getBaseUrl() { return base; }
        @Override public String getName() { return "URL fixture"; }
        @Override public String getLang() { return "en"; }
    }

    /** No network or Android service is involved in these URL-contract tests. */
    private static final class MangaUrlFixture extends HttpSource {
        @Override public String getBaseUrl() { return "https://manga.test"; }
        @Override public String getName() { return "URL fixture"; }
        @Override public String getLang() { return "en"; }
        @Override public boolean getSupportsLatest() { return true; }
        @Override protected Request popularMangaRequest(int page) { throw new UnsupportedOperationException(); }
        @Override protected MangasPage popularMangaParse(Response response) { throw new UnsupportedOperationException(); }
        @Override protected Request searchMangaRequest(int page, String query, FilterList filters) { throw new UnsupportedOperationException(); }
        @Override protected MangasPage searchMangaParse(Response response) { throw new UnsupportedOperationException(); }
        @Override protected Request latestUpdatesRequest(int page) { throw new UnsupportedOperationException(); }
        @Override protected MangasPage latestUpdatesParse(Response response) { throw new UnsupportedOperationException(); }
        @Override protected SManga mangaDetailsParse(Response response) { throw new UnsupportedOperationException(); }
        @Override protected List<SChapter> chapterListParse(Response response) { throw new UnsupportedOperationException(); }
        @Override protected List<Page> pageListParse(Response response) { throw new UnsupportedOperationException(); }
        @Override protected String imageUrlParse(Response response) { throw new UnsupportedOperationException(); }
    }
}
