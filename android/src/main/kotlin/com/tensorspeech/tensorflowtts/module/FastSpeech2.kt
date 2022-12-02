package com.tensorspeech.tensorflowtts.module

import android.annotation.SuppressLint
import org.tensorflow.lite.DataType
import org.tensorflow.lite.Interpreter
import org.tensorflow.lite.support.tensorbuffer.TensorBuffer
import java.io.File
import java.nio.FloatBuffer
import java.nio.IntBuffer
import java.util.*

/**
 * @author []" "Xuefeng Ding"">&quot;mailto:xuefeng.ding@outlook.com&quot; &quot;Xuefeng Ding&quot;
 * Created 2020-07-20 17:26
 */
class FastSpeech2(private val modulePath: String) : AbstractModule() {
    fun getMelSpectrogram(inputIds: IntArray, speed: Float, speakerId: Int, isCancelled: () -> Boolean): Pair<TensorBuffer, IntArray>? {
        if(isCancelled()) return null
        val interpreter = Interpreter(File(modulePath), option)
        interpreter.resizeInput(0, intArrayOf(1, inputIds.size))

        if(isCancelled()) {
            interpreter.close()
            return null
        }
        interpreter.allocateTensors()
        if(isCancelled()) {
            interpreter.close()
            return null
        }
        @SuppressLint("UseSparseArrays") val outputMap: MutableMap<Int, Any> = HashMap()
        val outputBuffer = FloatBuffer.allocate(350000)
        val outputBuffer3 = IntBuffer.allocate(inputIds.size)
        if(isCancelled()) {
            interpreter.close()
            return null
        }
        outputMap[0] = outputBuffer
        outputMap[1] = outputBuffer3
        val inputs = Array(1) { IntArray(inputIds.size) }
        inputs[0] = inputIds

        if(isCancelled()) {
            interpreter.close()
            return null
        }

        interpreter.runForMultipleInputsOutputs(
            arrayOf<Any>(
                inputs,
                intArrayOf(speakerId),
                floatArrayOf(speed),
                floatArrayOf(1f),
                floatArrayOf(1f)
            ),
            outputMap
        )

        if(isCancelled()) {
            interpreter.close()
            return null
        }
        val size = interpreter.getOutputTensor(0).shape()[2]
        if(isCancelled()) {
            interpreter.close()
            return null
        }
        val shape = intArrayOf(1, outputBuffer.position() / size, size)
        val spectrogram1 = TensorBuffer.createFixedSize(shape, DataType.FLOAT32)
        val outputArray = FloatArray(outputBuffer.position())

        if(isCancelled()) {
            interpreter.close()
            return null
        }
        outputBuffer.rewind()
        outputBuffer[outputArray]

        if(isCancelled()) {
            interpreter.close()
            return null
        }
        spectrogram1.loadArray(outputArray)
        outputBuffer3.position()
        val duration = outputBuffer3.array()
        interpreter.close()
        return spectrogram1 to duration
    }
}