package app.best.best_app.ext;

import eu.kanade.tachiyomi.animesource.model.SAnime;
import eu.kanade.tachiyomi.animesource.model.SEpisode;
import eu.kanade.tachiyomi.animesource.model.FetchType;
import okhttp3.CacheControl;
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
}
