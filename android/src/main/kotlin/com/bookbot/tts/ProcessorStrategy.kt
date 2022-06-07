package com.bookbot.tts

interface ProcessorStrategy {
    fun initModel(modelPaths: List<String>, onCompleted: (modelOutputs: List<String>) -> Unit)
}

/// The singleton class use to share strategy across plugin & target app
object ProcessorHolder {
    var processorStrategy: ProcessorStrategy? = null
}