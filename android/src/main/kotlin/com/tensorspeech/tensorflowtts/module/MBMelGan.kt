package com.tensorspeech.tensorflowtts.module

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import java.nio.FloatBuffer
import java.util.Collections
import kotlin.math.ceil

/**
 * Multi-Band MelGAN vocoder processor (legacy two-stage pipeline).
 *
 * Converts a mel spectrogram (produced by [FastSpeech2]) into raw PCM audio.
 */
class MBMelGan(private val modulePath: String, threadCount: Int, ortEnv: OrtEnvironment) : AbstractModule(threadCount, modulePath, ortEnv) {
    /** Hop size used for buffer-size calculations. */
    private val hopSize = 512
    /** Minimum audio buffer size in samples. */
    private val minBufferSize = 350000

    /** Rounds [num] up to the nearest 100 000. */
    private fun roundUp(num: Int): Int {
        return (ceil(num.toDouble() / 100000.0) * 100000.0).toInt()
    }

    /** Runs MelGAN inference on the given mel spectrogram and returns raw PCM audio. */
    fun getAudio(mels: Array<Array<FloatArray>>, isCancelled: () -> Boolean): Array<Array<FloatArray>>? {
        if(isCancelled()) return null

        // unpack 3d FloatArray and get size along each dimension := (1, L, 80)
        val melsShape = longArrayOf(mels.size.toLong(), mels[0].size.toLong(), mels[0][0].size.toLong())

        val totalElements = mels.size * mels[0].size * mels[0][0].size
        val flattenedMels = FloatArray(totalElements) { index ->
            val i = index / (mels[0].size * mels[0][0].size)
            val j = (index % (mels[0].size * mels[0][0].size)) / mels[0][0].size
            val k = (index % (mels[0].size * mels[0][0].size)) % mels[0][0].size
            mels[i][j][k]
        }

        if(isCancelled()) return null
        // create input tensors from raw vectors
        val melTensor = OnnxTensor.createTensor(ortEnv, FloatBuffer.wrap(flattenedMels), melsShape)
        if(isCancelled()) return null
        // create input name -> input tensor map
        val inputTensors: Map<String, OnnxTensor> = Collections.singletonMap("mels", melTensor)

        val output = session.run(inputTensors)
        output.use {
            @Suppress("UNCHECKED_CAST")
            return output?.get(0)?.value as Array<Array<FloatArray>>
        }
    }
}