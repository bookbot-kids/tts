package com.tensorspeech.tensorflowtts.tts

import android.util.Log

class PlayVoiceTask(private val player: TtsBufferPlayer, private val buffer: FloatArray, private  val playerCompletedDelayed: Int, private val onCancelled: () -> Unit,  private val onCompleted: () -> Unit,): Runnable {
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

        player.playBuffer(buffer, isStopping)
        if (playerCompletedDelayed == 0) {
            onCompleted()
        } else {
            Thread.sleep(playerCompletedDelayed.toLong())
            onCompleted()
        }
    }
}