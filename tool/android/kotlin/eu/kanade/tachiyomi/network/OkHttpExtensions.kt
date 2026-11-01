package eu.kanade.tachiyomi.network

import kotlinx.coroutines.suspendCancellableCoroutine
import okhttp3.Call
import okhttp3.Response
import rx.Observable
import java.util.concurrent.Callable
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * Rx and coroutine wrappers over an OkHttp call.
 *
 * Same rule as `Requests.kt`: the extension emits
 * `eu/kanade/tachiyomi/network/OkHttpExtensionsKt->awaitSuccess`, so the file
 * name is fixed by the ABI.
 */

fun Call.asObservable(): Observable<Response> =
    Observable.fromCallable(Callable { clone().execute() })

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
