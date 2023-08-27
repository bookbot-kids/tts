package com.tensorspeech.tensorflowtts.tts

import android.util.Log
import com.tensorspeech.tensorflowtts.module.Piper
import io.flutter.plugin.common.MethodChannel

class InputTask(private val piper: Piper,
                private val inputIds: List<Long>, private val speed: Float,
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
        val output = piper.infer(inputIds.toLongArray(), speakerId, isStopping) ?: return

        if (isStopping())  return
        val audioData = output.first
        val audio = audioData.flatMap { it.asIterable() }.flatMap { it.asIterable() }.toFloatArray()
        val duration = output.second.map { it.toDouble() }
        if (isStopping())  return
        result.success(duration)
        if (isStopping())  return
        player?.play(inputIds, audio, isStopping)
    }
}