package com.tensorspeech.tensorflowtts.tts

import android.util.Log
import com.tensorspeech.tensorflowtts.module.Opti

class GenerateTask(private val opti: Opti,
                    private val inputIds: List<Long>, private val speed: Float,
                    private val speakerId: Long = 0,
                   private val hopSize: Int, private val sampleRate: Int,
                   private val enableLids: Boolean,
                   private val onCompleted: (buffer: FloatArray, durations: DoubleArray) -> Unit,
                   private val onCancelled: () -> Unit
): Runnable {
    var stop: Boolean = false
        set(value) {
            field = value
            Log.d("", "InputTask stop $value")
        }

    override fun run() {
        val isStopping: () -> Boolean = {
            val checking = stop || Thread.interrupted()
            if(checking) {
                onCancelled()
            }

            checking
        }
        if (isStopping())  return
        val output = opti.process(inputIds.toLongArray(), speed, speakerId, hopSize, sampleRate, enableLids, isStopping) ?: return
        if (isStopping())  return
        val audio = output.first
        val durations = output.second
        onCompleted(audio, durations)
    }

}