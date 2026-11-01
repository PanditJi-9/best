package eu.kanade.tachiyomi.animesource

import androidx.preference.PreferenceScreen
import eu.kanade.tachiyomi.animesource.model.AnimeFilterList
import eu.kanade.tachiyomi.animesource.model.AnimesPage
import eu.kanade.tachiyomi.animesource.model.Hoster
import eu.kanade.tachiyomi.animesource.model.SAnime
import eu.kanade.tachiyomi.animesource.model.SEpisode
import eu.kanade.tachiyomi.animesource.model.Video

/**
 * The contract an anime extension implements.
 *
 * Every method has a body so a host never meets an `AbstractMethodError`:
 * Aniyomi extensions in the wild target different API versions, and one that
 * does not override `getHosterList` must still load.
 */
@Suppress("unused")
interface AnimeSource {
    val id: Long
    val name: String
    val lang: String
    val supportsLatest: Boolean

    fun getFilterList(): AnimeFilterList = AnimeFilterList()

    suspend fun getPopularAnime(page: Int): AnimesPage =
        AnimesPage(emptyList(), false)

    suspend fun getSearchAnime(page: Int, query: String, filters: AnimeFilterList): AnimesPage =
        AnimesPage(emptyList(), false)

    suspend fun getLatestUpdates(page: Int): AnimesPage = getPopularAnime(page)

    suspend fun getAnimeDetails(anime: SAnime): SAnime = anime

    suspend fun getEpisodeList(anime: SAnime): List<SEpisode> = emptyList()

    suspend fun getVideoList(episode: SEpisode): List<Video> = emptyList()

    /** Newer sources hand back mirrors first and resolve streams per mirror. */
    suspend fun getHosterList(episode: SEpisode): List<Hoster> = emptyList()

    suspend fun getVideoList(hoster: Hoster): List<Video> = hoster.videoList
}

/** A source that can be browsed: popular, latest and search. */
interface AnimeCatalogueSource : AnimeSource

/** A bundle that exposes several sources from one APK. */
interface AnimeSourceFactory {
    fun createSources(): List<AnimeSource>
}

/** A source with a settings screen, filled in with `androidx.preference`. */
interface ConfigurableAnimeSource : AnimeSource {
    fun setupPreferenceScreen(screen: PreferenceScreen)
}
