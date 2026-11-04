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
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONArray
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.TimeUnit

/**
 * Background chapter downloader using WorkManager foreground service.
 * Continues downloading even after app swipe-kill or screen off.
 * Ported from HikariManga DownloadChapterWorker.
 */
class DownloadWorker(
    private val context: Context,
    params: WorkerParameters
) : CoroutineWorker(context, params) {

    companion object {
        const val CHANNEL_ID = "best_downloads_channel"
        const val NOTIFICATION_ID = 8001

        const val KEY_UNIT_ID = "unit_id"
        const val KEY_MEDIA_TITLE = "media_title"
        const val KEY_UNIT_TITLE = "unit_title"
        const val KEY_PAGE_URLS_JSON = "page_urls_json"
        const val KEY_TARGET_DIR = "target_dir"
        const val KEY_HEADERS_JSON = "headers_json"
    }

    private val notificationManager =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        val unitId = inputData.getString(KEY_UNIT_ID) ?: return@withContext Result.failure()
        val mediaTitle = inputData.getString(KEY_MEDIA_TITLE) ?: "Manga"
        val unitTitle = inputData.getString(KEY_UNIT_TITLE) ?: "Chapter"
        val urlsJson = inputData.getString(KEY_PAGE_URLS_JSON) ?: return@withContext Result.failure()
        val targetDirStr = inputData.getString(KEY_TARGET_DIR) ?: return@withContext Result.failure()

        val targetDir = File(targetDirStr).apply { mkdirs() }
        val urls = try {
            val arr = JSONArray(urlsJson)
            (0 until arr.length()).map { arr.getString(it) }
        } catch (e: Exception) {
            return@withContext Result.failure()
        }

        createNotificationChannel()

        val foregroundInfo = createForegroundInfo(unitId, mediaTitle, unitTitle, 0, urls.size)
        setForeground(foregroundInfo)

        for (i in urls.indices) {
            if (isStopped) {
                return@withContext Result.retry()
            }

            val pageUrl = urls[i]
            val destFile = File(targetDir, String.format("%03d.jpg", i + 1))

            if (!destFile.exists() || destFile.length() == 0L) {
                val downloaded = downloadPage(pageUrl, destFile)
                if (!downloaded && !isStopped) {
                    // One retry
                    downloadPage(pageUrl, destFile)
                }
            }

            updateProgressNotification(unitId, mediaTitle, unitTitle, i + 1, urls.size)
        }

        notificationManager.cancel(NOTIFICATION_ID)
        Result.success()
    }

    private fun downloadPage(url: String, dest: File): Boolean {
        return try {
            val req = Request.Builder().url(url).build()
            client.newCall(req).execute().use { response ->
                if (!response.isSuccessful) return false
                val bytes = response.body?.bytes() ?: return false
                FileOutputStream(dest).use { it.write(bytes) }
                true
            }
        } catch (e: Exception) {
            false
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

    private fun createForegroundInfo(
        unitId: String,
        mediaTitle: String,
        unitTitle: String,
        progress: Int,
        total: Int
    ): ForegroundInfo {
        val notification = buildNotification(unitId, mediaTitle, unitTitle, progress, total)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ForegroundInfo(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            ForegroundInfo(NOTIFICATION_ID, notification)
        }
    }

    private fun updateProgressNotification(
        unitId: String,
        mediaTitle: String,
        unitTitle: String,
        progress: Int,
        total: Int
    ) {
        val notification = buildNotification(unitId, mediaTitle, unitTitle, progress, total)
        notificationManager.notify(NOTIFICATION_ID, notification)
    }

    private fun buildNotification(
        unitId: String,
        mediaTitle: String,
        unitTitle: String,
        progress: Int,
        total: Int
    ): android.app.Notification {
        val cancelIntent = Intent(context, DownloadNotificationReceiver::class.java).apply {
            action = DownloadNotificationReceiver.ACTION_CANCEL
            putExtra(DownloadNotificationReceiver.EXTRA_UNIT_ID, unitId)
        }
        val cancelPendingIntent = PendingIntent.getBroadcast(
            context,
            unitId.hashCode(),
            cancelIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val title = "$mediaTitle — $unitTitle"
        val content = if (total > 0) "جاري التحميل: $progress / $total صفحة" else "جاري بدء التحميل..."

        return NotificationCompat.Builder(context, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(content)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setProgress(total, progress, total <= 0)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "إلغاء", cancelPendingIntent)
            .build()
    }
}
