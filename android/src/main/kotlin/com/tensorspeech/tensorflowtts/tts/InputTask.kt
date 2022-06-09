package com.tensorspeech.tensorflowtts.tts

import android.util.Log
import com.tensorspeech.tensorflowtts.module.FastSpeech2
import com.tensorspeech.tensorflowtts.module.MBMelGan
import io.flutter.plugin.common.MethodChannel

class InputTask(private val fastspeech: FastSpeech2, private val mbMelGan: MBMelGan,
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

        val output =
            fastspeech.getMelSpectrogram(inputIds.toIntArray(), speed, speakerId, isStopping)
                ?: return

        result.success(output.second.map { it.toDouble() })
        if (isStopping()) {
            return
        }

        val audioData = mbMelGan.getAudio(output.first, isStopping) ?: return
        if (isStopping()) {
            return
        }

        player?.play(inputIds, audioData, isStopping)
    }
}