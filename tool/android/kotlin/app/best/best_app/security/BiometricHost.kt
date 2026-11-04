package app.best.best_app.security

import android.content.Context
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class BiometricHost(
    private val activity: FragmentActivity
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val CHANNEL = "app.best/biometric"
    }

    private var channel: MethodChannel? = null

    fun attach(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "canAuthenticate" -> {
                try {
                    val biometricManager = BiometricManager.from(activity)
                    val authenticators = BiometricManager.Authenticators.BIOMETRIC_STRONG or
                            BiometricManager.Authenticators.DEVICE_CREDENTIAL
                    val canAuth = biometricManager.canAuthenticate(authenticators) == BiometricManager.BIOMETRIC_SUCCESS
                    result.success(canAuth)
                } catch (e: Exception) {
                    result.success(false)
                }
            }
            "authenticate" -> {
                val title = call.argument<String>("title") ?: "تأكيد الهوية"
                val subtitle = call.argument<String>("subtitle") ?: "استخدم بصمة الإصبع أو رمز القفل للوصول"

                try {
                    val executor = ContextCompat.getMainExecutor(activity)
                    val promptInfo = BiometricPrompt.PromptInfo.Builder()
                        .setTitle(title)
                        .setSubtitle(subtitle)
                        .setAllowedAuthenticators(
                            BiometricManager.Authenticators.BIOMETRIC_STRONG or
                            BiometricManager.Authenticators.DEVICE_CREDENTIAL
                        )
                        .build()

                    val prompt = BiometricPrompt(activity, executor, object : BiometricPrompt.AuthenticationCallback() {
                        override fun onAuthenticationSucceeded(authResult: BiometricPrompt.AuthenticationResult) {
                            super.onAuthenticationSucceeded(authResult)
                            result.success(true)
                        }

                        override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                            super.onAuthenticationError(errorCode, errString)
                            result.success(false)
                        }

                        override fun onAuthenticationFailed() {
                            super.onAuthenticationFailed()
                            // User can retry until error or success
                        }
                    })

                    prompt.authenticate(promptInfo)
                } catch (e: Exception) {
                    result.error("BIOMETRIC_ERROR", e.message, null)
                }
            }
            else -> result.notImplemented()
        }
    }
}
