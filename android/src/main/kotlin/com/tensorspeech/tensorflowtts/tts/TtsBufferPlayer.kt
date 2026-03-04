package com.tensorspeech.tensorflowtts.tts

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.util.Log
import com.bookbot.tts.ProcessorHolder
import com.tensorspeech.tensorflowtts.utils.ThreadPoolManager
import java.util.concurrent.Future
import kotlin.math.min

/**
 * PCM audio buffer player backed by [AudioTrack] (mono, Float32).
 *
 * Writes PCM Float32 samples in streaming mode and supports cancellation.
 * Can delegate playback to an external [ProcessorStrategy] if one is set.
 *
 * @param sampleRate Audio sample rate in Hz (e.g. 44100).
 */
@Suppress("MemberVisibilityCanBePrivate", "CanBeParameter")
class TtsBufferPlayer(val sampleRate: Int) {
    /** Single-thread executor for async audio writes. */
    val threadPool = ThreadPoolManager.instance.getSingleExecutor("audio")
    /** Minimum buffer size for the configured sample rate / channel / format. */
    val bufferSize = AudioTrack.getMinBufferSize(sampleRate, CHANNEL, FORMAT)
    private val audioTrack: AudioTrack = AudioTrack(
        AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
            .build(),
        AudioFormat.Builder()
            .setSampleRate(sampleRate)
            .setEncoding(FORMAT)
            .setChannelMask(CHANNEL)
            .build(),
        bufferSize,
        AudioTrack.MODE_STREAM, AudioManager.AUDIO_SESSION_ID_GENERATE
    )

    /** Whether playback is currently in progress. */
    @Volatile var isPlaying = false
    /** Flag to interrupt the current playback loop. */
    @Volatile var isInterrupt = false
    /** Future for the async playback task (for cancellation). */
    var task: Future<*>? = null

    /** Starts asynchronous playback; interrupts any in-progress playback first. */
    fun play(inputIds: List<Long>, audio: FloatArray, isCancelled: () -> Boolean) {
        Log.d(TAG, "start playing: $inputIds, audio ${audio.size}")
        if(isPlaying || isCancelled()) {
            isInterrupt = true
            task?.cancel(true)
        }

        submitTask(audio, isCancelled)
    }

    /** Returns the external strategy's AudioTrack if available, otherwise the default. */
    fun getAudioTrack(): AudioTrack {
        return ProcessorHolder.processorStrategy?.audioTrack(sampleRate, CHANNEL, FORMAT) ?: audioTrack
    }

    /** Submits a chunked write loop to the audio thread pool. */
    private fun submitTask(audio: FloatArray, isCancelled: () -> Boolean) {
        task = threadPool.submit {
            if(ProcessorHolder.processorStrategy?.playBuffer(this, audio, isCancelled) != true) {
                isPlaying = true
                var index = 0
                getAudioTrack().play()
                while (index < audio.size && !isInterrupt && !isCancelled()) {
                    val buffer = min(bufferSize, audio.size - index)
                    getAudioTrack().write(
                        audio,
                        index,
                        buffer,
                        AudioTrack.WRITE_BLOCKING
                    )
                    index += bufferSize
                    Log.d(TAG, "play $index")
                }
                isPlaying = false
                isInterrupt = false
                Log.d(TAG, "play completed")
            }
        }
    }

    /** Synchronous playback – writes PCM chunks in the caller's thread. */
    fun playBuffer(audio: FloatArray, isCancelled: () -> Boolean) {
        if(ProcessorHolder.processorStrategy?.playBuffer(this, audio, isCancelled) != true) {
            isPlaying = true
            var index = 0
            getAudioTrack().play()
            while (index < audio.size && !isInterrupt && !isCancelled()) {
                val buffer = min(bufferSize, audio.size - index)
                getAudioTrack().write(
                    audio,
                    index,
                    buffer,
                    AudioTrack.WRITE_BLOCKING
                )
                index += bufferSize
                Log.d(TAG, "play $index")
            }
            isPlaying = false
            isInterrupt = false
            Log.d(TAG, "play completed")
        }
    }

    companion object {
        private const val TAG = "TtsPlayer"
        private const val FORMAT = AudioFormat.ENCODING_PCM_FLOAT
        private const val CHANNEL = AudioFormat.CHANNEL_OUT_MONO
    }
}