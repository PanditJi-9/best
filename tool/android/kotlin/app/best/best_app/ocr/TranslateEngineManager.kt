package app.best.best_app.ocr

import com.google.android.gms.tasks.Tasks
import com.google.mlkit.common.model.DownloadConditions
import com.google.mlkit.common.model.RemoteModelManager
import com.google.mlkit.nl.translate.TranslateLanguage
import com.google.mlkit.nl.translate.TranslateRemoteModel
import com.google.mlkit.nl.translate.Translation
import com.google.mlkit.nl.translate.Translator
import com.google.mlkit.nl.translate.TranslatorOptions
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONArray
import java.net.URLEncoder
import java.util.concurrent.TimeUnit

/**
 * English -> Arabic translation with a local-first policy.
 *
 * Both ML Kit language models are optional downloads. An online reader can use
 * the HTTP client immediately while the models download in the background; once
 * those models are present, every page works with no connection. Requests are
 * bounded so a page with ten bubbles does not create ten competing engines, and
 * a failed network attempt opens a short circuit instead of making every bubble
 * wait for the same timeout.
 */
class TranslateEngineManager {

    companion object {
        private const val LOCAL_TIMEOUT_MS = 4_000L
        private const val MODEL_DOWNLOAD_TIMEOUT_MS = 60_000L
        private const val HTTP_COOLDOWN_MS = 30_000L
        private const val MODEL_RETRY_MS = 5 * 60_000L
        private const val MAX_CONCURRENT_TRANSLATIONS = 3
    }

    private val options = TranslatorOptions.Builder()
        .setSourceLanguage(TranslateLanguage.ENGLISH)
        .setTargetLanguage(TranslateLanguage.ARABIC)
        .build()

    private val translator: Translator by lazy {
        Translation.getClient(options)
    }

    private val modelManager = RemoteModelManager.getInstance()
    private val englishModel =
        TranslateRemoteModel.Builder(TranslateLanguage.ENGLISH).build()
    private val arabicModel =
        TranslateRemoteModel.Builder(TranslateLanguage.ARABIC).build()

    private val modelLock = Mutex()
    private val translationSlots = Semaphore(MAX_CONCURRENT_TRANSLATIONS)

    @Volatile private var modelReady = false
    @Volatile private var modelChecked = false
    @Volatile private var lastDownloadAttemptMs = 0L
    @Volatile private var httpBlockedUntilMs = 0L

    private val httpClient = OkHttpClient.Builder()
        .connectTimeout(4, TimeUnit.SECONDS)
        .readTimeout(6, TimeUnit.SECONDS)
        .callTimeout(9, TimeUnit.SECONDS)
        .retryOnConnectionFailure(true)
        .build()

    /** True only when both the source and target models are on the device. */
    suspend fun isModelDownloaded(): Boolean = withContext(Dispatchers.IO) {
        val installed = modelsInstalled()
        if (installed) modelReady = true
        modelChecked = true
        installed
    }

    /**
     * Downloads both models. Callers should not block a page on this; it is the
     * background preparation that turns online translation into offline
     * translation after the first run.
     */
    suspend fun downloadModel(force: Boolean = false): Boolean = withContext(Dispatchers.IO) {
        if (modelReady) return@withContext true
        val now = System.currentTimeMillis()
        if (!force && now - lastDownloadAttemptMs < MODEL_RETRY_MS) {
            return@withContext false
        }
        lastDownloadAttemptMs = now
        modelLock.withLock {
            if (modelReady) return@withLock true
            val installed = withTimeoutOrNull(MODEL_DOWNLOAD_TIMEOUT_MS) {
                try {
                    Tasks.await(
                        translator.downloadModelIfNeeded(
                            DownloadConditions.Builder().build()
                        )
                    )
                    true
                } catch (_: Exception) {
                    false
                }
            } ?: false
            modelReady = installed
            modelChecked = true
            installed
        }
    }

    suspend fun translate(text: String): String = translationSlots.withPermit {
        withContext(Dispatchers.IO) { translateInternal(text) }
    }

    private suspend fun translateInternal(text: String): String {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return ""

        // A reader who already downloaded the models gets the local engine even
        // after a process restart. Checking once avoids a model-manager query on
        // every bubble.
        if (!modelReady && !modelChecked) {
            modelReady = modelsInstalled()
            modelChecked = true
        }

        if (modelReady) {
            val local = withTimeoutOrNull(LOCAL_TIMEOUT_MS) {
                try {
                    Tasks.await(translator.translate(trimmed))
                } catch (_: Exception) {
                    null
                }
            }
            if (!local.isNullOrBlank()) return local
        }

        return translateViaHttp(trimmed)
    }

    private suspend fun modelsInstalled(): Boolean = try {
        Tasks.await(modelManager.isModelDownloaded(englishModel)) &&
            Tasks.await(modelManager.isModelDownloaded(arabicModel))
    } catch (_: Exception) {
        false
    }

    /**
     * The Google web endpoint is the emergency path when the offline model is
     * absent or broken. A short circuit prevents an offline phone from paying
     * a timeout for every bubble in a page.
     */
    private fun translateViaHttp(text: String): String {
        if (System.currentTimeMillis() < httpBlockedUntilMs) return ""

        val encoded = URLEncoder.encode(text, "UTF-8")
        val url =
            "https://translate.googleapis.com/translate_a/single?client=gtx&sl=en&tl=ar&dt=t&q=$encoded"
        val request = Request.Builder()
            .url(url)
            .header("Accept", "application/json")
            // The public endpoint is picky about non-browser agents.
            .header("User-Agent", "Mozilla/5.0")
            .build()

        return try {
            httpClient.newCall(request).execute().use { response ->
                if (!response.isSuccessful) {
                    httpBlockedUntilMs =
                        System.currentTimeMillis() + HTTP_COOLDOWN_MS
                    return ""
                }
                val body = response.body?.string() ?: return ""
                val json = JSONArray(body)
                val sentences = json.optJSONArray(0) ?: return ""
                val result = StringBuilder()
                for (i in 0 until sentences.length()) {
                    val sentence = sentences.optJSONArray(i)
                    if (sentence != null) result.append(sentence.optString(0))
                }
                val translated = result.toString().trim()
                if (translated.isNotEmpty()) httpBlockedUntilMs = 0L
                translated
            }
        } catch (_: Exception) {
            httpBlockedUntilMs = System.currentTimeMillis() + HTTP_COOLDOWN_MS
            ""
        }
    }

    fun close() {
        translator.close()
    }
}
