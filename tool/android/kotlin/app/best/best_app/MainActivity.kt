package app.best.best_app

import app.best.best_app.ext.ExtensionHost
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

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
    }
}
