package com.tensorspeech.tensorflowtts.tts

import android.util.Log
import com.tensorspeech.tensorflowtts.dispatcher.TtsStateDispatcher.Companion.instance
import com.tensorspeech.tensorflowtts.module.FastSpeech2
import com.tensorspeech.tensorflowtts.module.MBMelGan
import com.tensorspeech.tensorflowtts.tts.TtsPlayer.AudioData
import com.tensorspeech.tensorflowtts.utils.Processor
import com.tensorspeech.tensorflowtts.utils.ThreadPoolManager
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.LinkedBlockingQueue

/**
 * @author []" "Xuefeng Ding"">&quot;mailto:xuefeng.ding@outlook.com&quot; &quot;Xuefeng Ding&quot;
 * Created 2020-07-28 14:25
 */
internal class InputWorker(fastspeech: String, vocoder: String) {
    private val mInputQueue = LinkedBlockingQueue<InputText>()
    private var mCurrentInputText: InputText? = null
    private val mFastSpeech2: FastSpeech2
    private val mMBMelGan: MBMelGan
    private val mProcessor: Processor
    private val mTtsPlayer: TtsPlayer
    fun processInput(inputIds: List<Int>, speed: Float, speakerId: Int = 0, result: MethodChannel.Result) {
        Log.d(TAG, "add to queue: $inputIds")
        mInputQueue.offer(InputText(inputIds, speed, speakerId, result))
    }

    fun interrupt() {
        mInputQueue.clear()
        if (mCurrentInputText != null) {
            mCurrentInputText?.interrupt()
        }
        mTtsPlayer.interrupt()
    }

    private inner class InputText(val inputIds: List<Int>, private val SPEED: Float, private val speakerId: Int, private val result: MethodChannel.Result) {
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
            mTtsPlayer.play(AudioData(inputIds, audioData))
        }

        fun interrupt() {
            isInterrupt = true
        }
    }

    companion object {
        private const val TAG = "InputWorker"
    }

    init {
        mFastSpeech2 = FastSpeech2(fastspeech)
        mMBMelGan = MBMelGan(vocoder)
        mProcessor = Processor()
        mTtsPlayer = TtsPlayer()
        ThreadPoolManager.instance.getSingleExecutor("worker").execute {
            while (true) {
                try {
                    mCurrentInputText = mInputQueue.take()
                    Log.d(TAG, "processing: " + mCurrentInputText?.inputIds)
                    mCurrentInputText?.inputIds?.let { instance.onTtsStart(it) }
                    mCurrentInputText?.proceed()
                    instance.onTtsStop()
                } catch (e: Exception) {
                    Log.e(TAG, "Exception: ", e)
                }
            }
        }
    }
}