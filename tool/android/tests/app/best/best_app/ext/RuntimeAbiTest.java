package app.best.best_app.ext;

import eu.kanade.tachiyomi.animesource.model.SAnime;
import eu.kanade.tachiyomi.animesource.model.SEpisode;
import eu.kanade.tachiyomi.animesource.model.FetchType;
import eu.kanade.tachiyomi.animesource.model.Video;
import eu.kanade.tachiyomi.animesource.model.Hoster;
import eu.kanade.tachiyomi.animesource.model.AnimeFilter;
import eu.kanade.tachiyomi.animesource.model.ChapterType;
import eu.kanade.tachiyomi.animesource.online.AnimeHttpSource;
import eu.kanade.tachiyomi.source.online.HttpSource;
import eu.kanade.tachiyomi.source.model.FilterList;
import eu.kanade.tachiyomi.source.model.MangasPage;
import eu.kanade.tachiyomi.source.model.Page;
import eu.kanade.tachiyomi.source.model.SChapter;
import eu.kanade.tachiyomi.source.model.SManga;
import eu.kanade.tachiyomi.source.model.SMangaUpdate;
import kotlin.coroutines.Continuation;
import kotlin.jvm.internal.DefaultConstructorMarker;
import okhttp3.CacheControl;
import okhttp3.Headers;
import okhttp3.Request;
import okhttp3.Response;
import okhttp3.Interceptor;
import okhttp3.OkHttpClient;
import okhttp3.Protocol;
import okhttp3.ResponseBody;
import java.io.IOException;
import java.util.Collections;
import java.util.List;
import java.util.Set;
import org.junit.Test;
import static org.junit.Assert.*;

/** Pin the JVM contract that real extension dex uses, not merely Kotlin syntax. */
public class RuntimeAbiTest {
    private static final String PACKAGE = "eu.kanade.tachiyomi.extension.all.test";

    private static OkHttpClient extensionClient() throws Exception {
        return (OkHttpClient) Class.forName("eu.kanade.tachiyomi.network.NetworkKt")
            .getMethod("createExtensionHttpClient").invoke(null);
    }

    private static Response response(Interceptor.Chain chain, int code) {
        return new Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1)
            .code(code).message("fixture").body(ResponseBody.create("fixture", null)).build();
    }

    @Test public void defaultClientMeetsTheCurrentKeiyoushiInterceptorContract() throws Exception {
        List<Interceptor> interceptors = extensionClient().interceptors();
        assertEquals("UncaughtExceptionInterceptor", interceptors.get(0).getClass().getSimpleName());
        for (String required : new String[] {"UserAgentInterceptor", "CloudflareInterceptor"}) {
            assertTrue(required, interceptors.stream().anyMatch(i -> i.getClass().getSimpleName().equals(required)));
        }
    }

    @Test public void userAgentIsSuppliedWithoutOverwritingSourceHeaders() throws Exception {
        OkHttpClient client = extensionClient().newBuilder().addInterceptor(chain -> response(chain, 200)).build();
        Request request = new Request.Builder().url("https://fixture.test/").build();
        try (Response result = client.newCall(request).execute()) {
            assertTrue(result.request().header("User-Agent").contains("Mozilla"));
        }
        try (Response result = client.newCall(request.newBuilder().header("User-Agent", "source-specific").build()).execute()) {
            assertEquals("source-specific", result.request().header("User-Agent"));
        }
    }

    @Test public void uncaughtInterceptorExceptionsBecomeNonFatalIoErrors() throws Exception {
        IllegalStateException original = new IllegalStateException("source parser failed");
        OkHttpClient client = extensionClient().newBuilder().addInterceptor(chain -> { throw original; }).build();
        try {
            client.newCall(new Request.Builder().url("https://fixture.test/").build()).execute();
            fail("A source error must not escape OkHttp as a fatal runtime exception.");
        } catch (IOException error) {
            assertSame(original, error.getCause());
        }
    }

    @Test public void networkIoExceptionsKeepTheirIdentity() throws Exception {
        IOException original = new IOException("offline");
        OkHttpClient client = extensionClient().newBuilder().addInterceptor(chain -> { throw original; }).build();
        try {
            client.newCall(new Request.Builder().url("https://fixture.test/").build()).execute();
            fail("Offline must remain an error.");
        } catch (IOException error) {
            assertSame(original, error);
        }
    }

    @Test public void browserChallengesAreReportedNotFakedAsSuccessfulResponses() throws Exception {
        OkHttpClient client = extensionClient().newBuilder().addInterceptor(chain ->
            response(chain, 403).newBuilder().header("cf-mitigated", "challenge").build()).build();
        try {
            client.newCall(new Request.Builder().url("https://fixture.test/").build()).execute();
            fail("Best does not claim to solve browser verification.");
        } catch (IOException error) {
            assertTrue(error.getMessage().contains("browser verification"));
        }
        OkHttpClient ordinary = extensionClient().newBuilder().addInterceptor(chain -> response(chain, 403)).build();
        try (Response result = ordinary.newCall(new Request.Builder().url("https://fixture.test/").build()).execute()) {
            assertEquals(403, result.code());
        }
    }

    @Test public void modernMangaUpdateModelAndSuspendContractAreAvailable() throws Exception {
        Class<?> update = Class.forName("eu.kanade.tachiyomi.source.model.SMangaUpdate");
        SManga manga = SManga.Companion.create();
        List<SChapter> chapters = Collections.singletonList(SChapter.Companion.create());
        Object value = update.getConstructor(SManga.class, List.class).newInstance(manga, chapters);
        assertSame(manga, update.getMethod("getManga").invoke(value));
        assertEquals(chapters, update.getMethod("getChapters").invoke(value));
        assertEquals(Object.class, Class.forName("eu.kanade.tachiyomi.source.Source")
            .getMethod("getMangaUpdate", SManga.class, List.class, boolean.class, boolean.class,
                kotlin.coroutines.Continuation.class).getReturnType());
    }

    @Test public void imageRequestsHonorTheExtensionsOwnUrlAndHeaders() {
        MangaUrlFixture source = new MangaUrlFixture();
        Page page = new Page(0, "https://page.test/metadata", "/relative-image.jpg", null);
        Request request = source.pageImageRequest(page);
        assertEquals("https://cdn.test/resolved-image.jpg", request.url().toString());
        assertEquals("source-header", request.header("Referer"));
    }

    @Test public void legacyMangaUpdatesForwardOnlyTheRequestedFetches() {
        LegacyMangaFixture source = new LegacyMangaFixture();
        SManga manga = SManga.Companion.create();
        List<SChapter> existing = Collections.singletonList(SChapter.Companion.create());
        SMangaUpdate result = (SMangaUpdate) source.getMangaUpdate(manga, existing, false, false, null);
        assertSame(manga, result.getManga());
        assertSame(existing, result.getChapters());
        assertEquals(0, source.detailsCalls);
        assertEquals(0, source.chapterCalls);

        result = (SMangaUpdate) source.getMangaUpdate(manga, existing, true, false, null);
        assertSame(source.details, result.getManga());
        assertSame(existing, result.getChapters());
        assertEquals(1, source.detailsCalls);
        assertEquals(0, source.chapterCalls);

        result = (SMangaUpdate) source.getMangaUpdate(manga, existing, false, true, null);
        assertSame(manga, result.getManga());
        assertSame(source.chapters, result.getChapters());
        assertEquals(1, source.detailsCalls);
        assertEquals(1, source.chapterCalls);
    }

    @Test public void compressionModulesRequiredByCurrentKeiyoushiSourcesArePackaged() throws Exception {
        // KeiSource builds CompressionInterceptor(Gzip, Deflate, Brotli, Zstd)
        // and rejects a default client that already contains BrotliInterceptor.
        Class.forName("okhttp3.brotli.Brotli");
        Class<?> brotli = Class.forName("okhttp3.brotli.BrotliInterceptor");
        Class.forName("okhttp3.zstd.Zstd");
        Class.forName("okhttp3.CompressionInterceptor");
        Class.forName("okhttp3.Gzip");
        assertTrue(Interceptor.class.isAssignableFrom(brotli));
        assertTrue(extensionClient().interceptors().stream()
            .noneMatch(i -> i.getClass().getSimpleName().equals("BrotliInterceptor")));
    }

    @Test public void extensionSettingsKeepThePreferenceTypesSourcesBuild() throws Exception {
        // Mangalek and most Madara bundles add a ListPreference for
        // preferred_mirror. A missing preference runtime would silently remove
        // the only way to move a blocked source to a working domain.
        Class<?> list = Class.forName("androidx.preference.ListPreference");
        assertNotNull(list.getMethod("setEntryValues", CharSequence[].class));
        assertTrue(androidx.preference.TwoStatePreference.class.isAssignableFrom(
            Class.forName("androidx.preference.SwitchPreferenceCompat")));
        assertTrue(androidx.preference.Preference.class.isAssignableFrom(
            Class.forName("androidx.preference.PreferenceGroup")));
        Class<?> host = Class.forName("app.best.best_app.ext.SourcePreferences");
        assertNotNull(host.getMethod("describe", android.content.Context.class, long.class, Object.class));
        assertNotNull(host.getMethod("apply", android.content.Context.class, long.class,
            Object.class, String.class, String.class));
    }

    @Test public void httpExceptionKeepsTheMihonConstructorAndParent() throws Exception {
        Class<?> type = Class.forName("eu.kanade.tachiyomi.network.HttpException");
        assertTrue(IllegalStateException.class.isAssignableFrom(type));
        Throwable error = (Throwable) type.getConstructor(int.class).newInstance(404);
        assertEquals(404, type.getMethod("getCode").invoke(error));
        assertEquals("HTTP error 404", error.getMessage());
    }

    @Test public void animeSortAndTriStateFiltersMatchTheAniyomiContract() throws Exception {
        Class<?> sort = Class.forName("eu.kanade.tachiyomi.animesource.model.AnimeFilter$Sort");
        Class<?> selection = Class.forName("eu.kanade.tachiyomi.animesource.model.AnimeFilter$Sort$Selection");
        Object chosen = selection.getConstructor(int.class, boolean.class).newInstance(2, true);
        assertEquals(2, selection.getMethod("getIndex").invoke(chosen));
        assertEquals(true, selection.getMethod("getAscending").invoke(chosen));
        assertTrue(sort.isAssignableFrom(AnimeSortFixture.class));
        assertNotNull(sort.getMethod("getValues"));

        Class<?> triState = Class.forName("eu.kanade.tachiyomi.animesource.model.AnimeFilter$TriState");
        assertEquals(0, triState.getField("STATE_IGNORE").get(null));
        assertEquals(1, triState.getField("STATE_INCLUDE").get(null));
        assertEquals(2, triState.getField("STATE_EXCLUDE").get(null));
        assertNotNull(triState.getMethod("isIgnored"));
    }

    @Test public void protobufWebkitAndQuickJsArePackagedForExtensionsThatLinkThem() throws Exception {
        ClassLoader loader = RuntimeAbiTest.class.getClassLoader();
        Class.forName("kotlinx.serialization.protobuf.ProtoBuf");
        Class.forName("androidx.webkit.WebViewClientCompat");
        Class.forName("org.chromium.support_lib_boundary.WebViewProviderFactoryBoundaryInterface");
        // QuickJs loads its native library in a static initializer, so only the
        // class's presence is asserted here; the device smoke run exercises it.
        Class.forName("app.cash.quickjs.QuickJs", false, loader);
    }

    @Test public void jsonOkioExportsTheClassAnimeKaiLinksAgainst() throws Exception {
        Class<?> streams = Class.forName("kotlinx.serialization.json.okio.OkioStreamsKt");
        assertTrue(java.util.Arrays.stream(streams.getMethods())
            .anyMatch(method -> method.getName().equals("decodeFromBufferedSource")));
    }

    @Test public void verifiedSamePublisherUpdateIsAccepted() {
        ExtensionInstallPolicy.INSTANCE.validateIdentity(PACKAGE, 12L, PACKAGE, 12L,
            Set.of("publisher"), 11L, Set.of("publisher"));
    }

    @Test(expected = IllegalArgumentException.class) public void changedPackageIsRejectedBeforeReplacement() {
        ExtensionInstallPolicy.INSTANCE.validateIdentity(PACKAGE, 12L, PACKAGE + "wrong", 12L,
            Set.of("publisher"), 11L, Set.of("publisher"));
    }

    @Test(expected = IllegalArgumentException.class) public void changedPublisherSignatureIsRejected() {
        ExtensionInstallPolicy.INSTANCE.validateIdentity(PACKAGE, 12L, PACKAGE, 12L,
            Set.of("intruder"), 11L, Set.of("publisher"));
    }

    @Test(expected = IllegalArgumentException.class) public void unsignedArchiveIsRejected() {
        ExtensionInstallPolicy.INSTANCE.validateIdentity(PACKAGE, 12L, PACKAGE, 12L,
            Set.of(), null, null);
    }

    @Test(expected = IllegalArgumentException.class) public void unexpectedVersionIsRejected() {
        ExtensionInstallPolicy.INSTANCE.validateIdentity(PACKAGE, 12L, PACKAGE, 13L,
            Set.of("publisher"), null, null);
    }

    @Test(expected = IllegalArgumentException.class) public void extensionDowngradeIsRejected() {
        ExtensionInstallPolicy.INSTANCE.validateIdentity(PACKAGE, 10L, PACKAGE, 10L,
            Set.of("publisher"), 11L, Set.of("publisher"));
    }

    @Test public void downloadsRequireTrustedHttpsPublisherAndRedirectHosts() {
        assertTrue(ExtensionInstallPolicy.INSTANCE.allowDownload(
            "https://github.com/keiyoushi/extensions/releases/download/tag/test.apk", false));
        assertTrue(ExtensionInstallPolicy.INSTANCE.allowDownload(
            "https://raw.githubusercontent.com/yuzono/anime-repo/repo/apk/test.apk", false));
        assertTrue(ExtensionInstallPolicy.INSTANCE.allowDownload("https://release-assets.githubusercontent.com/test.apk", true));
        assertFalse(ExtensionInstallPolicy.INSTANCE.allowDownload("https://release-assets.githubusercontent.com/test.apk", false));
        assertFalse(ExtensionInstallPolicy.INSTANCE.allowDownload("http://github.com/keiyoushi/extensions/releases/download/tag/test.apk", false));
        assertFalse(ExtensionInstallPolicy.INSTANCE.allowDownload("https://evil.test/test.apk", true));
        assertFalse(ExtensionInstallPolicy.INSTANCE.allowDownload("https://github.com/attacker/extensions/releases/download/tag/test.apk", false));
        assertFalse(ExtensionInstallPolicy.INSTANCE.allowDownload("https://raw.githubusercontent.com/yuzono/anime-repo/repo/apk/../../other/test.apk", false));
    }
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
    private static class MangaUrlFixture extends HttpSource {
        @Override public String getBaseUrl() { return "https://manga.test"; }
        @Override public String getName() { return "URL fixture"; }
        @Override public String getLang() { return "en"; }
        @Override public boolean getSupportsLatest() { return true; }
        @Override protected Request imageRequest(Page page) {
            return new Request.Builder().url("https://cdn.test/resolved-image.jpg")
                .header("Referer", "source-header").build();
        }
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

    private static final class AnimeSortFixture extends AnimeFilter.Sort {
        AnimeSortFixture() {
            super("Sort", new String[] {"Popular", "Latest"}, (AnimeFilter.Sort.Selection) null);
        }
    }

    private static final class LegacyMangaFixture extends MangaUrlFixture {
        final SManga details = SManga.Companion.create();
        final List<SChapter> chapters = Collections.singletonList(SChapter.Companion.create());
        int detailsCalls;
        int chapterCalls;

        @Override public Object getMangaDetails(SManga manga, Continuation<? super SManga> continuation) {
            detailsCalls++;
            return details;
        }

        @Override public Object getChapterList(SManga manga, Continuation<? super List<? extends SChapter>> continuation) {
            chapterCalls++;
            return chapters;
        }
    }
}
