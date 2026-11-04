package app.best.best_app.webtoon

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapRegionDecoder
import android.graphics.Rect
import android.os.Build
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import kotlin.math.min

/**
 * Intelligent Webtoon image slicer for handling extremely long vertical strips.
 * Prevents OpenGL texture limit crashes and OutOfMemory errors by splitting strips
 * into 2048px vertical tiles using [BitmapRegionDecoder].
 * Ported from HikariManga 1.4.2.
 */
object WebtoonDecoder {
    const val SLICE_HEIGHT = 2048
    const val TRIGGER_THRESHOLD = 3000

    data class SliceInfo(
        val index: Int,
        val top: Int,
        val height: Int,
        val width: Int,
        val filePath: String
    )

    /**
     * Checks if image needs slicing.
     */
    fun shouldSlice(bytes: ByteArray): Boolean {
        val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
        return options.outHeight > TRIGGER_THRESHOLD ||
                (options.outWidth.toLong() * options.outHeight.toLong() * 4 > 80_000_000L)
    }

    /**
     * Slices a long webtoon image into multiple temporary files.
     */
    fun sliceImage(bytes: ByteArray, cacheDir: File, pageIdentifier: String): List<SliceInfo> {
        val decoder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            BitmapRegionDecoder.newInstance(bytes, 0, bytes.size)
        } else {
            @Suppress("DEPRECATION")
            BitmapRegionDecoder.newInstance(bytes, 0, bytes.size, false)
        } ?: return emptyList()

        val width = decoder.width
        val height = decoder.height

        // Downsample if image is outrageously large
        var sampleSize = 1
        while ((width.toLong() * height.toLong() * 2) / (sampleSize * sampleSize) > 60_000_000L) {
            sampleSize *= 2
        }

        val options = BitmapFactory.Options().apply {
            inPreferredConfig = Bitmap.Config.RGB_565
            inSampleSize = sampleSize
        }

        val sliceTargetHeight = SLICE_HEIGHT * sampleSize
        val slices = mutableListOf<SliceInfo>()

        var y = 0
        var sliceIdx = 0
        while (y < height) {
            val chunkH = min(sliceTargetHeight, height - y)
            val rect = Rect(0, y, width, y + chunkH)

            val bitmapChunk = try {
                decoder.decodeRegion(rect, options)
            } catch (e: Throwable) {
                null
            }

            if (bitmapChunk != null) {
                val sliceFile = File(cacheDir, "slice_${pageIdentifier}_$sliceIdx.jpg")
                try {
                    FileOutputStream(sliceFile).use { out ->
                        bitmapChunk.compress(Bitmap.CompressFormat.JPEG, 92, out)
                    }
                    slices.add(
                        SliceInfo(
                            index = sliceIdx,
                            top = y,
                            height = chunkH,
                            width = width,
                            filePath = sliceFile.absolutePath
                        )
                    )
                } finally {
                    bitmapChunk.recycle()
                }
            }

            y += chunkH
            sliceIdx++
        }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            @Suppress("DEPRECATION")
            decoder.recycle()
        }

        return slices
    }
}
