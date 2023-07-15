package com.tensorspeech.tensorflowtts.tts

import android.util.Log
import com.tensorspeech.tensorflowtts.module.FastSpeech2
import com.tensorspeech.tensorflowtts.module.MBMelGan

class GenerateTask(private val fastspeech: FastSpeech2, private val mbMelGan: MBMelGan,
                    private val inputIds: List<Int>, private val speed: Float,
                    private val speakerId: Int = 0,
                   private val onCompleted: (buffer: FloatArray, durations: Array<IntArray>) -> Unit,
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
        val output =
            fastspeech.getMelSpectrogram(inputIds.toIntArray(), speed, speakerId, isStopping)
                ?: return

        if (isStopping())  return
        val audioData = mbMelGan.getAudio(output.first, isStopping) ?: return
        val durations = output.second

        val audio = audioData.flatMap { it.asIterable() }.flatMap { it.asIterable() }.toFloatArray()
        onCompleted(audio, durations)
    }

}