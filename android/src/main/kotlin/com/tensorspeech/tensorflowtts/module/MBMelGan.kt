package com.tensorspeech.tensorflowtts.module

import android.util.Log
import org.tensorflow.lite.Interpreter
import org.tensorflow.lite.support.tensorbuffer.TensorBuffer
import java.io.File
import java.nio.FloatBuffer
import java.util.*
import kotlin.math.*

/**
 * @author []" "Xuefeng Ding"">&quot;mailto:xuefeng.ding@outlook.com&quot; &quot;Xuefeng Ding&quot;
 * Created 2020-07-20 17:26
 */
class MBMelGan(modulePath: String) : AbstractModule() {
    private lateinit var mModule: Interpreter
    private val hopSize = 512
    private val minBufferSize = 350000

    private fun roundUp(num: Int): Int {
        return (ceil(num.toDouble() / 100000.0) * 100000.0).toInt()
    }

    fun getAudio(input: TensorBuffer, isCancelled: () -> Boolean): FloatArray? {
        if(isCancelled()) return null
        mModule.resizeInput(0, input.shape)
        mModule.allocateTensors()
        if(isCancelled()) return null
        var bufferSize = minBufferSize
        val melSpectrogramLength = input.shape[1] * hopSize
        if(melSpectrogramLength > bufferSize) {
            bufferSize = max(minBufferSize, max(melSpectrogramLength, roundUp(melSpectrogramLength)))
        }

        val outputBuffer = FloatBuffer.allocate(bufferSize)
        if(isCancelled()) return null
        mModule.run(input.buffer, outputBuffer)
        if(isCancelled()) return null
        val audioArray = FloatArray(outputBuffer.position())
        outputBuffer.rewind()
        outputBuffer[audioArray]
        if(isCancelled()) return null
        return audioArray
    }

    companion object {
        private const val TAG = "MBMelGan"
    }

    init {
        try {
            mModule = Interpreter(File(modulePath), option)
            val input = mModule.inputTensorCount
            for (i in 0 until input) {
                val inputTensor = mModule.getInputTensor(i)
                Log.d(
                    TAG, "input:" + i
                            + " name:" + inputTensor.name()
                            + " shape:" + Arrays.toString(inputTensor.shape()) +
                            " dtype:" + inputTensor.dataType()
                )
            }
            val output = mModule.outputTensorCount
            for (i in 0 until output) {
                val outputTensor = mModule.getOutputTensor(i)
                Log.d(
                    TAG, "output:" + i
                            + " name:" + outputTensor.name()
                            + " shape:" + Arrays.toString(outputTensor.shape())
                            + " dtype:" + outputTensor.dataType()
                )
            }
            Log.d(TAG, "successfully init")
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}