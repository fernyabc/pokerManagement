package com.pokermanagement.service

import android.content.Context
import android.graphics.Bitmap
import android.graphics.RectF
import org.tensorflow.lite.Interpreter
import org.tensorflow.lite.gpu.CompatibilityList
import org.tensorflow.lite.gpu.GpuDelegate
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.MappedByteBuffer
import java.nio.channels.FileChannel

data class DetectedCard(
    val label: String,
    val confidence: Float,
    val boundingBox: RectF  // normalized [0,1], top-left origin
)

class CardDetectionService(private val context: Context) {

    var modelLoaded: Boolean = false
        private set

    private var interpreter: Interpreter? = null
    private var gpuDelegate: GpuDelegate? = null

    // 52-card label map matching iOS order
    private val labels = listOf(
        "Ac", "2c", "3c", "4c", "5c", "6c", "7c", "8c", "9c", "Tc", "Jc", "Qc", "Kc",
        "Ad", "2d", "3d", "4d", "5d", "6d", "7d", "8d", "9d", "Td", "Jd", "Qd", "Kd",
        "Ah", "2h", "3h", "4h", "5h", "6h", "7h", "8h", "9h", "Th", "Jh", "Qh", "Kh",
        "As", "2s", "3s", "4s", "5s", "6s", "7s", "8s", "9s", "Ts", "Js", "Qs", "Ks"
    )

    private val inputSize = 640
    private val confidenceThreshold = 0.25f
    private val iouThreshold = 0.45f
    // Output tensor: [1, 56, 8400] — 4 bbox coords + 52 class scores
    private val numDetections = 8400
    private val numAttributes = 56

    init {
        loadModel()
    }

    private fun loadModel() {
        try {
            val modelBuffer = loadModelFile("yolov11-playing-cards.tflite")

            val options = Interpreter.Options()
            val compatList = CompatibilityList()
            if (compatList.isDelegateSupportedOnThisDevice) {
                gpuDelegate = GpuDelegate()
                options.addDelegate(gpuDelegate!!)
            }

            interpreter = Interpreter(modelBuffer, options)
            modelLoaded = true
        } catch (e: Exception) {
            modelLoaded = false
        }
    }

    private fun loadModelFile(filename: String): MappedByteBuffer {
        val assetFileDescriptor = context.assets.openFd(filename)
        val inputStream = FileInputStream(assetFileDescriptor.fileDescriptor)
        val fileChannel = inputStream.channel
        return fileChannel.map(
            FileChannel.MapMode.READ_ONLY,
            assetFileDescriptor.startOffset,
            assetFileDescriptor.declaredLength
        )
    }

    fun detect(bitmap: Bitmap): List<DetectedCard> {
        val interpreter = interpreter ?: return emptyList()

        val inputBuffer = preprocessBitmap(bitmap)
        // Output shape: [1, 56, 8400]
        val outputArray = Array(1) { Array(numAttributes) { FloatArray(numDetections) } }

        interpreter.run(inputBuffer, outputArray)

        return postprocess(outputArray[0], bitmap.width, bitmap.height)
    }

    private fun preprocessBitmap(bitmap: Bitmap): ByteBuffer {
        val scaled = Bitmap.createScaledBitmap(bitmap, inputSize, inputSize, true)
        val buffer = ByteBuffer.allocateDirect(4 * inputSize * inputSize * 3)
        buffer.order(ByteOrder.nativeOrder())

        val pixels = IntArray(inputSize * inputSize)
        scaled.getPixels(pixels, 0, inputSize, 0, 0, inputSize, inputSize)

        for (pixel in pixels) {
            val r = ((pixel shr 16) and 0xFF) / 255.0f
            val g = ((pixel shr 8) and 0xFF) / 255.0f
            val b = (pixel and 0xFF) / 255.0f
            buffer.putFloat(r)
            buffer.putFloat(g)
            buffer.putFloat(b)
        }
        buffer.rewind()
        return buffer
    }

    private fun postprocess(
        output: Array<FloatArray>,
        origWidth: Int,
        origHeight: Int
    ): List<DetectedCard> {
        val candidates = mutableListOf<DetectedCard>()

        for (i in 0 until numDetections) {
            val cx = output[0][i]
            val cy = output[1][i]
            val w = output[2][i]
            val h = output[3][i]

            // Find best class
            var bestClass = -1
            var bestScore = confidenceThreshold
            for (c in 0 until labels.size) {
                val score = output[4 + c][i]
                if (score > bestScore) {
                    bestScore = score
                    bestClass = c
                }
            }

            if (bestClass < 0) continue

            // Convert cx,cy,w,h (normalized) to x1,y1,x2,y2
            val x1 = (cx - w / 2f).coerceIn(0f, 1f)
            val y1 = (cy - h / 2f).coerceIn(0f, 1f)
            val x2 = (cx + w / 2f).coerceIn(0f, 1f)
            val y2 = (cy + h / 2f).coerceIn(0f, 1f)

            candidates.add(
                DetectedCard(
                    label = labels[bestClass],
                    confidence = bestScore,
                    boundingBox = RectF(x1, y1, x2, y2)
                )
            )
        }

        return applyNms(candidates)
    }

    private fun applyNms(candidates: List<DetectedCard>): List<DetectedCard> {
        val sorted = candidates.sortedByDescending { it.confidence }
        val kept = mutableListOf<DetectedCard>()

        for (candidate in sorted) {
            val suppressed = kept.any { existing ->
                iou(candidate.boundingBox, existing.boundingBox) > iouThreshold
            }
            if (!suppressed) kept.add(candidate)
        }
        return kept
    }

    private fun iou(a: RectF, b: RectF): Float {
        val interLeft = maxOf(a.left, b.left)
        val interTop = maxOf(a.top, b.top)
        val interRight = minOf(a.right, b.right)
        val interBottom = minOf(a.bottom, b.bottom)

        val interWidth = (interRight - interLeft).coerceAtLeast(0f)
        val interHeight = (interBottom - interTop).coerceAtLeast(0f)
        val intersection = interWidth * interHeight

        val aArea = a.width() * a.height()
        val bArea = b.width() * b.height()
        val union = aArea + bArea - intersection

        return if (union > 0) intersection / union else 0f
    }

    fun classifyCards(
        detected: List<DetectedCard>
    ): Pair<List<String>, List<String>> {
        // Android top-left origin: y > 0.7 means bottom 30% of frame → hole cards
        val holeCards = detected
            .filter { it.boundingBox.top > 0.7f }
            .map { it.label }

        val communityCards = detected
            .filter { it.boundingBox.top <= 0.7f }
            .map { it.label }

        return Pair(holeCards, communityCards)
    }

    fun close() {
        interpreter?.close()
        gpuDelegate?.close()
    }
}
