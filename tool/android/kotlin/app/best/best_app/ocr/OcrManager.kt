package app.best.best_app.ocr

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Rect
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.Text
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlin.math.max
import kotlin.math.min

/**
 * Android OCR engine using ML Kit Latin text recognition with image tiling and
 * bubble color sampling. Ported from HikariManga 1.4.2.
 */
class OcrManager {

    private val recognizer: TextRecognizer by lazy {
        TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
    }

    companion object {
        const val OCR_TILE_THRESHOLD_PX = 2500
        const val OCR_TILE_HEIGHT_PX = 1600
        const val OCR_TILE_OVERLAP_PX = 250
    }

    data class BubbleColors(
        val bgHex: String,
        val bgGradientEndHex: String?,
        val textHex: String
    )

    data class RawBubble(
        val text: String,
        val left: Double,
        val top: Double,
        val width: Double,
        val height: Double,
        val bgHex: String,
        val bgGradientEndHex: String?,
        val textHex: String
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "text" to text,
            "box" to mapOf(
                "left" to left,
                "top" to top,
                "width" to width,
                "height" to height
            ),
            "bgColorHex" to bgHex,
            "bgGradientEndHex" to bgGradientEndHex,
            "textColorHex" to textHex
        )
    }

    suspend fun processBitmap(bitmap: Bitmap): List<Map<String, Any?>> = withContext(Dispatchers.Default) {
        if (bitmap.isRecycled || bitmap.width <= 0 || bitmap.height <= 0) {
            return@withContext emptyList()
        }

        val rawBubbles = if (bitmap.height > OCR_TILE_THRESHOLD_PX) {
            extractBubblesTiled(bitmap)
        } else {
            extractBubblesDirect(bitmap, 0, bitmap.height)
        }

        val deduplicated = deduplicateAndMerge(rawBubbles)
        deduplicated.map { it.toMap() }
    }

    private fun extractBubblesTiled(bitmap: Bitmap): List<RawBubble> {
        val totalHeight = bitmap.height
        val totalWidth = bitmap.width
        val bubbles = mutableListOf<RawBubble>()

        var yOffset = 0
        while (yOffset < totalHeight) {
            val tileHeight = min(OCR_TILE_HEIGHT_PX, totalHeight - yOffset)
            if (tileHeight <= 0) break

            val tileBitmap = try {
                Bitmap.createBitmap(bitmap, 0, yOffset, totalWidth, tileHeight)
            } catch (e: Exception) {
                null
            }

            if (tileBitmap != null) {
                try {
                    val tileBubbles = extractBubblesDirect(tileBitmap, yOffset, totalHeight)
                    bubbles.addAll(tileBubbles)
                } finally {
                    if (tileBitmap != bitmap && !tileBitmap.isRecycled) {
                        tileBitmap.recycle()
                    }
                }
            }

            if (yOffset + tileHeight >= totalHeight) break
            yOffset += (OCR_TILE_HEIGHT_PX - OCR_TILE_OVERLAP_PX)
        }

        return bubbles
    }

    private fun extractBubblesDirect(bitmapTile: Bitmap, yOffsetGlobal: Int, totalImageHeight: Int): List<RawBubble> {
        val inputImage = InputImage.fromBitmap(bitmapTile, 0)
        val visionText: Text = try {
            Tasks.await(recognizer.process(inputImage))
        } catch (e: Exception) {
            return emptyList()
        }

        val list = mutableListOf<RawBubble>()
        for (block in visionText.textBlocks) {
            val text = block.text.trim()
            if (text.isEmpty()) continue

            val box = block.boundingBox ?: continue
            val left = box.left.toDouble()
            val top = (box.top + yOffsetGlobal).toDouble()
            val width = box.width().toDouble()
            val height = box.height().toDouble()

            val colors = sampleBubbleColors(bitmapTile, box)

            list.add(
                RawBubble(
                    text = text,
                    left = left,
                    top = top,
                    width = width,
                    height = height,
                    bgHex = colors.bgHex,
                    bgGradientEndHex = colors.bgGradientEndHex,
                    textHex = colors.textHex
                )
            )
        }
        return list
    }

    /**
     * Samples pixels around the perimeter of the bounding box to identify speech bubble background
     * color and text contrast color. Ported from HikariManga OcrBubbleUtilsKt.
     */
    private fun sampleBubbleColors(bitmap: Bitmap, box: Rect): BubbleColors {
        val bWidth = bitmap.width
        val bHeight = bitmap.height
        val left = box.left.coerceIn(0, bWidth - 1)
        val top = box.top.coerceIn(0, bHeight - 1)
        val right = box.right.coerceIn(0, bWidth - 1)
        val bottom = box.bottom.coerceIn(0, bHeight - 1)

        val w = right - left
        val h = bottom - top
        if (w <= 0 || h <= 0) {
            return BubbleColors("#FFFFFF", null, "#000000")
        }

        val padX = (w * 0.08).toInt().coerceIn(3, 14)
        val padY = (h * 0.08).toInt().coerceIn(3, 14)

        val topSamples = mutableListOf<Int>()
        val bottomSamples = mutableListOf<Int>()
        val sideSamples = mutableListOf<Int>()

        val topY = (top - padY).coerceIn(0, bHeight - 1)
        val bottomY = (bottom + padY).coerceIn(0, bHeight - 1)

        for (i in 1..6) {
            val x = (left + (w * i / 7)).coerceIn(0, bWidth - 1)
            topSamples.add(bitmap.getPixel(x, topY))
            bottomSamples.add(bitmap.getPixel(x, bottomY))
        }

        val leftX = (left - padX).coerceIn(0, bWidth - 1)
        val rightX = (right + padX).coerceIn(0, bWidth - 1)

        for (i in 1..6) {
            val y = (top + (h * i / 7)).coerceIn(0, bHeight - 1)
            sideSamples.add(bitmap.getPixel(leftX, y))
            sideSamples.add(bitmap.getPixel(rightX, y))
        }

        val allBorder = topSamples + bottomSamples + sideSamples
        val dominantBg = getDominantColor(allBorder)

        // Calculate luminance: 0.299 R + 0.587 G + 0.114 B
        val lum = (Color.red(dominantBg) * 0.299 +
                Color.green(dominantBg) * 0.587 +
                Color.blue(dominantBg) * 0.114) / 255.0

        val textHex = if (lum > 0.5) "#000000" else "#FFFFFF"
        val bgHex = String.format("#%06X", (0xFFFFFF and dominantBg))

        val topDominant = getDominantColor(topSamples)
        val bottomDominant = getDominantColor(bottomSamples)
        val gradientEnd = if (topDominant != bottomDominant && topDominant != dominantBg) {
            String.format("#%06X", (0xFFFFFF and bottomDominant))
        } else null

        return BubbleColors(bgHex, gradientEnd, textHex)
    }

    private fun getDominantColor(pixels: List<Int>): Int {
        if (pixels.isEmpty()) return Color.WHITE
        var r = 0L
        var g = 0L
        var b = 0L
        for (c in pixels) {
            r += Color.red(c)
            g += Color.green(c)
            b += Color.blue(c)
        }
        val count = pixels.size
        return Color.rgb((r / count).toInt(), (g / count).toInt(), (b / count).toInt())
    }

    private fun deduplicateAndMerge(bubbles: List<RawBubble>): List<RawBubble> {
        if (bubbles.size <= 1) return bubbles
        val sorted = bubbles.sortedBy { it.top }
        val result = mutableListOf<RawBubble>()

        for (curr in sorted) {
            if (result.isEmpty()) {
                result.add(curr)
                continue
            }
            val last = result.last()
            // Check if curr and last significantly overlap vertically and horizontally
            val verticalGap = curr.top - (last.top + last.height)
            val horizontalOverlap = max(0.0, min(last.left + last.width, curr.left + curr.width) - max(last.left, curr.left))
            val minWidth = min(last.width, curr.width)

            if (verticalGap in -20.0..40.0 && horizontalOverlap > 0.3 * minWidth) {
                // Merge bubbles
                val newLeft = min(last.left, curr.left)
                val newTop = min(last.top, curr.top)
                val newRight = max(last.left + last.width, curr.left + curr.width)
                val newBottom = max(last.top + last.height, curr.top + curr.height)
                val mergedText = "${last.text} ${curr.text}"

                result[result.size - 1] = last.copy(
                    text = mergedText,
                    left = newLeft,
                    top = newTop,
                    width = newRight - newLeft,
                    height = newBottom - newTop
                )
            } else {
                result.add(curr)
            }
        }
        return result
    }
}
