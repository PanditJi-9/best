package app.best.best_app.ext

import android.app.Application
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.system.Os
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
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import eu.kanade.tachiyomi.source.CatalogueSource
import eu.kanade.tachiyomi.source.Source
import eu.kanade.tachiyomi.source.SourceFactory
import eu.kanade.tachiyomi.source.model.FilterList
import eu.kanade.tachiyomi.source.model.MangasPage
import eu.kanade.tachiyomi.source.model.SChapter
import eu.kanade.tachiyomi.source.model.SManga
import eu.kanade.tachiyomi.source.model.SMangaUpdate
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import okhttp3.Request
import uy.kohesive.injekt.Injekt
import uy.kohesive.injekt.api.get
import uy.kohesive.injekt.api.addSingleton
import uy.kohesive.injekt.api.addSingletonFactory
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
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

        /** A page image is bounded like any other download, never streamed into memory unbounded. */
        private const val MAX_IMAGE_BYTES = 32L * 1024 * 1024
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
        // Community extensions share a Json service through Injekt; without it
        // their static helpers fail before even making a catalogue request.
        Injekt.addSingleton(Json {
            ignoreUnknownKeys = true
            isLenient = true
            explicitNulls = false
        })
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
        app.packageManager.getPackageArchiveInfo(file.path, PackageManager.GET_META_DATA or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) PackageManager.GET_SIGNING_CERTIFICATES
            else PackageManager.GET_SIGNATURES)

    @Suppress("DEPRECATION")
    private fun versionCode(pkg: android.content.pm.PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) pkg.longVersionCode else pkg.versionCode.toLong()

    @Suppress("DEPRECATION")
    private fun signers(pkg: android.content.pm.PackageInfo): Set<String> {
        val certs = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P)
            pkg.signingInfo?.apkContentsSigners else pkg.signatures
        return certs?.map { cert ->
            MessageDigest.getInstance("SHA-256").digest(cert.toByteArray())
                .joinToString("") { "%02x".format(it) }
        }?.toSet() ?: emptySet()
    }

    @Suppress("DEPRECATION")
    private fun meta(pkg: android.content.pm.PackageInfo, key: String): String? =
        pkg.applicationInfo?.metaData?.get(key)?.toString()?.takeIf { it.isNotBlank() }

    private fun isNsfw(pkg: android.content.pm.PackageInfo): Boolean {
        val declared = meta(pkg, KEY_NSFW) ?: meta(pkg, KEY_ANIME_NSFW)
        return declared == "1" || declared.equals("true", ignoreCase = true)
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
            "versionCode" to versionCode(pkg),
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
        fun tryEntry(name: String) {
            // Android manifest class names may be package-relative, e.g.
            // `.ExtensionGenerated`. Class.forName does not expand them.
            val qualified = when {
                name.startsWith(".") -> pkg.packageName + name
                !name.contains(".") -> "${pkg.packageName}.$name"
                else -> name
            }
            runCatching { instantiate(loader, qualified) }
                .onSuccess { produced += it }
                .onFailure { error -> Log.w(TAG, "entry $qualified failed", error) }
        }
        for (declared in listOfNotNull(className, factoryName)) {
            declared.split(';').map { it.trim() }.filter { it.isNotEmpty() }.forEach { tryEntry(it) }
        }
        // Some bundles only declare a factory class; try the conventional names
        // so an extension with unusual metadata still has a chance to load.
        if (produced.isEmpty()) {
            for (candidate in listOf(
                "${pkg.packageName}.Extension",
                "${pkg.packageName}.SourceFactory",
            )) {
                tryEntry(candidate)
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
        for (file in apkFiles().sortedByDescending { archiveInfo(it)?.let(::versionCode) ?: 0 }) {
            val identity = describe(file) ?: continue
            val pkgName = identity["packageName"] as? String ?: continue
            if (sourceOwner.values.contains(pkgName)) continue
            val error = register(file, pkgName)
            if (error != null) problems += identity + ("error" to error)
        }
        return problems
    }

    /** Loads one APK's sources; returns a human-readable error when it cannot. */
    private fun register(file: File, pkgName: String): String? = try {
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
            "No source could be created."
        } else {
            null
        }
    } catch (t: Throwable) {
        Log.w(TAG, "extension $pkgName failed to load", t)
        t.message ?: t::class.java.simpleName
    }

    /**
     * Re-creates a package's sources after a setting changed. A source may read
     * its domain, credentials or headers once in a constructor, so writing the
     * preference is not enough on its own.
     */
    private fun reloadPackage(pkgName: String?) {
        if (pkgName == null) return
        sourceOwner.filterValues { it == pkgName }.keys.toList().forEach { id ->
            sources.remove(id)
            animeSources.remove(id)
            sourceOwner.remove(id)
        }
        val file = apkFiles().firstOrNull {
            describe(it)?.get("packageName") == pkgName
        } ?: return
        register(file, pkgName)
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
                val expectedPackage = call.argument<String>("expectedPackage")
                val expectedVersion = call.argument<Number>("expectedVersionCode")?.toLong()
                if (url.isNullOrBlank() || expectedPackage.isNullOrBlank() || expectedVersion == null) {
                    result.error("bad-argument", "An extension url, package and version are required.", null)
                    return
                }
                respond(result) { install(url, fileName, expectedPackage, expectedVersion) }
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
                val memo = call.argument<String>("memo").orEmpty()
                respond(result) { details(id, url, memo) }
            }
            "chapters" -> {
                val id = call.argument<Number>("sourceId")?.toLong()
                val url = call.argument<String>("url").orEmpty()
                val memo = call.argument<String>("memo").orEmpty()
                respond(result) { chapters(id, url, memo) }
            }
            "pages" -> {
                val id = call.argument<Number>("sourceId")?.toLong()
                val url = call.argument<String>("url").orEmpty()
                val memo = call.argument<String>("memo").orEmpty()
                respond(result) { pages(id, url, memo) }
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
            "imageBytes" -> {
                val id = call.argument<Number>("sourceId")?.toLong()
                val url = call.argument<String>("url").orEmpty()
                val headers = call.argument<Map<String, String>>("headers") ?: emptyMap()
                respond(result) { imageBytes(id, url, headers) }
            }
            "settings" -> {
                val id = call.argument<Number>("sourceId")?.toLong()
                respond(result) { settingsFor(id) }
            }
            "setSetting" -> {
                val id = call.argument<Number>("sourceId")?.toLong()
                val key = call.argument<String>("key")
                val value = call.argument<String>("value")
                if (id == null || key.isNullOrBlank() || value == null) {
                    result.error("bad-argument", "A source id, setting key and value are required.", null)
                    return
                }
                respond(result) { setSetting(id, key, value) }
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
                        Log.w(TAG, "extension request failed", error)
                        result.error("extension-error", error.message ?: "The extension failed.", null)
                    },
                )
            }
        }
    }

    // ------------------------------------------------------------------- calls

    /** Installed extensions plus every source they expose. */
    @Synchronized
    private fun catalog(): Map<String, Any?> {
        val problems = ensureLoaded()
        val inventory = apkFiles().mapNotNull(::describe)
            .sortedByDescending { (it["versionCode"] as? Long) ?: 0 }
            .distinctBy { it["packageName"] }
        val identities = inventory.associateBy { it["packageName"] }
        Log.i(TAG, "catalog: ${sources.size} manga, ${animeSources.size} anime, ${problems.size} problem(s)")
        val entries = mutableListOf<Map<String, Any?>>()
        sources.forEach { (id, source) ->
            val catalogue = source as? CatalogueSource
            entries += entry(id, source.name, "manga", catalogue?.lang, catalogue?.supportsLatest == true,
                identities[sourceOwner[id]] ?: emptyMap())
        }
        animeSources.forEach { (id, source) ->
            entries += entry(id, source.name, "anime", source.lang, source.supportsLatest,
                identities[sourceOwner[id]] ?: emptyMap())
        }
        return mapOf<String, Any?>(
            "sources" to entries,
            "problems" to problems,
            "installed" to inventory,
        )
    }

    /** One row of the catalog the picker reads. */
    private fun entry(
        id: Long,
        name: String,
        kind: String,
        lang: String?,
        supportsLatest: Boolean,
        identity: Map<String, Any?>,
    ): Map<String, Any?> {
        val owner = sourceOwner[id]
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

    @Synchronized
    private fun install(url: String, fileName: String, expectedPackage: String,
                        expectedVersion: Long): Map<String, Any?> {
        require(ExtensionInstallPolicy.allowDownload(url)) { "Only the configured publisher repositories are allowed." }
        val staged = File.createTempFile("install-", ".part", extensionsDir)
        try {
        download(url, staged)
        val pkg = archiveInfo(staged) ?: error("The download is not a valid APK.")
        require(meta(pkg, KEY_CLASS) != null || meta(pkg, KEY_FACTORY) != null ||
            meta(pkg, KEY_ANIME_CLASS) != null || meta(pkg, KEY_ANIME_FACTORY) != null) {
            "The APK does not declare an extension entry point."
        }
        val previous = apkFiles().mapNotNull { file -> archiveInfo(file)?.let { file to it } }
            .filter { it.second.packageName == expectedPackage }
        val newest = previous.maxByOrNull { versionCode(it.second) }?.second
        ExtensionInstallPolicy.validateIdentity(expectedPackage, expectedVersion,
            pkg.packageName, versionCode(pkg), signers(pkg), newest?.let(::versionCode), newest?.let(::signers))
        // Check every duplicate left by the legacy filename installer as well.
        require(previous.all { signers(it.second) == signers(pkg) }) { "Conflicting installed signing certificates." }
        val target = File(extensionsDir, "$expectedPackage.apk")
        check(staged.setReadOnly()) { "Could not protect the extension APK." }
        // Atomic same-filesystem replacement. No old APK is touched on any
        // network, identity, certificate or version validation failure.
        Os.rename(staged.path, target.path)
        previous.filter { it.first.path != target.path }.forEach { it.first.delete() }
        unload(expectedPackage)
        Log.i(TAG, "installed $expectedPackage version $expectedVersion from $fileName")
        return describe(target) ?: error("The extension could not be read after installation.")
        } finally { staged.delete() }
    }

    private fun download(url: String, staged: File, redirects: Int = 0) {
        require(redirects <= 5 && ExtensionInstallPolicy.allowDownload(url, redirects > 0)) {
            "The extension download redirected outside a trusted HTTPS host."
        }
        val connection = (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = 30_000
            readTimeout = 60_000
            instanceFollowRedirects = false
            setRequestProperty("User-Agent", "Best/1.0")
        }
        try {
            val code = connection.responseCode
            if (code in listOf(301, 302, 303, 307, 308)) {
                val location = connection.getHeaderField("Location") ?: error("Missing download redirect.")
                download(URL(URL(url), location).toString(), staged, redirects + 1)
                return
            }
            if (code !in 200..299) throw IllegalStateException("The extension download answered HTTP $code.")
            require(connection.contentLengthLong <= 32 * 1024 * 1024) { "The extension APK is too large." }
            connection.inputStream.use { input ->
                staged.outputStream().use { output ->
                    val buffer = ByteArray(64 * 1024)
                    var total = 0L
                    while (true) {
                        val read = input.read(buffer)
                        if (read < 0) break
                        total += read
                        require(total <= 32 * 1024 * 1024) { "The extension APK is too large." }
                        output.write(buffer, 0, read)
                    }
                }
            }
        } finally {
            connection.disconnect()
        }
    }

    private fun unload(packageName: String) {
        sourceOwner.filterValues { it == packageName }.keys.forEach {
            sources.remove(it)
            animeSources.remove(it)
            sourceOwner.remove(it)
        }
    }

    @Synchronized
    private fun uninstall(packageName: String?): Boolean {
        if (packageName.isNullOrBlank()) return false
        val files = apkFiles().filter { describe(it)?.get("packageName") == packageName }
        if (files.isEmpty()) return false
        val removed = files.all { it.delete() }
        unload(packageName)
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

    // KeiSource rejects concurrent metadata/chapter updates. Flutter asks for
    // both in parallel, so serialize just those calls per installed source.
    private val mangaUpdateLocks = ConcurrentHashMap<Long, Mutex>()

    private suspend fun mangaUpdate(
        source: Source, url: String, memo: String, details: Boolean, chapters: Boolean,
    ): SMangaUpdate =
        mangaUpdateLocks.computeIfAbsent(source.id) { Mutex() }.withLock {
            val manga = SManga.create().apply {
                this.url = url
                // Madara-derived sources keep the canonical manga path in the
                // catalogue card's memo and build chapter/page URLs from it.
                // Without it the chapter list is fetched for `/?p=<id>` and the
                // pages resolve against the wrong path.
                if (memo.isNotBlank()) {
                    runCatching { this.memo = Json.parseToJsonElement(memo).jsonObject }
                }
            }
            source.getMangaUpdate(manga, emptyList(), details, chapters)
        }

    private suspend fun details(id: Long?, url: String, memo: String = ""): Map<String, Any?> {
        animeFor(id ?: 0L)?.let { source ->
            val anime = SAnime.create().apply { this.url = url }
            return animeToMap(source.getAnimeDetails(anime), source)
        }
        val source = id?.let { sourceFor(it) } ?: throw IllegalStateException("Unknown source.")
        return mangaToMap(
            mangaUpdate(source, url, memo, details = true, chapters = false).manga,
            source,
        )
    }

    private suspend fun chapters(id: Long?, url: String, memo: String = ""): List<Map<String, Any?>> {
        animeFor(id ?: 0L)?.let { return episodes(id, url) }
        val source = id?.let { sourceFor(it) } ?: throw IllegalStateException("Unknown source.")
        return mangaUpdate(source, url, memo, details = false, chapters = true).chapters
            .map { chapterToMap(it, source) }
    }

    private suspend fun pages(id: Long?, url: String, memo: String): List<Map<String, Any?>> {
        val source = id?.let { sourceFor(it) } ?: throw IllegalStateException("Unknown source.")
        // Madara-derived sources (Mangalek among them) keep the manga path in
        // `chapter.memo` and refuse to build a page list without it
        // ("Refresh the chapter list."), so the memo the chapter list produced
        // must travel back with the chapter the reader asks for.
        val chapter = SChapter.create().apply {
            this.url = url
            if (memo.isNotBlank()) {
                runCatching { this.memo = Json.parseToJsonElement(memo).jsonObject }
            }
        }
        val raw = source.getPageList(chapter)
        // A source that returns an empty list looks like "this chapter has no
        // pages" in the reader, and there is no other way to tell a parse that
        // found nothing from a request that hit the wrong URL.
        Log.i(
            TAG,
            "pages: ${source.name} $url memo=${memo.length}B -> ${raw.size}" +
                (raw.firstOrNull()?.let { " first=[${it.url}|${it.imageUrl}]" } ?: ""),
        )
        // Pages may come back as an index or as a direct image url; resolve both
        // so the reader never has to know which style the extension used.
        return raw.mapIndexed { position, page ->
            val http = source as? eu.kanade.tachiyomi.source.online.HttpSource
            val resolved = if (page.imageUrl.isNullOrBlank() && page.url.isNotBlank() && http != null) {
                runCatching { http.getImageUrl(page) }.getOrDefault(page.url)
            } else {
                page.imageUrl
            }
            // Modern MangaDex returns metadata + a relative image suffix. Its
            // own imageRequest resolves that into the actual CDN request.
            if (!resolved.isNullOrBlank()) page.imageUrl = resolved
            val imageRequest = http?.pageImageRequest(page)
            mapOf<String, Any?>(
                "index" to (page.index.takeIf { it > 0 } ?: position),
                "url" to (imageRequest?.url?.toString() ?: resolved ?: page.url),
                "headers" to (imageRequest?.headers?.toMultimap() ?: headersFor(id)["headers"]),
            )
        }
    }

    // ------------------------------------------------------------------- anime

    /**
     * One page image, fetched by the extension's own client.
     *
     * Flutter's HTTP stack has neither the extension's cookies nor its signing
     * interceptors, so a CDN that accepts Mihon's request answers 403 to the
     * reader (MangaFire did exactly that). Downloading through the host keeps
     * the request identical to what the extension expects, and gives the reader
     * a real error instead of a silent broken-image icon.
     */
    private suspend fun imageBytes(id: Long?, url: String, headers: Map<String, String>): ByteArray {
        require(url.startsWith("https://") || url.startsWith("http://")) {
            "Only http(s) page images can be loaded."
        }
        val source = id?.let { sourceFor(it) }
        val client = (source as? eu.kanade.tachiyomi.source.online.HttpSource)?.client
            ?: Injekt.get<NetworkHelper>().client
        val request = Request.Builder().url(url).apply {
            headers.forEach { (key, value) ->
                if (key.isNotBlank() && value.isNotBlank() && !key.equals("Host", true)) {
                    header(key, value)
                }
            }
        }.build()
        client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) {
                throw java.io.IOException("The site answered HTTP ${response.code} for this page image.")
            }
            val body = response.body ?: throw java.io.IOException("The site returned an empty page image.")
            require(body.contentLength() <= MAX_IMAGE_BYTES) { "This page image is too large to open." }
            val bytes = body.bytes()
            require(bytes.size <= MAX_IMAGE_BYTES) { "This page image is too large to open." }
            return bytes
        }
    }

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

    /** The settings screen an extension declares, as JSON, or `[]` when none. */
    private fun settingsFor(id: Long?): String {
        if (id == null) return "[]"
        val source = sources[id] ?: animeSources[id] ?: return "[]"
        return SourcePreferences.describe(app, id, source).toString()
    }

    private fun setSetting(id: Long, key: String, value: String): Boolean {
        val source = sources[id] ?: animeSources[id] ?: return false
        if (!SourcePreferences.apply(app, id, source, key, value)) return false
        // Re-create the package's sources so a value read in a constructor (a
        // domain, a token) takes effect without a restart.
        reloadPackage(sourceOwner[id])
        return true
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
        // Round-trips the work-level memo; `SManga.memo` is a JsonObject, and
        // an empty one must not look like data to the store.
        "memo" to (manga.memo.takeIf { it.isNotEmpty() }?.toString() ?: ""),
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
        "memo" to chapter.memo.toString(),
        "sourceId" to source.id,
    )
}
