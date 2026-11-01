package eu.kanade.tachiyomi.network

import okhttp3.CacheControl
import okhttp3.Headers
import okhttp3.HttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response

/**
 * The request builders every extension calls.
 *
 * The file name is part of the ABI: an extension compiled against the real
 * `source-api` emits `invokestatic eu/kanade/tachiyomi/network/RequestsKt->GET`,
 * so these must live in `Requests.kt` and nowhere else. Kotlin names the class
 * after the file, which is why the builders are not kept in `Network.kt`.
 */

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

fun POST(
    url: HttpUrl,
    headers: Headers = DEFAULT_HEADERS,
    body: RequestBody = DEFAULT_BODY,
    cache: CacheControl = DEFAULT_CACHE_CONTROL,
): Request = Request.Builder()
    .url(url)
    .headers(headers)
    .post(body)
    .cacheControl(cache)
    .build()

/**
 * A one-shot GET that hands back the response.
 *
 * Newer extensions (the v16 Aniyomi line) call `client.get(url, headers)` instead
 * of building a request and awaiting it, so both styles have to exist. The
 * receiver is the source's own client, which is why this cannot live on a
 * top-level object.
 */
suspend fun OkHttpClient.get(
    url: String,
    headers: Headers = DEFAULT_HEADERS,
    cache: CacheControl = DEFAULT_CACHE_CONTROL,
): Response = newCall(GET(url, headers, cache)).await()

suspend fun OkHttpClient.get(
    url: HttpUrl,
    headers: Headers = DEFAULT_HEADERS,
    cache: CacheControl = DEFAULT_CACHE_CONTROL,
): Response = newCall(GET(url, headers, cache)).await()
