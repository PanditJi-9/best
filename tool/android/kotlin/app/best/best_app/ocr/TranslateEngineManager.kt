package app.best.best_app.ocr

import android.content.Context
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.common.model.DownloadConditions
import com.google.mlkit.common.model.RemoteModelManager
import com.google.mlkit.nl.translate.TranslateLanguage
import com.google.mlkit.nl.translate.TranslateRemoteModel
import com.google.mlkit.nl.translate.Translation
import com.google.mlkit.nl.translate.Translator
import com.google.mlkit.nl.translate.TranslatorOptions
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONArray
import java.net.URLEncoder
import java.util.concurrent.TimeUnit

/**
 * On-device translation engine using Google ML Kit English -> Arabic,
 * with model management and HTTP fallback. Ported from HikariManga 1.4.2.
 */
class TranslateEngineManager(private val context: Context) {

    private val options = TranslatorOptions.Builder()
        .setSourceLanguage(TranslateLanguage.ENGLISH)
        .setTargetLanguage(TranslateLanguage.ARABIC)
        .build()

    private val translator: Translator by lazy {
        Translation.getClient(options)
    }

    private val modelManager = RemoteModelManager.getInstance()
    private val arabicModel = TranslateRemoteModel.Builder(TranslateLanguage.ARABIC).build()

    private val httpClient = OkHttpClient.Builder()
        .connectTimeout(5, TimeUnit.SECONDS)
        .readTimeout(8, TimeUnit.SECONDS)
        .build()

    suspend fun isModelDownloaded(): Boolean = withContext(Dispatchers.IO) {
        try {
            Tasks.await(modelManager.isModelDownloaded(arabicModel))
        } catch (e: Exception) {
            false
        }
    }

    suspend fun downloadModel(): Boolean = withContext(Dispatchers.IO) {
        val conditions = DownloadConditions.Builder().build()
        try {
            Tasks.await(translator.downloadModelIfNeeded(conditions))
            true
        } catch (e: Exception) {
            false
        }
    }

    suspend fun translate(text: String): String = withContext(Dispatchers.IO) {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return@withContext ""

        // 1. Try ML Kit on-device translation with 5 second timeout
        val mlKitResult = withTimeoutOrNull(5000L) {
            try {
                Tasks.await(translator.translate(trimmed))
            } catch (e: Exception) {
                null
            }
        }

        if (!mlKitResult.isNullOrBlank()) {
            return@withContext mlKitResult
        }

        // 2. HTTP Fallback (client API)
        val httpResult = translateViaHttp(trimmed)
        if (httpResult.isNotBlank()) {
            return@withContext httpResult
        }

        return@withContext ""
    }

    private fun translateViaHttp(text: String): String {
        return try {
            val encoded = URLEncoder.encode(text, "UTF-8")
            val url = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=en&tl=ar&dt=t&q=$encoded"
            val request = Request.Builder()
                .url(url)
                .header("User-Agent", "Mozilla/5.0")
                .build()

            httpClient.newCall(request).execute().use { response ->
                if (!response.isSuccessful) return ""
                val body = response.body?.string() ?: return ""
                val json = JSONArray(body)
                val sentences = json.optJSONArray(0) ?: return ""
                val sb = StringBuffer()
                for (i in 0 until sentences.length()) {
                    val s = sentences.optJSONArray(i)
                    if (s != null) {
                        sb.append(s.optString(0))
                    }
                }
                sb.toString().trim()
            }
        } catch (e: Exception) {
            ""
        }
    }

    fun close() {
        translator.close()
    }
}
