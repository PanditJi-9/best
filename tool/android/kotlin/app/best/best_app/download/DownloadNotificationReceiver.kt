package app.best.best_app.download

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import app.best.best_app.BestEngine

/**
 * Notification commands reach the same Dart manager as the Downloads screen.
 * A notification action never deletes stored pages without confirmation.
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
        val unitId = intent.getStringExtra(EXTRA_UNIT_ID)
        if (action != ACTION_PAUSE && action != ACTION_RESUME && action != ACTION_CANCEL) return
        Handler(Looper.getMainLooper()).post {
            BestEngine.get(context)
            DownloadRuntime.dispatch(when (action) {
                ACTION_PAUSE -> "pause"
                ACTION_RESUME -> "resume"
                else -> "stop"
            }, unitId)
        }
    }
}
