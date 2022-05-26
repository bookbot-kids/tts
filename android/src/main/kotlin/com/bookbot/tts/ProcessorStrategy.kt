package com.bookbot.tts

interface ProcessorStrategy {
    fun initModel(modelPath: String): String?
}

/// The singleton class use to share strategy across plugin & target app
object ProcessorHolder {
    var processorStrategy: ProcessorStrategy? = null
}