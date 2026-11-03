package eu.kanade.tachiyomi.network.interceptor

import eu.kanade.tachiyomi.network.DEFAULT_USER_AGENT
import okhttp3.Interceptor
import okhttp3.Response
import java.io.IOException

/** First in the chain: source interceptors must not crash OkHttp's dispatcher. */
class UncaughtExceptionInterceptor : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response = try {
        chain.proceed(chain.request())
    } catch (error: Exception) {
        if (error is IOException) throw error
        throw IOException(error)
    }
}

class UserAgentInterceptor : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        val original = chain.request()
        val request = if (original.header("User-Agent").isNullOrBlank()) {
            original.newBuilder().header("User-Agent", DEFAULT_USER_AGENT).build()
        } else original
        return chain.proceed(request)
    }
}

/**
 * Compatible network boundary, not a pretend challenge solver. Best has no
 * browser verification flow yet; preserve normal responses and report real
 * challenges clearly without retries, fake success, or disabling TLS checks.
 */
class CloudflareInterceptor : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        val response = chain.proceed(chain.request())
        if (!isBrowserChallenge(response)) return response
        // Closing a response whose body is already unusable must not replace the
        // challenge with a crash of its own.
        runCatching { response.close() }
        throw IOException(CHALLENGE)
    }

    private fun isBrowserChallenge(response: Response): Boolean {
        // Modern Cloudflare sets this on every managed challenge, including a
        // 200 response, so it is checked before the body is touched at all.
        if (response.header("cf-mitigated")?.equals("challenge", ignoreCase = true) == true) {
            return true
        }
        if (response.code !in REFUSALS) return false
        if (response.header("server")?.contains("cloudflare", ignoreCase = true) != true) {
            return false
        }
        return try {
            val body = response.peekBody(SNIFF_BYTES).string()
            body.contains("cf-chl-") ||
                body.contains("/cdn-cgi/challenge-platform/") ||
                body.contains("Just a moment")
        } catch (_: Exception) {
            // Run 41627263558: a retried call handed this interceptor a response
            // whose body was already closed, so sniffing it threw
            // IllegalStateException("closed") and a Cloudflare refusal became a
            // broken source. The refusal code plus the Cloudflare server header
            // already identify the answer, so report it as a challenge.
            true
        }
    }

    private companion object {
        const val CHALLENGE =
            "This site requires Cloudflare browser verification, which is not available in Best yet."
        const val SNIFF_BYTES = 8192L
        val REFUSALS = listOf(403, 503)
    }
}
