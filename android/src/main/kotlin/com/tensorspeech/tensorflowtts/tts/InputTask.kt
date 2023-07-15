package com.tensorspeech.tensorflowtts.tts

import android.util.Log
import com.tensorspeech.tensorflowtts.module.FastSpeech2
import com.tensorspeech.tensorflowtts.module.MBMelGan
import io.flutter.plugin.common.MethodChannel

class InputTask(private val fastSpeech: FastSpeech2, private val mbMelGan: MBMelGan,
                private val inputIds: List<Int>, private val speed: Float,
                private val speakerId: Int = 0, private val player: TtsBufferPlayer?,
                private val result: MethodChannel.Result
): Runnable {
    var stop: Boolean = false
        set(value) {
            field = value
            Log.d("", "InputTask stop $value")
        }

    override fun run() {
        val isStopping: () -> Boolean = {
            stop || Thread.interrupted()
        }
        if (isStopping())  return
        val output =
            fastSpeech.getMelSpectrogram(inputIds.toIntArray(), speed, speakerId, isStopping)
                ?: return

        if (isStopping())  return
        val audioData = mbMelGan.getAudio(output.first, isStopping) ?: return
        val audio = audioData.flatMap { it.asIterable() }.flatMap { it.asIterable() }.toFloatArray()
        val duration = output.second.flatMap { it.asIterable() }.map { it.toDouble() }
        if (isStopping())  return
        result.success(duration)
        if (isStopping())  return
        player?.play(inputIds, audio, isStopping)
    }
}