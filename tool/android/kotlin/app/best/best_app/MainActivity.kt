package app.best.best_app

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Build
import android.Manifest
import android.content.pm.PackageManager
import java.lang.ref.WeakReference
import androidx.lifecycle.Lifecycle
import app.best.best_app.download.DownloadRuntime
import app.best.best_app.ext.ExtensionHost
import app.best.best_app.security.BiometricHost
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterFragmentActivity() {

    companion object {
        private var foregroundActivity = WeakReference<MainActivity>(null)
        private var notificationPermissionRequested = false

        fun requestDownloadsPermission() {
            val activity = foregroundActivity.get() ?: return
            if (Build.VERSION.SDK_INT < 33 || notificationPermissionRequested ||
                !activity.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED) ||
                activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) return
            notificationPermissionRequested = true
            activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 8000)
        }
        /**
         * One host per process: it caches the loaded extension classes, which are
         * expensive to build and must stay valid while a chapter is open.
         */
        fun host(activity: MainActivity): ExtensionHost =
            BestEngine.extensions(activity.applicationContext)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        BestEngine.activityAttached = true
        foregroundActivity = WeakReference(this)
        super.onCreate(savedInstanceState)
        handleNotificationIntent(intent)
    }

    override fun provideFlutterEngine(context: Context): FlutterEngine =
        BestEngine.get(context)

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        BiometricHost(this).attach(flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleNotificationIntent(intent)
    }

    private fun handleNotificationIntent(intent: Intent?) {
        if (intent?.getBooleanExtra("best_open_downloads", false) == true) {
            intent.removeExtra("best_open_downloads")
            DownloadRuntime.dispatch("open", null)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        if (foregroundActivity.get() === this) {
            foregroundActivity.clear()
            BestEngine.activityAttached = false
        }
        BestEngine.releaseIfIdle()
    }
}
