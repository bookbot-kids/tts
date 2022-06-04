package com.tensorspeech.tensorflowtts.tts

import android.content.Context
import android.os.Build
import android.util.Log
import com.bookbot.tts.ProcessorHolder
import com.tensorspeech.tensorflowtts.dispatcher.OnTtsStateListener
import com.tensorspeech.tensorflowtts.dispatcher.TtsStateDispatcher
import com.tensorspeech.tensorflowtts.utils.ThreadPoolManager
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

/**
 * @author []" "Xuefeng Ding"">&quot;mailto:xuefeng.ding@outlook.com&quot; &quot;Xuefeng Ding&quot;
 * Created 2020-07-28 14:25
 */
class TtsManager {
    private var mWorker: InputTask? = null
    private val workerMap = mutableMapOf<String, InputTask?>()
    private val players = mutableMapOf<Int, TtsBufferPlayer>()
    fun init(context: Context, fastSpeechModel: String, melganModel: String, callback: (() -> Unit)? = null) {
        val key = fastSpeechModel + melganModel
        if(workerMap[key] == null) {
            ThreadPoolManager.instance.getSingleExecutor("init").execute {
                try {
                    val fastspeech = ProcessorHolder.processorStrategy?.initModel(fastSpeechModel) ?: copyFile(context, fastSpeechModel)
                    val vocoder = ProcessorHolder.processorStrategy?.initModel(melganModel) ?: copyFile(context, melganModel)
                    for(worker in workerMap.values) {
                        worker?.interrupt()
                    }

                    workerMap.clear()
                    mWorker = InputTask(fastspeech, vocoder)
                    workerMap[key] = mWorker
                    callback?.invoke()
                } catch (e: Exception) {
                    Log.e(TAG, "mWorker init failed", e)
                }
                TtsStateDispatcher.instance.onTtsReady()
            }

            TtsStateDispatcher.instance.addListener(object : OnTtsStateListener {
                override fun onTtsReady() {}
                override fun onTtsStart(inputIds: List<Int>) {}
                override fun onTtsStop() {}
            })
        } else {
            callback?.invoke()
        }
    }

    private fun copyFile(context: Context, strOutFileName: String): String {
        Log.d(TAG, "start copy file $strOutFileName")
        val file = context.filesDir
        val tmpFile = file.absolutePath + "/" + strOutFileName
        val f = File(tmpFile)
        if (f.exists()) {
            Log.d(TAG, "file exists $strOutFileName")
            return f.absolutePath
        }
        try {
            FileOutputStream(f).use { myOutput ->
                context.assets.open(strOutFileName).use { myInput ->
                    val buffer = ByteArray(1024)
                    var length = myInput.read(buffer)
                    while (length > 0) {
                        myOutput.write(buffer, 0, length)
                        length = myInput.read(buffer)
                    }
                    myOutput.flush()
                    Log.d(TAG, "Copy task successful")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "copyFile: Failed to copy", e)
        } finally {
            Log.d(TAG, "end copy file $strOutFileName")
        }
        return f.absolutePath
    }

    fun stopTts() {
        mWorker?.interrupt()
    }

    fun speak(inputIds: List<Int>, speed: Float, interrupt: Boolean, sampleRate: Int, hopSize: Int, speakerId: Int = 0, result: MethodChannel.Result) {
        if (interrupt) {
            stopTts()
        }

        val playerKey = sampleRate + hopSize
        val player = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            players.putIfAbsent(playerKey, TtsBufferPlayer(sampleRate))
            players[playerKey]
        } else {
            if (!players.containsKey(playerKey)) {
                players[playerKey] = TtsBufferPlayer(sampleRate)
            }
            players[playerKey]
        }

        ThreadPoolManager.instance.execute {
            mWorker?.processInput(inputIds, speed, speakerId, player, result)
        }
    }

    companion object {
        private const val TAG = "TtsManager"
        var instance: TtsManager = TtsManager()
    }
}