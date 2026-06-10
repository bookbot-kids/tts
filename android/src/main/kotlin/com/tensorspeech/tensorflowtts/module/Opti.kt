package com.tensorspeech.tensorflowtts.module

import android.util.Log
import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import java.nio.FloatBuffer
import java.nio.LongBuffer
import java.util.Locale

/**
 * Optimised end-to-end ONNX TTS processor (single-model architecture).
 *
 * Accepts phoneme token IDs and returns raw PCM audio plus per-phoneme
 * durations in a single ONNX inference pass. Supports multi-speaker models
 * via [speakerId] and optional language IDs via [enableLids].
 */
class Opti (modulePath: String, threadCount: Int,
            ortEnv: OrtEnvironment,
            provider: Provider = Provider.CPU,
) : AbstractModule(threadCount, modulePath, ortEnv, provider) {
    /**
     * Runs ONNX inference on the given [inputIds].
     *
     * @return A [Pair] of (audio PCM Float32 array, per-phoneme durations in
     *         seconds), or `null` if cancelled.
     */
    @Suppress("UNCHECKED_CAST")
    fun process(inputIds: LongArray, speed: Float, speakerId: Long, hopSize: Int, sampleRate: Int, enableLids: Boolean, logEnabled: Boolean = true, isCancelled: () -> Boolean): Pair<FloatArray, DoubleArray>? {
        if (isCancelled()) return null
        val processStartNs = System.nanoTime()

        val x = inputIds
        val xLengths = longArrayOf(inputIds.size.toLong())
        val scales = floatArrayOf(speed, 1.0f, 1.0f)

        // Define shapes
        val xShape = longArrayOf(1, x.size.toLong())
        val xLengthsShape = longArrayOf(1)
        val scalesShape = longArrayOf(3)

        // Create input tensors
        val xTensor = OnnxTensor.createTensor(ortEnv, LongBuffer.wrap(x), xShape)
        val xLengthsTensor = OnnxTensor.createTensor(ortEnv, LongBuffer.wrap(xLengths), xLengthsShape)
        val scalesTensor = OnnxTensor.createTensor(ortEnv, FloatBuffer.wrap(scales), scalesShape)


        val inputTensors = mutableMapOf(
            "x" to xTensor,
            "x_lengths" to xLengthsTensor,
            "scales" to scalesTensor,
        )

        if(speakerId >= 0) {
            val sids = longArrayOf(speakerId)
            val sidsShape = longArrayOf(1)
            val sidsTensor = OnnxTensor.createTensor(ortEnv, LongBuffer.wrap(sids), sidsShape)
            inputTensors["sids"] = sidsTensor
        }

        if (enableLids) {
            val lids = longArrayOf(0)
            val lidsShape = longArrayOf(1)
            val lidsTensor = OnnxTensor.createTensor(ortEnv, LongBuffer.wrap(lids), lidsShape)
            inputTensors["lids"] = lidsTensor
        }        

        if (isCancelled()) return null

        val output = session.run(inputTensors)
        output.use {
            if (isCancelled()) return null
            val audioOrtValue = output.firstOrNull { it.key == "wav" }?.value as? OnnxTensor
            val durationsOrtValue = output.firstOrNull { it.key == "durations" }?.value as? OnnxTensor
            if (audioOrtValue == null || durationsOrtValue == null) {
                return null
            }

            val audioArray = (audioOrtValue.value as Array<FloatArray>)[0]
            val durationsArray = (durationsOrtValue.value as Array<LongArray>)[0]
            if (logEnabled) {
                logRealTimeFactor(processStartNs, audioArray.size, sampleRate)
            }
            // convert to seconds
            val durationsInSeconds = durationsArray.map { it.toDouble() * hopSize / sampleRate }.toDoubleArray()
            return audioArray to durationsInSeconds
        }
    }

    private fun logRealTimeFactor(processStartNs: Long, audioSampleCount: Int, sampleRate: Int) {
        if (audioSampleCount <= 0 || sampleRate <= 0) return

        val elapsedSeconds = (System.nanoTime() - processStartNs) / 1_000_000_000.0
        val audioDurationSeconds = audioSampleCount.toDouble() / sampleRate
        val rtf = elapsedSeconds / audioDurationSeconds
        Log.d(TAG, "RTF (Real-Time Factor) ${formatDecimal(elapsedSeconds)}/${formatDecimal(audioDurationSeconds)} = ${formatDecimal(rtf)}")
    }

    private fun formatDecimal(value: Double): String =
        String.format(Locale.US, "%.3f", value).replace('.', ',')

    companion object {
        private const val TAG = "Opti"
    }
}
