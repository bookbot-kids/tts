package com.bookbot.tts

import io.flutter.plugin.common.MethodChannel

@Suppress("UNCHECKED_CAST")
data class RequestInfo (val requestId: String, val models: List<String>,
                        val inputIds: List<Long>, val speed: Double, val speakerId: Long = 0, val sampleRate: Int,
                        val hopSize: Int, val singleThread: Boolean, val playerCompletedDelayed: Int,
                        var modelVersion: Int, val threadCount: Int, val enableLids: Boolean, val result: MethodChannel.Result
) {
    constructor(map: Map<*, *>, result: MethodChannel.Result) : this(
        map["requestId"] as String,
        (map["models"] as List<*>) as List<String>,
        ((map["inputIds"] as List<*>) as List<Int>).map { it.toLong() },
        map["speed"] as Double,
        (map["speakerId"] as Int).toLong(),
        map["sampleRate"] as Int,
        map["hopSize"] as Int,
        map["singleThread"] as Boolean,
        map["playerCompletedDelayed"] as Int,
        map["modelVersion"] as Int,
        map["threadCount"] as Int,
        map["enableLids"] as Boolean,
        result
    )
}