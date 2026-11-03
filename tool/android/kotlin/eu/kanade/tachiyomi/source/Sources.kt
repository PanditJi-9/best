package eu.kanade.tachiyomi.source

import androidx.preference.PreferenceScreen
import eu.kanade.tachiyomi.source.model.FilterList
import eu.kanade.tachiyomi.source.model.MangasPage
import eu.kanade.tachiyomi.source.model.Page
import eu.kanade.tachiyomi.source.model.SChapter
import eu.kanade.tachiyomi.source.model.SManga
import eu.kanade.tachiyomi.source.model.SMangaUpdate
import rx.Observable

/**
 * The interfaces every Mihon/Komikku extension is compiled against.
 *
 * Every member that the stub library declares abstract must exist here with the
 * same JVM signature. Members that an extension may not have been compiled
 * against get a default body, so an extension built for extensions-lib 1.4 keeps
 * loading on a host that implements the 1.7 surface.
 */
@Suppress("unused")
interface Source {

    val id: Long

    val name: String

    fun fetchMangaDetails(manga: SManga): Observable<SManga>

    fun fetchChapterList(manga: SManga): Observable<List<SChapter>>

    fun fetchPageList(chapter: SChapter): Observable<List<Page>>

    // Komikku additions. Defaults keep extensions built for lib 1.4 working.

    suspend fun getMangaDetails(manga: SManga): SManga =
        throw UnsupportedOperationException("This source cannot load details.")

    suspend fun getChapterList(manga: SManga): List<SChapter> =
        throw UnsupportedOperationException("This source cannot load chapters.")

    suspend fun getPageList(chapter: SChapter): List<Page> =
        throw UnsupportedOperationException("This source cannot load pages.")

    /** Modern sources override this; legacy sources keep their separate APIs. */
    suspend fun getMangaUpdate(
        manga: SManga, chapters: List<SChapter>, fetchDetails: Boolean, fetchChapters: Boolean,
    ): SMangaUpdate = SMangaUpdate(
        if (fetchDetails) getMangaDetails(manga) else manga,
        if (fetchChapters) getChapterList(manga) else chapters,
    )

    suspend fun getRelatedMangaList(
        manga: SManga,
        exceptionHandler: (Throwable) -> Unit,
        pushResults: suspend (relatedManga: Pair<String, List<SManga>>, completed: Boolean) -> Unit,
    ) {
        // Related titles are a Komikku nicety; a host that does not browse them
        // simply reports nothing instead of failing the screen.
    }
}

@Suppress("unused")
interface CatalogueSource : Source {

    /** An ISO 639-1 compliant language code (two letters in lower case). */
    val lang: String

    val supportsLatest: Boolean

    fun fetchPopularManga(page: Int): Observable<MangasPage>

    fun fetchSearchManga(page: Int, query: String, filters: FilterList): Observable<MangasPage>

    fun fetchLatestUpdates(page: Int): Observable<MangasPage>

    fun getFilterList(): FilterList

    val supportsRelatedMangas: Boolean get() = false

    val disableRelatedMangasBySearch: Boolean get() = false

    val disableRelatedMangas: Boolean get() = false

    suspend fun fetchRelatedMangaList(manga: SManga): List<SManga> =
        throw UnsupportedOperationException("Unsupported!")

    suspend fun getPopularManga(page: Int): MangasPage =
        throw UnsupportedOperationException("This source cannot browse.")

    suspend fun getSearchManga(page: Int, query: String, filters: FilterList): MangasPage =
        throw UnsupportedOperationException("This source cannot search.")

    suspend fun getLatestUpdates(page: Int): MangasPage =
        throw UnsupportedOperationException("This source cannot list updates.")

    suspend fun getRelatedMangaListByExtension(
        manga: SManga,
        exceptionHandler: (Throwable) -> Unit,
        pushResults: suspend (relatedManga: Pair<String, List<SManga>>, completed: Boolean) -> Unit,
    ) {
    }
}

@Suppress("unused")
interface SourceFactory {
    fun createSources(): List<Source>
}

@Suppress("unused")
interface ConfigurableSource {
    fun setupPreferenceScreen(screen: PreferenceScreen)
}

@Suppress("unused")
interface UnmeteredSource
