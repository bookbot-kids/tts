package com.bookbot.tts

import io.flutter.plugin.common.MethodChannel

@Suppress("UNCHECKED_CAST")
data class RequestInfo (val requestId: String, val fastSpeechModel: String, val melganModel: String,
                        val inputIds: List<Int>, val speed: Double, val speakerId: Int = 0, val sampleRate: Int,
                        val hopSize: Int, val singleThread: Boolean, val result: MethodChannel.Result
) {
    constructor(map: Map<*, *>, result: MethodChannel.Result) : this(
        map["requestId"] as String,
        map["fastSpeechModel"] as String,
        map["melganModel"] as String,
        (map["inputIds"] as List<*>) as List<Int>,
        map["speed"] as Double,
        map["speakerId"] as Int,
        map["sampleRate"] as Int,
        map["hopSize"] as Int,
        map["singleThread"] as Boolean,
        result
    )
}