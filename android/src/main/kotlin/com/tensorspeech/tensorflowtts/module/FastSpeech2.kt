package com.tensorspeech.tensorflowtts.module

import android.annotation.SuppressLint
import android.util.Log
import org.tensorflow.lite.DataType
import org.tensorflow.lite.Interpreter
import org.tensorflow.lite.support.tensorbuffer.TensorBuffer
import java.io.File
import java.nio.FloatBuffer
import java.util.*

/**
 * @author []" "Xuefeng Ding"">&quot;mailto:xuefeng.ding@outlook.com&quot; &quot;Xuefeng Ding&quot;
 * Created 2020-07-20 17:26
 */
class FastSpeech2(modulePath: String) : AbstractModule() {
    private lateinit var mModule: Interpreter
    fun getMelSpectrogram(inputIds: IntArray, speed: Float): TensorBuffer {
        Log.d(TAG, "input id length: " + inputIds.size)
        mModule.resizeInput(0, intArrayOf(1, inputIds.size))
        mModule.allocateTensors()
        @SuppressLint("UseSparseArrays") val outputMap: MutableMap<Int, Any> = HashMap()
        val outputBuffer = FloatBuffer.allocate(350000)
        outputMap[0] = outputBuffer
        val inputs = Array(1) { IntArray(inputIds.size) }
        inputs[0] = inputIds
        val time = System.currentTimeMillis()
        mModule.runForMultipleInputsOutputs(
            arrayOf<Any>(
                inputs,
                Array(1) { IntArray(1) },
                intArrayOf(0),
                floatArrayOf(speed),
                floatArrayOf(1f),
                floatArrayOf(1f)
            ),
            outputMap
        )
        Log.d(TAG, "time cost: " + (System.currentTimeMillis() - time))
        val size = mModule.getOutputTensor(0).shape()[2]
        val shape = intArrayOf(1, outputBuffer.position() / size, size)
        val spectrogram = TensorBuffer.createFixedSize(shape, DataType.FLOAT32)
        val outputArray = FloatArray(outputBuffer.position())
        outputBuffer.rewind()
        outputBuffer[outputArray]
        spectrogram.loadArray(outputArray)
        return spectrogram
    }

    companion object {
        private const val TAG = "FastSpeech2"
    }

    init {
        try {
            mModule = Interpreter(File(modulePath), option)
            val input = mModule.inputTensorCount
            for (i in 0 until input) {
                val inputTensor = mModule.getInputTensor(i)
                Log.d(
                    TAG, "input:" + i +
                            " name:" + inputTensor.name() +
                            " shape:" + Arrays.toString(inputTensor.shape()) +
                            " dtype:" + inputTensor.dataType()
                )
            }
            val output = mModule.getOutputTensorCount()
            for (i in 0 until output) {
                val outputTensor = mModule.getOutputTensor(i)
                Log.d(
                    TAG, "output:" + i +
                            " name:" + outputTensor.name() +
                            " shape:" + Arrays.toString(outputTensor.shape()) +
                            " dtype:" + outputTensor.dataType()
                )
            }
            Log.d(TAG, "successfully init")
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}