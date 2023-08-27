package com.tensorspeech.tensorflowtts.module

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import java.nio.FloatBuffer
import java.nio.LongBuffer

class Piper(modulePath: String, threadCount: Int,
ortEnv: OrtEnvironment
) : AbstractModule(threadCount, modulePath, ortEnv) {

    private fun sumVertically(array: Array<FloatArray>): FloatArray {
        val numRows = array.size
        val numCols = array[0].size

        val sumArray = FloatArray(numCols)

        for (col in 0 until numCols) {
            var sum = 0.0f
            for (row in 0 until numRows) {
                sum += array[row][col]
            }
            sumArray[col] = sum
        }

        return sumArray
    }

    fun infer(inputIds: LongArray, speakerId: Int, isCancelled: () -> Boolean): Pair<Array<Array<FloatArray>>, FloatArray>? {
        if(isCancelled()) return null
        val inputLength = longArrayOf(inputIds.size.toLong())
        val scales = floatArrayOf(0.667F, 1.0F, 0.8F)
        // TODO: change if multispeaker! only `null` if single-speaker
        val sid = null

        // this is the shape of the inputs, our equivalent to tf.expand_dims.
        val inputShape = longArrayOf(1, inputIds.size.toLong())
        val inputLengthShape = longArrayOf(1)
        val scalesShape = longArrayOf(3)

        val inputNames = arrayOf("input", "input_lengths", "scales")

        // create input tensors from raw vectors
        val inputTensor = OnnxTensor.createTensor(ortEnv, LongBuffer.wrap(inputIds), inputShape)
        val inputLengthTensor = OnnxTensor.createTensor(ortEnv, LongBuffer.wrap(inputLength), inputLengthShape)
        val scalesTensor = OnnxTensor.createTensor(ortEnv, FloatBuffer.wrap(scales), scalesShape)

        val inputTensorsVector = arrayOf(inputTensor, inputLengthTensor, scalesTensor)
        if(isCancelled()) return null
        // create input name -> input tensor map
        val inputTensors: Map<String, OnnxTensor> = inputNames.zip(inputTensorsVector).toMap()
        if(isCancelled()) return null
        val output = session.run(inputTensors)
        output.use {
            @Suppress("UNCHECKED_CAST") val audio = (output?.get(0)?.value) as Array<Array<FloatArray>> // (1, 1, frames) => (1, 1, acousticFrames * hopLength)
            @Suppress("UNCHECKED_CAST") val attention = (output.get(1)?.value) as Array<Array<Array<FloatArray>>> // (1, 1, acousticFrames, inputLength)

            val durations = sumVertically(attention[0][0])
            return audio to durations
        }
    }
}