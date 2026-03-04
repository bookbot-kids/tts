package com.bookbot.tts

import android.media.AudioTrack
import com.tensorspeech.tensorflowtts.tts.TtsBufferPlayer

/**
 * Strategy interface for external model loading and audio playback.
 *
 * Host applications can implement this interface and assign an instance to
 * [ProcessorHolder.processorStrategy] to override the default behaviour
 * (e.g. to provide custom model downloading or a custom audio player).
 */
interface ProcessorStrategy {
    /** Loads ONNX models and invokes [onCompleted] with resolved file paths. */
    fun initModel(version: Int, modelPaths: List<String>, onCompleted: (modelOutputs: List<String>) -> Unit)
    /** Plays PCM audio through a custom player. Returns `true` if handled. */
    fun playBuffer(player: TtsBufferPlayer, audio: FloatArray, isCancelled: () -> Boolean): Boolean?
    /** Returns a custom [AudioTrack] instance, or `null` to use the default. */
    fun audioTrack(sampleRate: Int, format: Int, channel: Int): AudioTrack?
}

/**
 * Singleton holder for sharing a [ProcessorStrategy] between the plugin
 * and the host application.
 */
object ProcessorHolder {
    /** The currently registered strategy, or `null` for default behaviour. */
    var processorStrategy: ProcessorStrategy? = null
}