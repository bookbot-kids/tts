package com.tensorspeech.tensorflowtts.tts

import android.util.Log
import com.tensorspeech.tensorflowtts.module.Opti
import io.flutter.plugin.common.MethodChannel

class InputTask(private val opti: Opti,
                private val inputIds: List<Long>, private val speed: Float,
                private val speakerId: Long = 0, private val hopSize: Int, private val sampleRate: Int,
                private val enableLids: Boolean,
                private val player: TtsBufferPlayer?,
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
        val output = opti.process(inputIds.toLongArray(), speed, speakerId, hopSize, sampleRate, enableLids, isStopping) ?: return

        if (isStopping())  return
        val audio = output.first
        val duration = output.second
        result.success(duration)
        if (isStopping())  return
        player?.play(inputIds, audio, isStopping)
    }
}