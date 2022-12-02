package com.tensorspeech.tensorflowtts.module

import org.tensorflow.lite.Interpreter
import org.tensorflow.lite.support.tensorbuffer.TensorBuffer
import java.io.File
import java.nio.FloatBuffer
import kotlin.math.ceil
import kotlin.math.max

/**
 * @author []" "Xuefeng Ding"">&quot;mailto:xuefeng.ding@outlook.com&quot; &quot;Xuefeng Ding&quot;
 * Created 2020-07-20 17:26
 */
class MBMelGan(private val modulePath: String) : AbstractModule() {
    private val hopSize = 512
    private val minBufferSize = 350000

    private fun roundUp(num: Int): Int {
        return (ceil(num.toDouble() / 100000.0) * 100000.0).toInt()
    }

    fun getAudio(input: TensorBuffer, isCancelled: () -> Boolean): FloatArray? {
        if(isCancelled()) return null
        val interpreter = Interpreter(File(modulePath), option)
        interpreter.resizeInput(0, input.shape)
        interpreter.allocateTensors()
        if(isCancelled()) {
            interpreter.close()
            return null
        }
        var bufferSize = minBufferSize
        val melSpectrogramLength = input.shape[1] * hopSize
        if(melSpectrogramLength > bufferSize) {
            bufferSize = max(minBufferSize, max(melSpectrogramLength, roundUp(melSpectrogramLength)))
        }

        val outputBuffer = FloatBuffer.allocate(bufferSize)
        if(isCancelled()) {
            interpreter.close()
            return null
        }
        interpreter.run(input.buffer, outputBuffer)
        if(isCancelled()) {
            interpreter.close()
            return null
        }
        val audioArray = FloatArray(outputBuffer.position())
        outputBuffer.rewind()
        outputBuffer[audioArray]
        if(isCancelled()) return null
        interpreter.close()
        return audioArray
    }
}