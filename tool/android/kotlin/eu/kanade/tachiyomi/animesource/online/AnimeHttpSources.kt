package eu.kanade.tachiyomi.animesource.online

import eu.kanade.tachiyomi.animesource.AnimeCatalogueSource
import eu.kanade.tachiyomi.animesource.model.AnimeFilterList
import eu.kanade.tachiyomi.animesource.model.AnimesPage
import eu.kanade.tachiyomi.animesource.model.Hoster
import eu.kanade.tachiyomi.animesource.model.SAnime
import eu.kanade.tachiyomi.animesource.model.SEpisode
import eu.kanade.tachiyomi.animesource.model.Video
import eu.kanade.tachiyomi.network.GET
import eu.kanade.tachiyomi.network.NetworkHelper
import eu.kanade.tachiyomi.network.awaitSuccess
import eu.kanade.tachiyomi.util.asJsoup
import okhttp3.Headers
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import org.jsoup.nodes.Document
import org.jsoup.nodes.Element
import uy.kohesive.injekt.Injekt
import uy.kohesive.injekt.api.get
import java.net.URLEncoder
import java.security.MessageDigest

/**
 * The base class every anime extension extends.
 *
 * The stub library ships every body as `throw Exception("Stub!")`; extensions
 * only override the parsing hooks. Best ships working bodies so a source
 * behaves exactly as it does under Aniyomi: same catalogue, same episodes, same
 * streams. Nothing is scraped by Best itself.
 *
 * Every hook is `open` with a body, never `abstract`: extensions in the wild
 * target different API versions and one that does not implement a newer hook
 * must still load.
 */
@Suppress("unused", "MemberVisibilityCanBePrivate")
abstract class AnimeHttpSource : AnimeCatalogueSource {

    protected val network: NetworkHelper
        get() = Injekt.get()

    open val baseUrl: String = ""

    /** Bumping this makes the host treat the source as new. */
    open val versionId: Int = 0

    override val id: Long by lazy {
        val key = "${name.lowercase()}/$lang/$versionId"
        val bytes = MessageDigest.getInstance("MD5").digest(key.toByteArray())
        var result = 0L
        for (i in 0..7) {
            result = result or ((bytes[i].toLong() and 0xff) shl (8 * (7 - i)))
        }
        result and Long.MAX_VALUE
    }

    override val supportsLatest: Boolean get() = true

    val headers: Headers by lazy { headersBuilder().build() }

    open val client: OkHttpClient
        get() = network.client

    protected open fun headersBuilder(): Headers.Builder =
        Headers.Builder().add("User-Agent", network.defaultUserAgent)

    override fun toString(): String = "$name (${lang.uppercase()})"

    // ------------------------------------------------------------------ popular

    override suspend fun getPopularAnime(page: Int): AnimesPage =
        popularAnimeParse(client.newCall(popularAnimeRequest(page)).awaitSuccess())

    protected open fun popularAnimeRequest(page: Int): Request =
        GET("$baseUrl/popular?page=$page", headers)

    protected open fun popularAnimeParse(response: Response): AnimesPage =
        throw UnsupportedOperationException("$name does not implement popularAnimeParse.")

    // ------------------------------------------------------------------- search

    override suspend fun getSearchAnime(page: Int, query: String, filters: AnimeFilterList): AnimesPage =
        searchAnimeParse(client.newCall(searchAnimeRequest(page, query, filters)).awaitSuccess())

    protected open fun searchAnimeRequest(page: Int, query: String, filters: AnimeFilterList): Request =
        GET("$baseUrl/search?q=${URLEncoder.encode(query, "UTF-8")}&page=$page", headers)

    protected open fun searchAnimeParse(response: Response): AnimesPage =
        throw UnsupportedOperationException("$name does not implement searchAnimeParse.")

    // ------------------------------------------------------------------- latest

    override suspend fun getLatestUpdates(page: Int): AnimesPage =
        latestUpdatesParse(client.newCall(latestUpdatesRequest(page)).awaitSuccess())

    protected open fun latestUpdatesRequest(page: Int): Request =
        GET("$baseUrl/latest?page=$page", headers)

    protected open fun latestUpdatesParse(response: Response): AnimesPage = popularAnimeParse(response)

    // ------------------------------------------------------------------ details

    override suspend fun getAnimeDetails(anime: SAnime): SAnime =
        animeDetailsParse(client.newCall(animeDetailsRequest(anime)).awaitSuccess())
            .apply { initialized = true }

    protected open fun animeDetailsRequest(anime: SAnime): Request = GET(getAnimeUrl(anime), headers)

    protected open fun animeDetailsParse(response: Response): SAnime =
        throw UnsupportedOperationException("$name does not implement animeDetailsParse.")

    // ----------------------------------------------------------------- episodes

    override suspend fun getEpisodeList(anime: SAnime): List<SEpisode> =
        episodeListParse(client.newCall(episodeListRequest(anime)).awaitSuccess())

    protected open fun episodeListRequest(anime: SAnime): Request = GET(getAnimeUrl(anime), headers)

    protected open fun episodeListParse(response: Response): List<SEpisode> =
        throw UnsupportedOperationException("$name does not implement episodeListParse.")

    // ------------------------------------------------------------------- videos

    override suspend fun getVideoList(episode: SEpisode): List<Video> =
        videoListParse(client.newCall(videoListRequest(episode)).awaitSuccess())

    protected open fun videoListRequest(episode: SEpisode): Request = GET(getEpisodeUrl(episode), headers)

    protected open fun videoListParse(response: Response): List<Video> =
        throw UnsupportedOperationException("$name does not implement videoListParse.")

    // ------------------------------------------------------------------ hosters

    override suspend fun getHosterList(episode: SEpisode): List<Hoster> =
        hosterListParse(client.newCall(hosterListRequest(episode)).awaitSuccess())

    protected open fun hosterListRequest(episode: SEpisode): Request = GET(getEpisodeUrl(episode), headers)

    protected open fun hosterListParse(response: Response): List<Hoster> = emptyList()

    override suspend fun getVideoList(hoster: Hoster): List<Video> = hoster.videoList

    /** Sources that list several seasons call this before the episode list. */
    protected open fun seasonListParse(response: Response): List<SAnime> = emptyList()

    /** Lets a source reorder the streams it found, best first. */
    protected open fun sortVideos(videos: List<Video>): List<Video> = videos

    // --------------------------------------------------------------------- urls

    fun SAnime.setUrlWithoutDomain(url: String) {
        this.url = toRelative(url)
    }

    fun SEpisode.setUrlWithoutDomain(url: String) {
        this.url = toRelative(url)
    }

    open fun getAnimeUrl(anime: SAnime): String = toAbsolute(anime.url)

    open fun getEpisodeUrl(episode: SEpisode): String = toAbsolute(episode.url)

    /** Public alias the host uses to resolve a relative cover url. */
    fun resolveUrl(path: String?): String? =
        path?.takeIf { it.isNotBlank() }?.let { toAbsolute(it) }

    protected fun toAbsolute(path: String): String {
        if (path.startsWith("http://") || path.startsWith("https://")) return path
        val base = baseUrl.trimEnd('/')
        return if (path.startsWith("/")) "$base$path" else "$base/$path"
    }

    private fun toRelative(orig: String): String {
        val base = baseUrl.trimEnd('/')
        return when {
            orig == base -> ""
            orig.startsWith("$base/") -> orig.substring(base.length + 1)
            else -> orig
        }
    }
}

/**
 * A source that parses HTML with Jsoup selectors.
 *
 * Hooks are `protected` because the real API declares them that way: an
 * extension that narrows visibility would fail verification against a public
 * base method.
 */
@Suppress("unused", "MemberVisibilityCanBePrivate")
abstract class ParsedAnimeHttpSource : AnimeHttpSource() {

    protected fun document(response: Response): Document = response.asJsoup()

    // ------------------------------------------------------------------ popular

    protected open fun popularAnimeSelector(): String =
        throw UnsupportedOperationException("$name does not implement popularAnimeSelector.")

    protected open fun popularAnimeFromElement(element: Element): SAnime =
        throw UnsupportedOperationException("$name does not implement popularAnimeFromElement.")

    protected open fun popularAnimeNextPageSelector(): String? = null

    override fun popularAnimeParse(response: Response): AnimesPage {
        val doc = document(response)
        val animes = doc.select(popularAnimeSelector()).map { popularAnimeFromElement(it) }
        val hasNextPage = popularAnimeNextPageSelector()?.let { doc.selectFirst(it) != null } ?: false
        return AnimesPage(animes, hasNextPage)
    }

    // ------------------------------------------------------------------- latest

    protected open fun latestUpdatesSelector(): String = popularAnimeSelector()

    protected open fun latestUpdatesFromElement(element: Element): SAnime = popularAnimeFromElement(element)

    protected open fun latestUpdatesNextPageSelector(): String? = popularAnimeNextPageSelector()

    override fun latestUpdatesParse(response: Response): AnimesPage {
        val doc = document(response)
        val animes = doc.select(latestUpdatesSelector()).map { latestUpdatesFromElement(it) }
        val hasNextPage = latestUpdatesNextPageSelector()?.let { doc.selectFirst(it) != null } ?: false
        return AnimesPage(animes, hasNextPage)
    }

    // ------------------------------------------------------------------- search

    protected open fun searchAnimeSelector(): String = popularAnimeSelector()

    protected open fun searchAnimeFromElement(element: Element): SAnime = popularAnimeFromElement(element)

    protected open fun searchAnimeNextPageSelector(): String? = popularAnimeNextPageSelector()

    override fun searchAnimeParse(response: Response): AnimesPage {
        val doc = document(response)
        val animes = doc.select(searchAnimeSelector()).map { searchAnimeFromElement(it) }
        val hasNextPage = searchAnimeNextPageSelector()?.let { doc.selectFirst(it) != null } ?: false
        return AnimesPage(animes, hasNextPage)
    }

    // ------------------------------------------------------------------ details

    override fun animeDetailsParse(response: Response): SAnime = animeDetailsParse(document(response))

    protected open fun animeDetailsParse(document: Document): SAnime =
        throw UnsupportedOperationException("$name does not implement animeDetailsParse.")

    // ----------------------------------------------------------------- episodes

    protected open fun episodeListSelector(): String =
        throw UnsupportedOperationException("$name does not implement episodeListSelector.")

    protected open fun episodeFromElement(element: Element): SEpisode =
        throw UnsupportedOperationException("$name does not implement episodeFromElement.")

    override fun episodeListParse(response: Response): List<SEpisode> =
        document(response).select(episodeListSelector()).map { episodeFromElement(it) }

    // ------------------------------------------------------------------- videos

    protected open fun videoListSelector(): String =
        throw UnsupportedOperationException("$name does not implement videoListSelector.")

    protected open fun videoFromElement(element: Element): Video =
        throw UnsupportedOperationException("$name does not implement videoFromElement.")

    protected open fun videoFromObject(obj: Any?): Video =
        throw UnsupportedOperationException("$name does not implement videoFromObject.")

    override fun videoListParse(response: Response): List<Video> =
        document(response).select(videoListSelector()).map { videoFromElement(it) }
}
