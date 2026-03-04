package com.tensorspeech.tensorflowtts.module

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import java.nio.FloatBuffer
import java.nio.IntBuffer
import java.util.*

/**
 * FastSpeech 2 acoustic model processor (legacy two-stage pipeline).
 *
 * Converts phoneme token IDs into a mel spectrogram and per-phoneme
 * duration frames. The mel output is then fed to [MBMelGan] to synthesise
 * raw PCM audio.
 */
class FastSpeech2(modulePath: String, threadCount: Int,
                   ortEnv: OrtEnvironment
) : AbstractModule(threadCount, modulePath, ortEnv) {
    /**
     * Runs FastSpeech 2 inference to produce a mel spectrogram.
     *
     * @return A [Pair] of (mel spectrogram, duration frames), or `null` if cancelled.
     */
    fun getMelSpectrogram(inputIds: IntArray, speed: Float, speakerId: Int, isCancelled: () -> Boolean): Pair<Array<Array<FloatArray>>, Array<IntArray>>? {
        if(isCancelled()) return null
        val speakerIDs = intArrayOf(speakerId)
        val speedRatios = floatArrayOf(speed)
        val f0Ratios = floatArrayOf(1.0F)
        val energyRatios = floatArrayOf(1.0F)

        // this is the shape of the inputs, our equivalent to tf.expand_dims.
        val inputIDsShape = longArrayOf(1, inputIds.size.toLong())
        val speakerIDsShape = longArrayOf(1)
        val speedRatiosShape = longArrayOf(1)
        val f0RatiosShape = longArrayOf(1)
        val energyRatiosShape = longArrayOf(1)

        val inputNames = arrayOf("input_ids", "speaker_ids", "speed_ratios", "f0_ratios", "energy_ratios")

        // create input tensors from raw vectors
        val inputIDsTensor = OnnxTensor.createTensor(ortEnv, IntBuffer.wrap(inputIds), inputIDsShape)
        val speakerIDsTensor = OnnxTensor.createTensor(ortEnv, IntBuffer.wrap(speakerIDs), speakerIDsShape)
        val speedRatiosTensor = OnnxTensor.createTensor(ortEnv, FloatBuffer.wrap(speedRatios), speedRatiosShape)
        val f0RatiosTensor = OnnxTensor.createTensor(ortEnv, FloatBuffer.wrap(f0Ratios), f0RatiosShape)
        val energyRatiosTensor = OnnxTensor.createTensor(ortEnv, FloatBuffer.wrap(energyRatios), energyRatiosShape)
        val inputTensorsVector = arrayOf(inputIDsTensor, speakerIDsTensor, speedRatiosTensor, f0RatiosTensor, energyRatiosTensor)

        if(isCancelled()) return null
        // create input name -> input tensor map
        val inputTensors: Map<String, OnnxTensor> = inputNames.zip(inputTensorsVector).toMap()
        if(isCancelled()) return null

        val output = session.run(inputTensors)
        output.use {
            @Suppress("UNCHECKED_CAST") val mels = output?.get(0)?.value as Array<Array<FloatArray>>
            @Suppress("UNCHECKED_CAST") val durations = output.get(1)?.value as Array<IntArray>
            return mels to durations
        }
    }
}