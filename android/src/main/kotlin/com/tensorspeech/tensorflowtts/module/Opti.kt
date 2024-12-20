package com.tensorspeech.tensorflowtts.module

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import java.nio.FloatBuffer
import java.nio.LongBuffer

class Opti (modulePath: String, threadCount: Int,
            ortEnv: OrtEnvironment
) : AbstractModule(threadCount, modulePath, ortEnv) {
    @Suppress("UNCHECKED_CAST")
    fun process(inputIds: LongArray, speed: Float, speakerId: Long, hopSize: Int, sampleRate: Int, enableLids: Boolean, isCancelled: () -> Boolean): Pair<FloatArray, DoubleArray>? {
        if (isCancelled()) return null

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
            // convert to seconds
            val durationsInSeconds = durationsArray.map { it.toDouble() * hopSize / sampleRate }.toDoubleArray()
            return audioArray to durationsInSeconds
        }
    }
}