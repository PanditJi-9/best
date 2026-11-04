package app.best.best_app.ocr

import android.content.Context
import android.graphics.BitmapFactory
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Bridges Android ML Kit OCR and Translation to Flutter through MethodChannel.
 */
class OcrHost(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        private const val CHANNEL = "app.best/ocr"
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val ocrManager = OcrManager()
    private val translateManager = TranslateEngineManager(context)

    fun attach(messenger: BinaryMessenger) {
        val channel = MethodChannel(messenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "recognizeBubbles" -> {
                val bytes = call.argument<ByteArray>("bytes")
                if (bytes == null || bytes.isEmpty()) {
                    result.error("INVALID_ARGS", "Missing image bytes", null)
                    return
                }

                scope.launch {
                    try {
                        val bitmap = withContext(Dispatchers.IO) {
                            BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                        }
                        if (bitmap == null) {
                            result.error("DECODE_FAILED", "Failed to decode bitmap from bytes", null)
                            return@launch
                        }

                        val bubbles = ocrManager.processBitmap(bitmap)
                        val response = mapOf(
                            "width" to bitmap.width,
                            "height" to bitmap.height,
                            "bubbles" to bubbles
                        )
                        bitmap.recycle()
                        result.success(response)
                    } catch (e: Exception) {
                        result.error("OCR_ERROR", e.message, null)
                    }
                }
            }

            "translateText" -> {
                val text = call.argument<String>("text") ?: ""
                scope.launch {
                    try {
                        val translated = translateManager.translate(text)
                        result.success(translated)
                    } catch (e: Exception) {
                        result.error("TRANSLATE_ERROR", e.message, null)
                    }
                }
            }

            "isModelDownloaded" -> {
                scope.launch {
                    val downloaded = translateManager.isModelDownloaded()
                    result.success(downloaded)
                }
            }

            "downloadModel" -> {
                scope.launch {
                    val success = translateManager.downloadModel()
                    result.success(success)
                }
            }

            "shouldSliceWebtoon" -> {
                val bytes = call.argument<ByteArray>("bytes") ?: byteArrayOf()
                val should = app.best.best_app.webtoon.WebtoonDecoder.shouldSlice(bytes)
                result.success(should)
            }

            "sliceWebtoon" -> {
                val bytes = call.argument<ByteArray>("bytes")
                val pageId = call.argument<String>("pageId") ?: "page_${System.currentTimeMillis()}"
                if (bytes == null || bytes.isEmpty()) {
                    result.error("INVALID_ARGS", "Missing image bytes", null)
                    return
                }
                scope.launch {
                    try {
                        val slices = withContext(Dispatchers.IO) {
                            app.best.best_app.webtoon.WebtoonDecoder.sliceImage(bytes, context.cacheDir, pageId)
                        }
                        val mapped = slices.map {
                            mapOf(
                                "index" to it.index,
                                "top" to it.top,
                                "height" to it.height,
                                "width" to it.width,
                                "filePath" to it.filePath
                            )
                        }
                        result.success(mapped)
                    } catch (e: Exception) {
                        result.error("SLICE_ERROR", e.message, null)
                    }
                }
            }

            else -> result.notImplemented()
        }
    }
}
