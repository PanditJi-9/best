package app.best.best_app.playback

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.pm.PackageManager
import android.os.Build
import android.util.Rational
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class PlayerHost(private val activity: Activity) : MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null

    fun attach(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, "app.best/player").also {
            it.setMethodCallHandler(this)
        }
    }

    fun pipChanged(active: Boolean) {
        channel?.invokeMethod("pipChanged", active)
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    private fun supported(): Boolean = Build.VERSION.SDK_INT >= 26 &&
        activity.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pipSupported" -> result.success(supported())
            "enterPip" -> {
                if (!supported()) { result.success(false); return }
                try {
                    val raw = call.argument<Number>("aspectRatio")?.toDouble() ?: 16.0 / 9.0
                    val aspect = if (raw.isFinite()) raw.coerceIn(0.42, 2.38) else 16.0 / 9.0
                    val params = PictureInPictureParams.Builder()
                        .setAspectRatio(Rational((aspect * 1000).toInt(), 1000)).build()
                    result.success(activity.enterPictureInPictureMode(params))
                } catch (error: Exception) {
                    result.error("PIP_UNAVAILABLE", error.javaClass.simpleName, null)
                }
            }
            else -> result.notImplemented()
        }
    }
}
