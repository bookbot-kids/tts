package com.bookbot.tts

import com.tensorspeech.tensorflowtts.tts.TtsBufferPlayer

interface ProcessorStrategy {
    fun initModel(version: Int, modelPaths: List<String>, onCompleted: (modelOutputs: List<String>) -> Unit)
    fun playBuffer(player: TtsBufferPlayer, audio: FloatArray, isCancelled: () -> Boolean): Boolean?
}

/// The singleton class use to share strategy across plugin & target app
object ProcessorHolder {
    var processorStrategy: ProcessorStrategy? = null
}