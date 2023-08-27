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

@Suppress("MemberVisibilityCanBePrivate", "CanBeParameter")
class TtsBufferPlayer(val sampleRate: Int) {
    val threadPool = ThreadPoolManager.instance.getSingleExecutor("audio")
    val bufferSize = AudioTrack.getMinBufferSize(sampleRate, CHANNEL, FORMAT)
    val audioTrack: AudioTrack = AudioTrack(
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

    @Volatile var isPlaying = false
    @Volatile var isInterrupt = false
    var task: Future<*>? = null

    fun play(inputIds: List<Long>, audio: FloatArray, isCancelled: () -> Boolean) {
        Log.d(TAG, "start playing: $inputIds, audio ${audio.size}")
        if(isPlaying || isCancelled()) {
            isInterrupt = true
            task?.cancel(true)
        }

        submitTask(audio, isCancelled)
    }

    private fun submitTask(audio: FloatArray, isCancelled: () -> Boolean) {
        task = threadPool.submit {
            if(ProcessorHolder.processorStrategy?.playBuffer(this, audio, isCancelled) != true) {
                isPlaying = true
                var index = 0
                audioTrack.play()
                while (index < audio.size && !isInterrupt && !isCancelled()) {
                    val buffer = min(bufferSize, audio.size - index)
                    audioTrack.write(
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

    fun playBuffer(audio: FloatArray, isCancelled: () -> Boolean) {
        if(ProcessorHolder.processorStrategy?.playBuffer(this, audio, isCancelled) != true) {
            isPlaying = true
            var index = 0
            audioTrack.play()
            while (index < audio.size && !isInterrupt && !isCancelled()) {
                val buffer = min(bufferSize, audio.size - index)
                audioTrack.write(
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