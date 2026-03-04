package com.bookbot.tts

import io.flutter.plugin.common.MethodChannel

/**
 * Deserialized TTS request parameters received from the Dart side.
 *
 * @property requestId   Unique identifier used as the audio-buffer cache key.
 * @property models      ONNX model file names (typically a single entry).
 * @property inputIds    Phoneme token IDs to feed to the ONNX model.
 * @property speed       Speech speed ratio (lower = slower).
 * @property speakerId   Speaker embedding index for multi-speaker models.
 * @property sampleRate  Audio sample rate in Hz (e.g. 44100).
 * @property hopSize     Hop size for duration-to-seconds conversion.
 * @property singleThread When `true`, previous tasks are cancelled before starting a new one.
 * @property playerCompletedDelayed Delay (ms) after playback before returning the result.
 * @property modelVersion Model format version.
 * @property threadCount Number of ONNX Runtime intra-op threads.
 * @property enableLids  Whether to include language ID (`lids`) as an ONNX input.
 * @property result      Flutter method-channel result callback.
 */
@Suppress("UNCHECKED_CAST")
data class RequestInfo (val requestId: String, val models: List<String>,
                        val inputIds: List<Long>, val speed: Double, val speakerId: Long = 0, val sampleRate: Int,
                        val hopSize: Int, val singleThread: Boolean, val playerCompletedDelayed: Int,
                        var modelVersion: Int, val threadCount: Int, val enableLids: Boolean, val result: MethodChannel.Result
) {
    /** Secondary constructor that deserializes from a Flutter arguments map. */
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