package app.best.best_app.download

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters
import app.best.best_app.BestEngine
import app.best.best_app.MainActivity
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout

/**
 * A persisted foreground lifetime for the one existing Dart queue. A cold
 * restart opens SQLite and resumes that queue through the normal bootstrap.
 * Result.success() means this lifetime ended, not that any chapter succeeded:
 * only DownloadManager's verified SQLite transitions can say that.
 */
class DownloadWorker(
    private val context: Context,
    params: WorkerParameters
) : CoroutineWorker(context, params) {

    companion object {
        const val CHANNEL_ID = "best_downloads_channel"
        const val NOTIFICATION_ID = 8001

    }

    private val notificationManager =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    @OptIn(FlowPreview::class)
    override suspend fun doWork(): Result {
        DownloadRuntime.workerCount.incrementAndGet()
        try {
            createNotificationChannel()
            setForeground(createForegroundInfo(DownloadRuntime.state.value))
            withContext(Dispatchers.Main) { BestEngine.get(context) }
            withTimeout(6 * 60 * 60 * 1000L) {
                coroutineScope {
                    val updates = launch {
                        DownloadRuntime.state.collect { snapshot ->
                            if (snapshot.ready && snapshot.pending) {
                                notificationManager.notify(
                                    NOTIFICATION_ID, buildNotification(snapshot),
                                )
                            }
                        }
                    }
                    // Debounce before filtering: new queued work must cancel an
                    // in-flight idle timeout instead of ending its foreground life.
                    DownloadRuntime.state.debounce(1200).first {
                        it.canFinish
                    }
                    updates.cancel()
                }
            }
            return Result.success()
        } catch (cancelled: kotlinx.coroutines.CancellationException) {
            throw cancelled
        } catch (error: Exception) {
            withContext(Dispatchers.Main) {
                DownloadRuntime.failure(error.javaClass.simpleName)
            }
            return Result.retry()
        } finally {
            DownloadRuntime.workerCount.decrementAndGet()
            withContext(kotlinx.coroutines.NonCancellable + Dispatchers.Main) {
                if (DownloadRuntime.workerCount.get() == 0) {
                    notificationManager.cancel(NOTIFICATION_ID)
                    BestEngine.releaseIfIdle()
                }
            }
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "تنزيلات الفصول (Downloads)",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "إشعار تقدم تنزيل الفصول في الخلفية"
                setShowBadge(false)
            }
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun createForegroundInfo(snapshot: DownloadSnapshot): ForegroundInfo {
        val notification = buildNotification(snapshot)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ForegroundInfo(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            ForegroundInfo(NOTIFICATION_ID, notification)
        }
    }

    private fun buildNotification(snapshot: DownloadSnapshot): android.app.Notification {
        val pauseIntent = Intent(context, DownloadNotificationReceiver::class.java).apply {
            action = DownloadNotificationReceiver.ACTION_PAUSE
        }
        val pause = PendingIntent.getBroadcast(
            context,
            8001,
            pauseIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val open = PendingIntent.getActivity(
            context, 8002,
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("best_open_downloads", true)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        return NotificationCompat.Builder(context, CHANNEL_ID)
            .setContentTitle(snapshot.title)
            .setContentText(snapshot.detail)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentIntent(open)
            .setProgress(snapshot.total, snapshot.progress.coerceAtMost(snapshot.total), snapshot.total <= 0)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .addAction(android.R.drawable.ic_media_pause, snapshot.pauseLabel, pause)
            .build()
    }
}
