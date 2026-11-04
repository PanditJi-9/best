package app.best.best_app.download

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.work.WorkManager

/**
 * Handles action buttons directly from the Android download notification
 * (Pause, Resume, Cancel). Ported from HikariManga DownloadActionsReceiver.
 */
class DownloadNotificationReceiver : BroadcastReceiver() {

    companion object {
        const val ACTION_PAUSE = "app.best.download.PAUSE"
        const val ACTION_RESUME = "app.best.download.RESUME"
        const val ACTION_CANCEL = "app.best.download.CANCEL"
        const val EXTRA_UNIT_ID = "extra_unit_id"
    }

    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        val unitId = intent.getStringExtra(EXTRA_UNIT_ID) ?: return

        when (action) {
            ACTION_PAUSE -> {
                WorkManager.getInstance(context).cancelUniqueWork("download_$unitId")
            }
            ACTION_RESUME -> {
                // Resume download work
            }
            ACTION_CANCEL -> {
                WorkManager.getInstance(context).cancelUniqueWork("download_$unitId")
            }
        }
    }
}
