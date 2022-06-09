package com.tensorspeech.tensorflowtts.module

import android.util.Log
import org.tensorflow.lite.Interpreter
import org.tensorflow.lite.support.tensorbuffer.TensorBuffer
import java.io.File
import java.nio.FloatBuffer
import java.util.*

/**
 * @author []" "Xuefeng Ding"">&quot;mailto:xuefeng.ding@outlook.com&quot; &quot;Xuefeng Ding&quot;
 * Created 2020-07-20 17:26
 */
class MBMelGan(modulePath: String) : AbstractModule() {
    private lateinit var mModule: Interpreter
    fun getAudio(input: TensorBuffer, isCancelled: () -> Boolean): FloatArray? {
        if(isCancelled()) return null
        mModule.resizeInput(0, input.shape)
        mModule.allocateTensors()
        if(isCancelled()) return null
        val outputBuffer = FloatBuffer.allocate(350000)
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