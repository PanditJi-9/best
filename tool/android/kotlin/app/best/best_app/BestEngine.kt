package app.best.best_app

import android.content.Context
import android.os.Looper
import android.os.Handler
import app.best.best_app.download.DownloadHost
import app.best.best_app.download.DownloadRuntime
import app.best.best_app.ext.ExtensionHost
import app.best.best_app.ocr.OcrHost
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * Exactly one Dart isolate and one download writer per process. WorkManager can
 * boot it without an Activity; reopening the app attaches to that same engine.
 */
object BestEngine {
    private var engine: FlutterEngine? = null
    private var extensionHost: ExtensionHost? = null
    var activityAttached = false

    fun extensions(context: Context): ExtensionHost =
        extensionHost ?: ExtensionHost(context.applicationContext).also {
            extensionHost = it
        }

    fun get(context: Context): FlutterEngine {
        check(Looper.myLooper() == Looper.getMainLooper())
        engine?.let { return it }
        val app = context.applicationContext
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(app)
        loader.ensureInitializationComplete(app, null)
        val created = FlutterEngine(app)
        engine = created
        extensions(app).attach(created.dartExecutor.binaryMessenger)
        OcrHost(app).attach(created.dartExecutor.binaryMessenger)
        DownloadHost(app).attach(created.dartExecutor.binaryMessenger)
        created.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint.createDefault(),
        )
        return created
    }

    fun releaseIfIdle() {
        check(Looper.myLooper() == Looper.getMainLooper())
        if (activityAttached || DownloadRuntime.workerCount.get() > 0 ||
            DownloadRuntime.state.value.pending) return
        val previous = engine ?: return
        // Give page/player progress and preference writes a short flush window.
        Handler(Looper.getMainLooper()).postDelayed({
            if (engine === previous && !activityAttached &&
                DownloadRuntime.workerCount.get() == 0 &&
                !DownloadRuntime.state.value.pending) {
                engine = null
                DownloadRuntime.detach()
                previous.destroy()
            }
        }, 2000)
    }
}
