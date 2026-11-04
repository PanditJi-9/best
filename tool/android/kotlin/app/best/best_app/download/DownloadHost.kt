package app.best.best_app.download

import android.content.Context
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * MethodChannel host for WorkManager background downloads.
 */
class DownloadHost(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        private const val CHANNEL = "app.best/background_download"
    }

    fun attach(messenger: BinaryMessenger) {
        val channel = MethodChannel(messenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "enqueueDownload" -> {
                val unitId = call.argument<String>("unitId") ?: run {
                    result.error("INVALID_ARGS", "Missing unitId", null)
                    return
                }
                val mediaTitle = call.argument<String>("mediaTitle") ?: "Manga"
                val unitTitle = call.argument<String>("unitTitle") ?: "Chapter"
                val urlsJson = call.argument<String>("urlsJson") ?: "[]"
                val targetDir = call.argument<String>("targetDir") ?: ""

                val data = Data.Builder()
                    .putString(DownloadWorker.KEY_UNIT_ID, unitId)
                    .putString(DownloadWorker.KEY_MEDIA_TITLE, mediaTitle)
                    .putString(DownloadWorker.KEY_UNIT_TITLE, unitTitle)
                    .putString(DownloadWorker.KEY_PAGE_URLS_JSON, urlsJson)
                    .putString(DownloadWorker.KEY_TARGET_DIR, targetDir)
                    .build()

                val work = OneTimeWorkRequestBuilder<DownloadWorker>()
                    .setInputData(data)
                    .addTag("download")
                    .addTag(unitId)
                    .build()

                WorkManager.getInstance(context).enqueueUniqueWork(
                    "download_$unitId",
                    ExistingWorkPolicy.REPLACE,
                    work
                )
                result.success(true)
            }

            "cancelDownload" -> {
                val unitId = call.argument<String>("unitId") ?: run {
                    result.error("INVALID_ARGS", "Missing unitId", null)
                    return
                }
                WorkManager.getInstance(context).cancelUniqueWork("download_$unitId")
                result.success(true)
            }

            else -> result.notImplemented()
        }
    }
}
