package com.bookbot.tts

import android.media.AudioTrack
import com.tensorspeech.tensorflowtts.tts.TtsBufferPlayer

interface ProcessorStrategy {
    fun initModel(version: Int, modelPaths: List<String>, onCompleted: (modelOutputs: List<String>) -> Unit)
    fun playBuffer(player: TtsBufferPlayer, audio: FloatArray, isCancelled: () -> Boolean): Boolean?
    fun audioTrack(sampleRate: Int, format: Int, channel: Int): AudioTrack?
}

/// The singleton class use to share strategy across plugin & target app
object ProcessorHolder {
    var processorStrategy: ProcessorStrategy? = null
}