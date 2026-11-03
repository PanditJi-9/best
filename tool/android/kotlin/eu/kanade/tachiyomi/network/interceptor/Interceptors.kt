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
        val challenge = response.header("cf-mitigated") == "challenge" ||
            (response.code in listOf(403, 503) &&
                response.header("server")?.contains("cloudflare", ignoreCase = true) == true &&
                response.peekBody(8192).string().let {
                    it.contains("cf-chl-") || it.contains("/cdn-cgi/challenge-platform/")
                })
        if (challenge) {
            response.close()
            throw IOException("This site requires Cloudflare browser verification, which is not available in Best yet.")
        }
        return response
    }
}
