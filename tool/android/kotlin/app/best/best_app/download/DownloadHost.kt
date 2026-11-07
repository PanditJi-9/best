package app.best.best_app.download

import android.content.Context
import androidx.work.Constraints
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.flow.MutableStateFlow
import java.util.concurrent.atomic.AtomicInteger
import app.best.best_app.MainActivity

data class DownloadSnapshot(
    val ready: Boolean = false,
    val pending: Boolean = false,
    val wifiOnly: Boolean = false,
    val unitId: String = "",
    val title: String = "Best",
    val detail: String = "",
    val progress: Int = 0,
    val total: Int = 0,
    val pauseLabel: String = "Pause downloads",
) {
    val canFinish: Boolean get() = ready && !pending
}

/** No files or database writes live on this side of the boundary. */
object DownloadRuntime {
    const val WORK_NAME = "best-download-lifetime"
    val state = MutableStateFlow(DownloadSnapshot())
    val workerCount = AtomicInteger(0)
    private var channel: MethodChannel? = null
    private var dartReady = false
    private val actions = mutableListOf<Pair<String, String?>>()

    fun attach(channel: MethodChannel) {
        this.channel = channel
    }

    fun ready() {
        dartReady = true
        val waiting = actions.toList()
        actions.clear()
        waiting.forEach { dispatch(it.first, it.second) }
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
        dartReady = false
        state.value = DownloadSnapshot()
    }

    fun dispatch(action: String, unitId: String?) {
        val current = channel
        if (current == null || !dartReady) {
            actions.add(action to unitId)
            return
        }
        current.invokeMethod("notificationAction", mapOf(
            "action" to action, "unitId" to unitId,
        ))
    }

    fun failure(message: String) {
        channel?.invokeMethod("backgroundFailure", message.take(180))
    }
}

/**
 * Keeps the existing Dart queue alive. It never downloads a parallel copy.
 */
class DownloadHost(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        private const val CHANNEL = "app.best/background_download"
    }

    fun attach(messenger: BinaryMessenger) {
        val channel = MethodChannel(messenger, CHANNEL)
        DownloadRuntime.attach(channel)
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "ready" -> {
                DownloadRuntime.ready()
                result.success(true)
            }
            "updateDownloadState" -> {
                try {
                    val previous = DownloadRuntime.state.value
                    val next = DownloadSnapshot(
                        ready = true,
                        pending = call.argument<Boolean>("pending") == true,
                        wifiOnly = call.argument<Boolean>("wifiOnly") == true,
                        unitId = call.argument<String>("unitId") ?: "",
                        title = (call.argument<String>("title") ?: "Best").take(160),
                        detail = (call.argument<String>("detail") ?: "").take(240),
                        progress = (call.argument<Number>("progress")?.toInt() ?: 0).coerceAtLeast(0),
                        total = (call.argument<Number>("total")?.toInt() ?: 0).coerceAtLeast(0),
                        pauseLabel = (call.argument<String>("pauseLabel") ?: "Pause downloads").take(80),
                    )
                    DownloadRuntime.state.value = next
                    if (next.pending) MainActivity.requestDownloadsPermission()
                    if (next.pending && DownloadRuntime.workerCount.get() == 0) {
                        val constraints = Constraints.Builder()
                            .setRequiredNetworkType(if (next.wifiOnly)
                                NetworkType.UNMETERED else NetworkType.CONNECTED)
                            .build()
                        val work = OneTimeWorkRequestBuilder<DownloadWorker>()
                            .setConstraints(constraints).addTag("best-downloads").build()
                        WorkManager.getInstance(context).enqueueUniqueWork(
                            DownloadRuntime.WORK_NAME,
                            if (previous.wifiOnly != next.wifiOnly)
                                ExistingWorkPolicy.REPLACE else ExistingWorkPolicy.KEEP,
                            work,
                        )
                    }
                    result.success(true)
                } catch (error: Exception) {
                    result.error("BACKGROUND_UNAVAILABLE", error.javaClass.simpleName, null)
                }
            }

            else -> result.notImplemented()
        }
    }
}
