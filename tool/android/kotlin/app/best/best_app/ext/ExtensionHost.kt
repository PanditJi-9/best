package app.best.best_app.ext

import android.app.Application
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import dalvik.system.DexClassLoader
import eu.kanade.tachiyomi.AppInfo
import eu.kanade.tachiyomi.animesource.AnimeCatalogueSource
import eu.kanade.tachiyomi.animesource.AnimeSource
import eu.kanade.tachiyomi.animesource.AnimeSourceFactory
import eu.kanade.tachiyomi.animesource.model.AnimeFilterList
import eu.kanade.tachiyomi.animesource.model.AnimesPage
import eu.kanade.tachiyomi.animesource.model.SAnime
import eu.kanade.tachiyomi.animesource.model.SEpisode
import eu.kanade.tachiyomi.animesource.model.Video
import eu.kanade.tachiyomi.network.NetworkHelper
import eu.kanade.tachiyomi.source.CatalogueSource
import eu.kanade.tachiyomi.source.Source
import eu.kanade.tachiyomi.source.SourceFactory
import eu.kanade.tachiyomi.source.model.FilterList
import eu.kanade.tachiyomi.source.model.MangasPage
import eu.kanade.tachiyomi.source.model.SChapter
import eu.kanade.tachiyomi.source.model.SManga
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uy.kohesive.injekt.Injekt
import uy.kohesive.injekt.api.addSingleton
import uy.kohesive.injekt.api.addSingletonFactory
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.ConcurrentHashMap

/**
 * Everything an installed extension APK needs to become a usable catalogue.
 *
 * An extension is a plain Android APK with a `classes.dex` and some manifest
 * metadata; it has no activity and no entry point of its own. The host loads the
 * dex with a [DexClassLoader] whose parent is the app's class loader, so the
 * `eu.kanade.tachiyomi.*` classes the extension was compiled against resolve to
 * the real implementations Best ships. Nothing is scraped by Best itself: the
 * extension is the program, exactly as it is under Mihon or Komikku.
 */
class ExtensionHost(private val context: Context) {

    companion object {
        private const val KEY_CLASS = "tachiyomi.extension.class"
        private const val KEY_FACTORY = "tachiyomi.extension.factory"
        private const val KEY_NSFW = "tachiyomi.extension.nsfw"

        /**
         * Anime extensions declare their entry point under their own keys, a
         * leftover from the Aniyomi fork. Both are read, so one loader serves
         * manga and anime bundles alike.
         */
        private const val KEY_ANIME_CLASS = "tachiyomi.animeextension.class"
        private const val KEY_ANIME_FACTORY = "tachiyomi.animeextension.factory"
        private const val KEY_ANIME_NSFW = "tachiyomi.animeextension.nsfw"
        private const val KEY_LIB_VERSION = "tachiyomix.extensionLib"
        private const val CHANNEL = "app.best/extensions"

        /**
         * Every extension outcome lands in logcat. Without this a source that
         * fails to load is invisible on a phone, and impossible to diagnose from
         * a build log.
         */
        private const val TAG = "BestExtensions"
    }

    private val app: Application = context.applicationContext as Application
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /** Where installed extension APKs live. Private to the app, never exported. */
    val extensionsDir: File = File(app.filesDir, "extensions").apply { mkdirs() }

    private val dexOutDir: File = File(app.codeCacheDir, "extension-dex").apply { mkdirs() }

    /** Loaded sources, keyed by the stable source id the extension generates. */
    private val sources = ConcurrentHashMap<Long, Source>()

    /** Anime sources, kept apart because they answer a different contract. */
    private val animeSources = ConcurrentHashMap<Long, AnimeSource>()

    /** Which extension package contributed which source id. */
    private val sourceOwner = ConcurrentHashMap<Long, String>()

    private var registered = false

    // ---------------------------------------------------------------- plumbing

    fun attach(messenger: BinaryMessenger) {
        registerSingletons()
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            handle(call, result)
        }
    }

    /**
     * Extensions reach for `Injekt.get<Application>()`, `Injekt.get<Context>()`
     * and `networkHelper.client` through Injekt, so those must exist before the
     * first class is loaded.
     */
    private fun registerSingletons() {
        if (registered) return
        registered = true
        Injekt.addSingletonFactory { app }
        Injekt.addSingletonFactory { app as Context }
        Injekt.addSingleton(NetworkHelper(app))
        try {
            val info = app.packageManager.getPackageInfo(app.packageName, 0)
            AppInfo.versionName = info.versionName ?: "0.0.0"
            AppInfo.versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                info.longVersionCode.toInt()
            } else {
                @Suppress("DEPRECATION")
                info.versionCode
            }
        } catch (_: Throwable) {
            // Version reporting is cosmetic; never block extension loading on it.
        }
    }

    // ------------------------------------------------------------------- files

    /** Every extension APK sitting in the private extension folder. */
    private fun apkFiles(): List<File> =
        extensionsDir.listFiles { file -> file.isFile && file.name.endsWith(".apk") }
            ?.sortedBy { it.name }
            ?: emptyList()

    @Suppress("DEPRECATION")
    private fun archiveInfo(file: File): android.content.pm.PackageInfo? =
        app.packageManager.getPackageArchiveInfo(file.path, PackageManager.GET_META_DATA)

    private fun meta(pkg: android.content.pm.PackageInfo, key: String): String? =
        pkg.applicationInfo?.metaData?.getString(key)?.takeIf { it.isNotBlank() }

    private fun isNsfw(pkg: android.content.pm.PackageInfo): Boolean {
        val declared = meta(pkg, KEY_NSFW) ?: meta(pkg, KEY_ANIME_NSFW)
        return declared?.toBoolean()
            ?: (pkg.applicationInfo?.metaData?.getBoolean(KEY_NSFW) ?: false)
            ?: (pkg.applicationInfo?.metaData?.getBoolean(KEY_ANIME_NSFW) ?: false)
    }

    /** Reads an APK's identity without loading any of its code. */
    private fun describe(file: File): Map<String, Any?>? {
        val pkg = archiveInfo(file) ?: return null
        return mapOf(
            "kind" to if (meta(pkg, KEY_ANIME_CLASS) != null || meta(pkg, KEY_ANIME_FACTORY) != null) {
                "anime"
            } else {
                "manga"
            },
            "packageName" to pkg.packageName,
            "versionName" to (pkg.versionName ?: ""),
            "nsfw" to isNsfw(pkg),
            "libVersion" to (meta(pkg, KEY_LIB_VERSION) ?: ""),
            "fileName" to file.name,
            "size" to file.length(),
        )
    }

    // ---------------------------------------------------------------- loading

    private fun classLoaderFor(file: File): DexClassLoader = DexClassLoader(
        file.path,
        dexOutDir.absolutePath,
        null,
        app.classLoader,
    )

    /**
     * Instantiates every source an extension APK declares. A broken extension
     * must never take the host down, so each failure is reported per-extension
     * and the rest keep loading.
     */
    private fun loadSources(file: File): List<Any> {
        val pkg = archiveInfo(file) ?: return emptyList()
        val loader = classLoaderFor(file)
        val className = meta(pkg, KEY_CLASS) ?: meta(pkg, KEY_ANIME_CLASS)
        val factoryName = meta(pkg, KEY_FACTORY) ?: meta(pkg, KEY_ANIME_FACTORY)

        val produced = mutableListOf<Any>()
        if (!className.isNullOrBlank()) {
            runCatching { instantiate(loader, className) }.getOrNull()?.let { produced += it }
        }
        if (!factoryName.isNullOrBlank()) {
            runCatching { instantiate(loader, factoryName) }.getOrNull()?.let { produced += it }
        }
        // Some bundles only declare a factory class; try the conventional names
        // so an extension with unusual metadata still has a chance to load.
        if (produced.isEmpty()) {
            for (candidate in listOf(
                "${pkg.packageName}.Extension",
                "${pkg.packageName}.SourceFactory",
            )) {
                runCatching { instantiate(loader, candidate) }.getOrNull()?.let { produced += it }
            }
        }
        return produced.flatMap { expand(it) }
            .filter { it is CatalogueSource || it is AnimeCatalogueSource }
    }

    /** A factory answers with a list; a plain source is its own list. */
    private fun expand(instance: Any): List<Any> = when (instance) {
        is SourceFactory -> instance.createSources()
        is AnimeSourceFactory -> instance.createSources()
        else -> listOf(instance)
    }

    /**
     * Newer sources take a preference list in their only constructor, so a
     * no-argument lookup is not enough. Both shapes are tried, and the list one
     * gets an empty list: Best does not render extension preference screens yet,
     * and an empty list is what the real app passes on a first run.
     */
    private fun instantiate(loader: ClassLoader, name: String): Any {
        val clazz = Class.forName(name, true, loader)
        val noArg = clazz.declaredConstructors.firstOrNull { it.parameterTypes.isEmpty() }
        if (noArg != null) {
            noArg.isAccessible = true
            return noArg.newInstance()
        }
        val listCtor = clazz.declaredConstructors.firstOrNull { ctor ->
            ctor.parameterTypes.size == 1 && List::class.java.isAssignableFrom(ctor.parameterTypes[0])
        } ?: throw NoSuchMethodException("$name has no usable constructor.")
        listCtor.isAccessible = true
        return listCtor.newInstance(emptyList<Any>())
    }

    private fun ensureLoaded(): List<Map<String, Any?>> {
        val problems = mutableListOf<Map<String, Any?>>()
        for (file in apkFiles()) {
            val identity = describe(file) ?: continue
            val pkgName = identity["packageName"] as? String ?: continue
            val already = sourceOwner.values.contains(pkgName)
            if (already) continue
            try {
                val loaded = loadSources(file)
                loaded.forEach { source ->
                    when (source) {
                        is AnimeSource -> animeSources[source.id] = source
                        is Source -> sources[source.id] = source
                    }
                    val id = when (source) {
                        is AnimeSource -> source.id
                        is Source -> source.id
                        else -> 0L
                    }
                    sourceOwner[id] = pkgName
                    Log.i(TAG, "loaded ${nameOf(source)} ($id) from $pkgName")
                }
                if (loaded.isEmpty()) {
                    Log.w(TAG, "no source could be created by $pkgName")
                    problems += identity + ("error" to "No source could be created.")
                }
            } catch (t: Throwable) {
                Log.w(TAG, "extension $pkgName failed to load", t)
                problems += identity + ("error" to (t.message ?: t::class.java.simpleName))
            }
        }
        return problems
    }

    private fun nameOf(source: Any): String = when (source) {
        is AnimeSource -> source.name
        is Source -> source.name
        else -> "?"
    }

    private fun sourceFor(id: Long): CatalogueSource? = sources[id] as? CatalogueSource

    private fun animeFor(id: Long): AnimeSource? = animeSources[id]

    // ------------------------------------------------------------------ bridge

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "catalog" -> respond(result) { catalog() }
            "install" -> {
                val url = call.argument<String>("url")
                val fileName = call.argument<String>("fileName") ?: "extension.apk"
                if (url.isNullOrBlank()) {
                    result.error("bad-argument", "An extension url is required.", null)
                    return
                }
                respond(result) { install(url, fileName) }
            }
            "remove" -> {
                val pkgName = call.argument<String>("packageName")
                respond(result) {
                    uninstall(pkgName)
                }
            }
            "popular" -> {
                val id = call.argument<Number>("sourceId")?.toLong()
                val page = call.argument<Number>("page")?.toInt() ?: 1
                respond(result) { popular(id, page) }
            }
            "latest" -> {
                val id = call.argument<Number>("sourceId")?.toLong()
                val page = call.argument<Number>("page")?.toInt() ?: 1
                respond(result) { latest(id, page) }
            }
            "search" -> {
                val id = call.argument<Number>("sourceId")?.toLong()
                val page = call.argument<Number>("page")?.toInt() ?: 1
                val query = call.argument<String>("query").orEmpty()
                respond(result) { search(id, query, page) }
            }
            "details" -> {
                val id = call.argument<Number>("sourceId")?.toLong()
                val url = call.argument<String>("url").orEmpty()
                respond(result) { details(id, url) }
            }
            "chapters" -> {
                val id = call.argument<Number>("sourceId")?.toLong()
                val url = call.argument<String>("url").orEmpty()
                respond(result) { chapters(id, url) }
            }
            "pages" -> {
                val id = call.argument<Number>("sourceId")?.toLong()
                val url = call.argument<String>("url").orEmpty()
                respond(result) { pages(id, url) }
            }
            "episodes" -> {
                val id = call.argument<Number>("sourceId")?.toLong()
                val url = call.argument<String>("url").orEmpty()
                respond(result) { episodes(id, url) }
            }
            "videos" -> {
                val id = call.argument<Number>("sourceId")?.toLong()
                val url = call.argument<String>("url").orEmpty()
                respond(result) { videos(id, url) }
            }
            "headers" -> {
                val id = call.argument<Number>("sourceId")?.toLong()
                respond(result) { headersFor(id) }
            }
            else -> result.notImplemented()
        }
    }

    private fun respond(result: MethodChannel.Result, block: suspend () -> Any?) {
        scope.launch {
            val outcome = runCatching { block() }
            withContext(Dispatchers.Main) {
                outcome.fold(
                    onSuccess = { result.success(it) },
                    onFailure = { error ->
                        result.error("extension-error", error.message ?: "The extension failed.", null)
                    },
                )
            }
        }
    }

    // ------------------------------------------------------------------- calls

    /** Installed extensions plus every source they expose. */
    private fun catalog(): Map<String, Any?> {
        val problems = ensureLoaded()
        Log.i(TAG, "catalog: ${sources.size} manga, ${animeSources.size} anime, ${problems.size} problem(s)")
        val entries = mutableListOf<Map<String, Any?>>()
        sources.forEach { (id, source) ->
            val catalogue = source as? CatalogueSource
            entries += entry(id, source.name, "manga", catalogue?.lang, catalogue?.supportsLatest == true)
        }
        animeSources.forEach { (id, source) ->
            entries += entry(id, source.name, "anime", source.lang, source.supportsLatest)
        }
        return mapOf<String, Any?>(
            "sources" to entries,
            "problems" to problems,
        )
    }

    /** One row of the catalog the picker reads. */
    private fun entry(
        id: Long,
        name: String,
        kind: String,
        lang: String?,
        supportsLatest: Boolean,
    ): Map<String, Any?> {
        val owner = sourceOwner[id]
        val identity = apkFiles()
            .firstOrNull { describe(it)?.get("packageName") == owner }
            ?.let { describe(it) }
            ?: emptyMap()
        return mapOf(
            "sourceId" to id,
            "name" to name,
            "kind" to kind,
            "lang" to (lang ?: ""),
            "supportsLatest" to supportsLatest,
            "packageName" to owner,
            "versionName" to identity["versionName"],
            "nsfw" to (identity["nsfw"] ?: false),
        )
    }

    private fun install(url: String, fileName: String): Map<String, Any?> {
        val safeName = fileName.replace(Regex("[^A-Za-z0-9._-]"), "_").ifBlank { "extension.apk" }
            .let { if (it.endsWith(".apk")) it else "$it.apk" }
        val target = File(extensionsDir, safeName)
        val staged = File(extensionsDir, "$safeName.part")
        val connection = (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = 30_000
            readTimeout = 60_000
            instanceFollowRedirects = true
            setRequestProperty("User-Agent", "Best/1.0")
        }
        try {
            val code = connection.responseCode
            if (code !in 200..299) throw IllegalStateException("The extension download answered HTTP $code.")
            connection.inputStream.use { input ->
                staged.outputStream().use { output -> input.copyTo(output, 64 * 1024) }
            }
        } finally {
            connection.disconnect()
        }
        if (!staged.renameTo(target)) {
            staged.delete()
            throw IllegalStateException("The extension could not be stored.")
        }
        target.setReadOnly()
        // A new APK means the old classes must go, so the next catalog reloads.
        sources.clear()
        animeSources.clear()
        sourceOwner.clear()
        val identity = describe(target)
        return identity ?: mapOf<String, Any?>("fileName" to target.name)
    }

    private fun uninstall(packageName: String?): Boolean {
        if (packageName.isNullOrBlank()) return false
        sourceOwner.filterValues { it == packageName }.keys.forEach {
            sources.remove(it)
            animeSources.remove(it)
            sourceOwner.remove(it)
        }
        val removed = apkFiles().filter { describe(it)?.get("packageName") == packageName }
            .onEach { it.delete() }
            .isNotEmpty()
        return removed
    }

    private suspend fun popular(id: Long?, page: Int): Map<String, Any?> {
        animeFor(id ?: 0L)?.let { return animesPageToMap(it.getPopularAnime(page), it) }
        val source = id?.let { sourceFor(it) } ?: throw IllegalStateException("Unknown source.")
        return pageToMap(source.getPopularManga(page), source)
    }

    private suspend fun latest(id: Long?, page: Int): Map<String, Any?> {
        animeFor(id ?: 0L)?.let { return animesPageToMap(it.getLatestUpdates(page), it) }
        val source = id?.let { sourceFor(it) } ?: throw IllegalStateException("Unknown source.")
        return pageToMap(source.getLatestUpdates(page), source)
    }

    private suspend fun search(id: Long?, query: String, page: Int): Map<String, Any?> {
        animeFor(id ?: 0L)?.let {
            return animesPageToMap(it.getSearchAnime(page, query, AnimeFilterList()), it)
        }
        val source = id?.let { sourceFor(it) } ?: throw IllegalStateException("Unknown source.")
        return pageToMap(source.getSearchManga(page, query, FilterList()), source)
    }

    private suspend fun details(id: Long?, url: String): Map<String, Any?> {
        animeFor(id ?: 0L)?.let { source ->
            val anime = SAnime.create().apply { this.url = url }
            return animeToMap(source.getAnimeDetails(anime), source)
        }
        val source = id?.let { sourceFor(it) } ?: throw IllegalStateException("Unknown source.")
        val manga = SManga.create().apply { this.url = url }
        return mangaToMap(source.getMangaDetails(manga), source)
    }

    private suspend fun chapters(id: Long?, url: String): List<Map<String, Any?>> {
        animeFor(id ?: 0L)?.let { return episodes(id, url) }
        val source = id?.let { sourceFor(it) } ?: throw IllegalStateException("Unknown source.")
        val manga = SManga.create().apply { this.url = url }
        return source.getChapterList(manga).map { chapterToMap(it, source) }
    }

    private suspend fun pages(id: Long?, url: String): List<Map<String, Any?>> {
        val source = id?.let { sourceFor(it) } ?: throw IllegalStateException("Unknown source.")
        val chapter = SChapter.create().apply { this.url = url }
        val raw = source.getPageList(chapter)
        // Pages may come back as an index or as a direct image url; resolve both
        // so the reader never has to know which style the extension used.
        return raw.mapIndexed { position, page ->
            val http = source as? eu.kanade.tachiyomi.source.online.HttpSource
            val resolved = if (page.imageUrl.isNullOrBlank() && page.url.isNotBlank() && http != null) {
                runCatching { http.getImageUrl(page) }.getOrDefault(page.url)
            } else {
                page.imageUrl
            }
            mapOf<String, Any?>(
                "index" to (page.index.takeIf { it > 0 } ?: position),
                "url" to (resolved ?: page.url),
                "headers" to headersFor(id)["headers"],
            )
        }
    }

    // ------------------------------------------------------------------- anime

    private suspend fun episodes(id: Long?, url: String): List<Map<String, Any?>> {
        val source = animeFor(id ?: 0L) ?: throw IllegalStateException("Unknown anime source.")
        val anime = SAnime.create().apply { this.url = url }
        return source.getEpisodeList(anime).map { episodeToMap(it, source) }
    }

    /**
     * Streams for one episode.
     *
     * Current sources hand back mirrors (hosters) first and resolve a stream per
     * mirror; older ones answer the episode directly. Both are tried, and a
     * mirror that fails is skipped instead of failing the whole episode.
     */
    private suspend fun videos(id: Long?, url: String): List<Map<String, Any?>> {
        val source = animeFor(id ?: 0L) ?: throw IllegalStateException("Unknown anime source.")
        val episode = SEpisode.create().apply { this.url = url }
        val collected = mutableListOf<Video>()
        val hosters = runCatching { source.getHosterList(episode) }.getOrDefault(emptyList())
        for (hoster in hosters) {
            runCatching { source.getVideoList(hoster) }
                .getOrDefault(emptyList())
                .let { collected += it }
        }
        if (collected.isEmpty()) {
            collected += source.getVideoList(episode)
        }
        return collected
            .filter { it.videoUrl.isNotBlank() }
            .map { videoToMap(it, source) }
    }

    private fun headersFor(id: Long?): Map<String, Any?> {
        val source = sources[id] as? eu.kanade.tachiyomi.source.online.HttpSource
        val headers = source?.headers?.toMultimap().orEmpty()
        return mapOf<String, Any?>("headers" to headers)
    }

    // ----------------------------------------------------------------- mapping

    private fun pageToMap(page: MangasPage, source: Source): Map<String, Any?> = mapOf<String, Any?>(
        "items" to page.mangas.map { mangaToMap(it, source) },
        "hasNextPage" to page.hasNextPage,
    )

    private fun mangaToMap(manga: SManga, source: Source?): Map<String, Any?> = mapOf<String, Any?>(
        "url" to manga.url,
        "title" to manga.title,
        "artist" to manga.artist,
        "author" to manga.author,
        "description" to manga.description,
        "genre" to manga.genre,
        "status" to manga.status,
        // `to` binds tighter than `?:`, so the fallback needs its own parens or
        // the elvis applies to the pair instead of the cover url.
        "thumbnailUrl" to (
            (source as? eu.kanade.tachiyomi.source.online.HttpSource)
                ?.resolveUrl(manga.thumbnail_url)
                ?: manga.thumbnail_url
            ),
        "sourceId" to source?.id,
    )

    private fun animesPageToMap(page: AnimesPage, source: AnimeSource): Map<String, Any?> = mapOf<String, Any?>(
        "items" to page.animes.map { animeToMap(it, source) },
        "hasNextPage" to page.hasNextPage,
    )

    private fun animeToMap(anime: SAnime, source: AnimeSource?): Map<String, Any?> = mapOf<String, Any?>(
        "url" to anime.url,
        "title" to anime.title,
        "artist" to anime.artist,
        "author" to anime.author,
        "description" to anime.description,
        "genre" to anime.genre,
        "status" to anime.status,
        "thumbnailUrl" to (
            (source as? eu.kanade.tachiyomi.animesource.online.AnimeHttpSource)
                ?.resolveUrl(anime.thumbnail_url)
                ?: anime.thumbnail_url
            ),
        "sourceId" to source?.id,
    )

    private fun episodeToMap(episode: SEpisode, source: AnimeSource): Map<String, Any?> = mapOf<String, Any?>(
        "url" to episode.url,
        "name" to episode.name,
        "dateUpload" to episode.date_upload,
        "chapterNumber" to episode.episode_number.toDouble(),
        "scanlator" to episode.scanlator,
        "sourceId" to source.id,
    )

    private fun videoToMap(video: Video, source: AnimeSource): Map<String, Any?> {
        val headers = video.headers?.toMultimap()
            ?: (source as? eu.kanade.tachiyomi.animesource.online.AnimeHttpSource)?.headers?.toMultimap()
            ?: emptyMap()
        return mapOf<String, Any?>(
            "url" to video.videoUrl,
            "quality" to video.quality,
            "title" to video.label(),
            "headers" to headers,
        )
    }

    private fun chapterToMap(chapter: SChapter, source: Source): Map<String, Any?> = mapOf<String, Any?>(
        "url" to chapter.url,
        "name" to chapter.name,
        "dateUpload" to chapter.date_upload,
        "chapterNumber" to chapter.chapter_number,
        "scanlator" to chapter.scanlator,
        "sourceId" to source.id,
    )
}
