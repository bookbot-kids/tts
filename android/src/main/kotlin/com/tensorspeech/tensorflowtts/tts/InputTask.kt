package com.tensorspeech.tensorflowtts.tts

import android.util.Log
import com.tensorspeech.tensorflowtts.module.FastSpeech2
import com.tensorspeech.tensorflowtts.module.MBMelGan
import com.tensorspeech.tensorflowtts.utils.Processor
import io.flutter.plugin.common.MethodChannel

class InputTask(fastspeech: String, vocoder: String) {
    private var mCurrentInputText: InputText? = null
    private val mFastSpeech2: FastSpeech2
    private val mMBMelGan: MBMelGan
    private val mProcessor: Processor

    init {
        mFastSpeech2 = FastSpeech2(fastspeech)
        mMBMelGan = MBMelGan(vocoder)
        mProcessor = Processor()
    }

    fun processInput(inputIds: List<Int>,
                      speed: Float,
                      speakerId: Int = 0,
                      player: TtsBufferPlayer?,
                      result: MethodChannel.Result) {
        mCurrentInputText = InputText(inputIds, speed, speakerId, player, result)
        mCurrentInputText?.proceed()
    }

    fun interrupt() {
        mCurrentInputText?.interrupt()
    }

    companion object {
        private const val TAG = "InputWorker"
    }

    private inner class InputText(val inputIds: List<Int>, private val SPEED: Float,
                                  private val speakerId: Int,
                                  private var player: TtsBufferPlayer?,
                                  private val result: MethodChannel.Result) {
        private var isInterrupt = false
        fun proceed() {
            val time = System.currentTimeMillis()
            val output = mFastSpeech2.getMelSpectrogram(inputIds.toIntArray(), SPEED, speakerId)
            result.success(output.second.map { it.toDouble() })
            if (isInterrupt) {
                Log.d(TAG, "proceed: interrupt")
                return
            }
            val encoderTime = System.currentTimeMillis()
            val audioData = mMBMelGan.getAudio(output.first)
            if (isInterrupt) {
                Log.d(TAG, "proceed: interrupt")
                return
            }
            val vocoderTime = System.currentTimeMillis()
            Log.d(
                TAG,
                "Time cost: " + (encoderTime - time) + "+" + (vocoderTime - encoderTime) + "=" + (vocoderTime - time)
            )

            player?.play(inputIds, audioData)
        }

        fun interrupt() {
            isInterrupt = true
        }
    }
}