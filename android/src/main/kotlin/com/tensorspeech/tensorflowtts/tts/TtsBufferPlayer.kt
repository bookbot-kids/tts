package com.tensorspeech.tensorflowtts.tts

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.util.Log
import com.tensorspeech.tensorflowtts.utils.ThreadPoolManager
import java.util.concurrent.Future
import kotlin.math.min

class TtsBufferPlayer(sampleRate: Int) {
    private val threadPool = ThreadPoolManager.instance.getSingleExecutor("audio")
    private val bufferSize = AudioTrack.getMinBufferSize(sampleRate, CHANNEL, FORMAT)
    private val mAudioTrack: AudioTrack = AudioTrack(
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

    @Volatile private var isPlaying = false
    @Volatile private var isInterrupt = false
    private var task: Future<*>? = null

    fun play(inputIds: List<Int>, audio: FloatArray) {
        Log.d(TAG, "start playing: $inputIds")
        if(isPlaying) {
            isInterrupt = true
            task?.cancel(true)
        }

        submitTask(audio)
    }

    private fun submitTask(audio: FloatArray) {
        task = threadPool.submit {
            isPlaying = true
            var index = 0
            while (index < audio.size && !isInterrupt) {
                val buffer = min(bufferSize, audio.size - index)
                mAudioTrack.write(
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