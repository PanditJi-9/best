package app.best.best_app

import app.best.best_app.download.DownloadHost
import app.best.best_app.ext.ExtensionHost
import app.best.best_app.ocr.OcrHost
import app.best.best_app.security.BiometricHost
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterFragmentActivity() {

    companion object {
        /**
         * One host per process: it caches the loaded extension classes, which are
         * expensive to build and must stay valid while a chapter is open.
         */
        private var host: ExtensionHost? = null

        fun host(activity: MainActivity): ExtensionHost =
            host ?: ExtensionHost(activity.applicationContext).also { host = it }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        host(this).attach(flutterEngine.dartExecutor.binaryMessenger)
        OcrHost(applicationContext).attach(flutterEngine.dartExecutor.binaryMessenger)
        DownloadHost(applicationContext).attach(flutterEngine.dartExecutor.binaryMessenger)
        BiometricHost(this).attach(flutterEngine.dartExecutor.binaryMessenger)
    }
}
