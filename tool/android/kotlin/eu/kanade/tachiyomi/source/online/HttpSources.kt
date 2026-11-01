package eu.kanade.tachiyomi.source.online

import eu.kanade.tachiyomi.network.GET
import eu.kanade.tachiyomi.network.NetworkHelper
import eu.kanade.tachiyomi.network.asObservable
import eu.kanade.tachiyomi.network.asObservableSuccess
import eu.kanade.tachiyomi.source.CatalogueSource
import eu.kanade.tachiyomi.source.model.FilterList
import eu.kanade.tachiyomi.source.model.MangasPage
import eu.kanade.tachiyomi.source.model.Page
import eu.kanade.tachiyomi.source.model.SChapter
import eu.kanade.tachiyomi.source.model.SManga
import eu.kanade.tachiyomi.util.asJsoup
import kotlinx.coroutines.suspendCancellableCoroutine
import okhttp3.Headers
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import org.jsoup.Jsoup
import org.jsoup.nodes.Document
import org.jsoup.nodes.Element
import rx.Observable
import rx.Subscriber
import rx.Subscription
import uy.kohesive.injekt.Injekt
import uy.kohesive.injekt.api.get
import java.security.MessageDigest
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * The base class every website extension extends.
 *
 * The stub library declares this class with every body replaced by
 * `throw Exception("Stub!")`; extensions only override the parsing hooks. Best
 * ships the working body: request building, Rx plumbing, the suspend wrappers
 * that current extensions call, and url bookkeeping.
 */
@Suppress("unused", "MemberVisibilityCanBePrivate")
abstract class HttpSource : CatalogueSource {

    /** Network service, injected by the host at start-up. */
    protected val network: NetworkHelper
        get() = Injekt.get()

    /** Base url of the website without the trailing slash, like: http://mysite.com */
    abstract val baseUrl: String

    /**
     * Version id used to generate the source id. If the site completely changes
     * and urls are incompatible, an extension increases this value and the host
     * treats it as a new source.
     */
    open val versionId: Int = 0

    /**
     * Id of the source: the first 64 bits of the MD5 of
     * `sourcename/language/versionId`, with the sign bit cleared. The algorithm
     * matches Mihon's, so a library built elsewhere keeps its ids here.
     */
    override val id: Long by lazy {
        val key = "${name.lowercase()}/$lang/$versionId"
        val bytes = MessageDigest.getInstance("MD5").digest(key.toByteArray())
        var result = 0L
        for (i in 0..7) {
            result = result or ((bytes[i].toLong() and 0xff) shl (8 * (7 - i)))
        }
        result and Long.MAX_VALUE
    }

    /** Headers used for requests. */
    val headers: Headers by lazy { headersBuilder().build() }

    /** Default network client for doing requests. */
    open val client: OkHttpClient
        get() = network.client

    /** Headers builder for requests. Implementations can override for custom headers. */
    protected open fun headersBuilder(): Headers.Builder =
        Headers.Builder().add("User-Agent", network.defaultUserAgent)

    override fun toString(): String = "$name (${lang.uppercase()})"

    // ------------------------------------------------------------------ popular

    override fun fetchPopularManga(page: Int): Observable<MangasPage> {
        return client.newCall(popularMangaRequest(page))
            .asObservableSuccess()
            .map { popularMangaParse(it) }
    }

    protected abstract fun popularMangaRequest(page: Int): Request

    protected abstract fun popularMangaParse(response: Response): MangasPage

    override suspend fun getPopularManga(page: Int): MangasPage = fetchPopularManga(page).awaitOne()

    // ------------------------------------------------------------------- search

    override fun fetchSearchManga(page: Int, query: String, filters: FilterList): Observable<MangasPage> {
        return client.newCall(searchMangaRequest(page, query, filters))
            .asObservableSuccess()
            .map { searchMangaParse(it) }
    }

    protected abstract fun searchMangaRequest(page: Int, query: String, filters: FilterList): Request

    protected abstract fun searchMangaParse(response: Response): MangasPage

    override suspend fun getSearchManga(page: Int, query: String, filters: FilterList): MangasPage =
        fetchSearchManga(page, query, filters).awaitOne()

    // ------------------------------------------------------------------- latest

    override fun fetchLatestUpdates(page: Int): Observable<MangasPage> {
        return client.newCall(latestUpdatesRequest(page))
            .asObservableSuccess()
            .map { latestUpdatesParse(it) }
    }

    protected abstract fun latestUpdatesRequest(page: Int): Request

    protected abstract fun latestUpdatesParse(response: Response): MangasPage

    override suspend fun getLatestUpdates(page: Int): MangasPage = fetchLatestUpdates(page).awaitOne()

    // ------------------------------------------------------------------ details

    override fun fetchMangaDetails(manga: SManga): Observable<SManga> {
        return client.newCall(mangaDetailsRequest(manga))
            .asObservableSuccess()
            .map { mangaDetailsParse(it).apply { initialized = true } }
    }

    open fun mangaDetailsRequest(manga: SManga): Request = GET(getMangaUrl(manga), headers)

    protected abstract fun mangaDetailsParse(response: Response): SManga

    override suspend fun getMangaDetails(manga: SManga): SManga = fetchMangaDetails(manga).awaitOne()

    // ----------------------------------------------------------------- chapters

    override fun fetchChapterList(manga: SManga): Observable<List<SChapter>> {
        return client.newCall(chapterListRequest(manga))
            .asObservableSuccess()
            .map { response ->
                chapterListParse(response).filter { it.name.isNotBlank() || it.url.isNotBlank() }
            }
    }

    protected open fun chapterListRequest(manga: SManga): Request = GET(getMangaUrl(manga), headers)

    protected abstract fun chapterListParse(response: Response): List<SChapter>

    override suspend fun getChapterList(manga: SManga): List<SChapter> = fetchChapterList(manga).awaitOne()

    /** Parses a single chapter page. Used by sources that paginate chapters. */
    protected open fun chapterPageParse(response: Response): SChapter =
        throw UnsupportedOperationException("Not used!")

    // -------------------------------------------------------------------- pages

    override fun fetchPageList(chapter: SChapter): Observable<List<Page>> {
        return client.newCall(pageListRequest(chapter))
            .asObservableSuccess()
            .map { pageListParse(it) }
    }

    protected open fun pageListRequest(chapter: SChapter): Request = GET(getChapterUrl(chapter), headers)

    protected abstract fun pageListParse(response: Response): List<Page>

    override suspend fun getPageList(chapter: SChapter): List<Page> = fetchPageList(chapter).awaitOne()

    // -------------------------------------------------------------------- image

    open fun fetchImageUrl(page: Page): Observable<String> {
        return client.newCall(imageUrlRequest(page))
            .asObservableSuccess()
            .map { imageUrlParse(it) }
            .onErrorReturn { "" }
    }

    protected open fun imageUrlRequest(page: Page): Request = GET(page.url, headers)

    protected abstract fun imageUrlParse(response: Response): String

    fun fetchImage(page: Page): Observable<Response> {
        return client.newCall(imageRequest(page)).asObservable()
    }

    protected open fun imageRequest(page: Page): Request {
        val url = page.imageUrl?.takeIf { it.isNotBlank() } ?: page.url
        return GET(url, headers)
    }

    open suspend fun getImageUrl(page: Page): String = fetchImageUrl(page).awaitOne()

    protected open suspend fun getImage(page: Page): Response = fetchImage(page).awaitOne()

    // --------------------------------------------------------------------- urls

    fun SChapter.setUrlWithoutDomain(url: String) {
        this.url = getUrlWithoutDomain(url)
    }

    fun SManga.setUrlWithoutDomain(url: String) {
        this.url = getUrlWithoutDomain(url)
    }

    private fun getUrlWithoutDomain(orig: String): String {
        val base = baseUrl.trimEnd('/')
        return when {
            orig == base -> ""
            orig.startsWith("$base/") -> orig.substring(base.length + 1)
            else -> orig
        }
    }

    /** Absolute url of a manga, from either a full url or a domain-less path. */
    open fun getMangaUrl(manga: SManga): String = toAbsoluteUrl(manga.url)

    /** Absolute url of a chapter, from either a full url or a domain-less path. */
    open fun getChapterUrl(chapter: SChapter): String = toAbsoluteUrl(chapter.url)

    /** Public alias the host uses to resolve a relative cover url. */
    fun resolveUrl(path: String?): String? =
        path?.takeIf { it.isNotBlank() }?.let { toAbsoluteUrl(it) }

    protected fun toAbsoluteUrl(path: String): String {
        if (path.startsWith("http://") || path.startsWith("https://")) return path
        val base = baseUrl.trimEnd('/')
        return if (path.startsWith("/")) "$base$path" else "$base/$path"
    }

    /**
     * Called before inserting a new chapter into the database. Extensions use it
     * to normalise the number or title.
     */
    open fun prepareNewChapter(chapter: SChapter, manga: SManga) {
    }

    override fun getFilterList(): FilterList = FilterList()

    // -------------------------------------------------- Komikku related titles

    override suspend fun fetchRelatedMangaList(manga: SManga): List<SManga> =
        throw UnsupportedOperationException("Unsupported!")

    protected open fun relatedMangaListRequest(manga: SManga): Request = GET(getMangaUrl(manga), headers)

    protected open fun relatedMangaListParse(response: Response): List<SManga> =
        throw UnsupportedOperationException("Unsupported!")
}

/**
 * Bridges a one-shot Rx stream to a suspend call. Extensions call the suspend
 * `get*` methods; the bodies above are Rx, so this is where the two meet.
 */
internal suspend fun <T> Observable<T>.awaitOne(): T = suspendCancellableCoroutine { continuation ->
    val subscription: Subscription = subscribe(
        object : Subscriber<T>() {
            override fun onNext(value: T) {
                if (continuation.isActive) continuation.resume(value)
            }

            override fun onError(error: Throwable) {
                if (continuation.isActive) continuation.resumeWithException(error)
            }

            override fun onCompleted() {
                if (continuation.isActive) {
                    continuation.resumeWithException(IllegalStateException("The source returned nothing."))
                }
            }
        },
    )
    continuation.invokeOnCancellation { subscription.unsubscribe() }
}

/**
 * A source that parses HTML with Jsoup selectors.
 *
 * Extensions only supply selectors and element mappers; everything else — the
 * request, the document, the next-page check — is here.
 */
@Suppress("unused", "MemberVisibilityCanBePrivate")
abstract class ParsedHttpSource : HttpSource() {

    protected fun responseBody(response: Response): String = response.body?.string().orEmpty()

    protected fun document(response: Response): Document = Jsoup.parse(responseBody(response), baseUrl)

    // ------------------------------------------------------------------ popular

    protected abstract fun popularMangaSelector(): String

    protected abstract fun popularMangaFromElement(element: Element): SManga

    protected abstract fun popularMangaNextPageSelector(): String?

    override fun popularMangaRequest(page: Int): Request = GET("$baseUrl/popular?page=$page", headers)

    override fun popularMangaParse(response: Response): MangasPage {
        val document = document(response)
        val mangas = document.select(popularMangaSelector()).map { popularMangaFromElement(it) }
        val hasNextPage = popularMangaNextPageSelector()?.let { document.selectFirst(it) != null } ?: false
        return MangasPage(mangas, hasNextPage)
    }

    // ------------------------------------------------------------------- latest

    protected abstract fun latestUpdatesSelector(): String

    protected abstract fun latestUpdatesFromElement(element: Element): SManga

    protected abstract fun latestUpdatesNextPageSelector(): String?

    override fun latestUpdatesRequest(page: Int): Request = GET("$baseUrl/latest?page=$page", headers)

    override fun latestUpdatesParse(response: Response): MangasPage {
        val document = document(response)
        val mangas = document.select(latestUpdatesSelector()).map { latestUpdatesFromElement(it) }
        val hasNextPage = latestUpdatesNextPageSelector()?.let { document.selectFirst(it) != null } ?: false
        return MangasPage(mangas, hasNextPage)
    }

    // ------------------------------------------------------------------- search

    protected abstract fun searchMangaSelector(): String

    protected abstract fun searchMangaFromElement(element: Element): SManga

    protected abstract fun searchMangaNextPageSelector(): String?

    override fun searchMangaRequest(page: Int, query: String, filters: FilterList): Request =
        GET("$baseUrl/search?q=${java.net.URLEncoder.encode(query, "UTF-8")}&page=$page", headers)

    override fun searchMangaParse(response: Response): MangasPage {
        val document = document(response)
        val mangas = document.select(searchMangaSelector()).map { searchMangaFromElement(it) }
        val hasNextPage = searchMangaNextPageSelector()?.let { document.selectFirst(it) != null } ?: false
        return MangasPage(mangas, hasNextPage)
    }

    // ------------------------------------------------------------------ details

    override fun mangaDetailsParse(response: Response): SManga = mangaDetailsParse(document(response))

    protected abstract fun mangaDetailsParse(document: Document): SManga

    // ----------------------------------------------------------------- chapters

    protected abstract fun chapterListSelector(): String

    protected abstract fun chapterFromElement(element: Element): SChapter

    override fun chapterListParse(response: Response): List<SChapter> {
        val document = document(response)
        return document.select(chapterListSelector()).map { chapterFromElement(it) }
    }

    // -------------------------------------------------------------------- pages

    override fun pageListParse(response: Response): List<Page> = pageListParse(document(response))

    protected abstract fun pageListParse(document: Document): List<Page>

    override fun imageUrlParse(response: Response): String = imageUrlParse(document(response))

    protected abstract fun imageUrlParse(document: Document): String
}

/** Jsoup convenience used by several extensions and by the host itself. */
internal fun Response.asDocument(): Document = asJsoup()
