package eu.kanade.tachiyomi.network

import android.content.Context
import kotlinx.coroutines.suspendCancellableCoroutine
import okhttp3.CacheControl
import okhttp3.Call
import okhttp3.Cookie
import okhttp3.CookieJar
import okhttp3.Headers
import okhttp3.HttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.Response
import okhttp3.ResponseBody
import okhttp3.RequestBody.Companion.toRequestBody
import rx.Observable
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/** The default user agent, kept close to what Mihon sends so sites behave. */
const val DEFAULT_USER_AGENT =
    "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) " +
        "Chrome/124.0.0.0 Mobile Safari/537.36"

/**
 * Cookies live for the lifetime of the process. Extensions that need a session
 * (a login wall, an age gate) still work within a reading session, which is what
 * they are written to expect.
 */
class MemoryCookieJar : CookieJar {
    private val store = ConcurrentHashMap<String, MutableList<Cookie>>()

    override fun saveFromResponse(url: HttpUrl, cookies: List<Cookie>) {
        val bucket = store.getOrPut(url.host) { mutableListOf() }
        synchronized(bucket) {
            cookies.forEach { fresh ->
                bucket.removeAll { it.name == fresh.name && it.path == fresh.path }
                if (fresh.expiresAt > System.currentTimeMillis()) bucket.add(fresh)
            }
        }
    }

    override fun loadForRequest(url: HttpUrl): List<Cookie> {
        val bucket = store[url.host] ?: return emptyList()
        val now = System.currentTimeMillis()
        synchronized(bucket) {
            bucket.removeAll { it.expiresAt <= now }
            return bucket.filter { it.matches(url) }
        }
    }
}

/**
 * What `networkHelper.client` answers with inside an extension.
 *
 * Extensions obtain this through Injekt (`networkHelper: NetworkHelper by
 * injectLazy()`), so the host registers one instance at start-up.
 */
class NetworkHelper(@Suppress("UNUSED_PARAMETER") context: Context) {

    val client: OkHttpClient = OkHttpClient.Builder()
        .cookieJar(MemoryCookieJar())
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .followRedirects(true)
        .followSslRedirects(true)
        .build()

    val defaultUserAgent: String = DEFAULT_USER_AGENT
}

private val DEFAULT_CACHE_CONTROL: CacheControl = CacheControl.Builder().build()
private val DEFAULT_HEADERS: Headers = Headers.Builder().build()
private val DEFAULT_BODY: RequestBody = ByteArray(0).toRequestBody()

fun GET(
    url: String,
    headers: Headers = DEFAULT_HEADERS,
    cache: CacheControl = DEFAULT_CACHE_CONTROL,
): Request = Request.Builder()
    .url(url)
    .headers(headers)
    .cacheControl(cache)
    .build()

fun GET(
    url: HttpUrl,
    headers: Headers = DEFAULT_HEADERS,
    cache: CacheControl = DEFAULT_CACHE_CONTROL,
): Request = Request.Builder()
    .url(url)
    .headers(headers)
    .cacheControl(cache)
    .build()

fun POST(
    url: String,
    headers: Headers = DEFAULT_HEADERS,
    body: RequestBody = DEFAULT_BODY,
    cache: CacheControl = DEFAULT_CACHE_CONTROL,
): Request = Request.Builder()
    .url(url)
    .headers(headers)
    .post(body)
    .cacheControl(cache)
    .build()

fun Call.asObservable(): Observable<Response> =
    Observable.fromCallable(java.util.concurrent.Callable { clone().execute() })

fun Call.asObservableSuccess(): Observable<Response> = asObservable().doOnNext { response ->
    if (!response.isSuccessful) {
        val code = response.code
        val message = response.message
        response.close()
        throw Exception("HTTP $code $message")
    }
}

suspend fun Call.await(): Response = suspendCancellableCoroutine { continuation ->
    val call = clone()
    continuation.invokeOnCancellation { call.cancel() }
    try {
        continuation.resume(call.execute())
    } catch (e: Throwable) {
        continuation.resumeWithException(e)
    }
}

suspend fun Call.awaitSuccess(): Response {
    val response = await()
    if (!response.isSuccessful) {
        val code = response.code
        val message = response.message
        response.close()
        throw Exception("HTTP $code $message")
    }
    return response
}

/** Reads the body once and closes the response, for hosts that only want text. */
fun Response.bodyText(): String = use { it.body?.string().orEmpty() }

internal fun ResponseBody.quietClose() {
    try {
        close()
    } catch (_: Throwable) {
    }
}

/**
 * Extensions compiled against extensions-lib 1.4 call this to run a site's own
 * JavaScript. Best does not ship a JS engine; the call reports a clear failure
 * instead of a NoClassDefFoundError.
 */
class JavaScriptEngine(@Suppress("UNUSED_PARAMETER") context: Context) {
    suspend fun <T> evaluate(script: String): T =
        throw UnsupportedOperationException("JavaScript evaluation is not available in Best.")
}
