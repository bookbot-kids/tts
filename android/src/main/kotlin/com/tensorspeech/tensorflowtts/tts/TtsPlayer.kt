package com.tensorspeech.tensorflowtts.tts

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.util.Log
import com.tensorspeech.tensorflowtts.utils.ThreadPoolManager
import java.util.concurrent.LinkedBlockingQueue
import kotlin.math.min

/**
 * @author []" "Xuefeng Ding"">&quot;mailto:xuefeng.ding@outlook.com&quot; &quot;Xuefeng Ding&quot;
 * Created 2020-07-20 18:22
 */
internal class TtsPlayer {
    private val mAudioTrack: AudioTrack = AudioTrack(
        AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
            .build(),
        AudioFormat.Builder()
            .setSampleRate(SAMPLE_RATE)
            .setEncoding(FORMAT)
            .setChannelMask(CHANNEL)
            .build(),
        BUFFER_SIZE,
        AudioTrack.MODE_STREAM, AudioManager.AUDIO_SESSION_ID_GENERATE
    )
    private val mAudioQueue = LinkedBlockingQueue<AudioData>()
    private var mCurrentAudioData: AudioData? = null
    fun play(audioData: AudioData) {
        Log.d(TAG, "add audio data to queue: " + audioData.inputIds)
        mAudioQueue.offer(audioData)
    }

    fun interrupt() {
        mAudioQueue.clear()
        if (mCurrentAudioData != null) {
            mCurrentAudioData?.interrupt()
        }
    }

    internal class AudioData(val inputIds: List<Int>, val audio: FloatArray) {
        var isInterrupt = false
        fun interrupt() {
            isInterrupt = true
        }
    }

    companion object {
        private const val TAG = "TtsPlayer"
        private const val FORMAT = AudioFormat.ENCODING_PCM_FLOAT
        public const val SAMPLE_RATE = 44100
        public const val HOP_SIZE = 521
        private const val CHANNEL = AudioFormat.CHANNEL_OUT_MONO
        private val BUFFER_SIZE = AudioTrack.getMinBufferSize(SAMPLE_RATE, CHANNEL, FORMAT)
    }

    init {
        mAudioTrack.play()
        ThreadPoolManager.instance.getSingleExecutor("audio").execute {
            while (true) {
                try {
                    mCurrentAudioData = mAudioQueue.take()
                    val currentAudioData = mCurrentAudioData ?: return@execute
                    Log.d(TAG, "playing: " + currentAudioData.inputIds)
                    var index = 0
                    while (index < currentAudioData.audio.size && !currentAudioData.isInterrupt) {
                        val buffer = min(BUFFER_SIZE, currentAudioData.audio.size - index)
                        mAudioTrack.write(
                            currentAudioData.audio,
                            index,
                            buffer,
                            AudioTrack.WRITE_BLOCKING
                        )
                        index += BUFFER_SIZE
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Exception: ", e)
                }
            }
        }
    }
}