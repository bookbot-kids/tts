package com.tensorspeech.tensorflowtts.tts

import android.content.Context
import android.util.Log
import com.tensorspeech.tensorflowtts.dispatcher.OnTtsStateListener
import com.tensorspeech.tensorflowtts.dispatcher.TtsStateDispatcher
import com.tensorspeech.tensorflowtts.utils.ThreadPoolManager
import java.io.File
import java.io.FileOutputStream

/**
 * @author []" "Xuefeng Ding"">&quot;mailto:xuefeng.ding@outlook.com&quot; &quot;Xuefeng Ding&quot;
 * Created 2020-07-28 14:25
 */
class TtsManager {
    private var mWorker: InputWorker? = null
    private val workerMap = mutableMapOf<String, InputWorker?>()
    fun init(context: Context, fastSpeechModel: String, melganModel: String, callback: (() -> Unit)? = null) {
        val key = fastSpeechModel + melganModel
        if(workerMap[key] == null) {
            ThreadPoolManager.instance.getSingleExecutor("init").execute {
                try {
                    val fastspeech = copyFile(context, fastSpeechModel)
                    val vocoder = copyFile(context, melganModel)
                    for(worker in workerMap.values) {
                        worker?.interrupt()
                    }

                    workerMap.clear()
                    mWorker = InputWorker(fastspeech, vocoder)
                    workerMap[key] = mWorker
                    callback?.invoke()
                } catch (e: Exception) {
                    Log.e(TAG, "mWorker init failed", e)
                }
                TtsStateDispatcher.instance.onTtsReady()
            }

            TtsStateDispatcher.instance.addListener(object : OnTtsStateListener {
                override fun onTtsReady() {}
                override fun onTtsStart(text: String?) {}
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

    fun speak(inputText: String?, speed: Float, interrupt: Boolean) {
        if (interrupt) {
            stopTts()
        }
        ThreadPoolManager.instance.execute { inputText?.let { mWorker?.processInput(it, speed) } }
    }

    companion object {
        private const val TAG = "TtsManager"
        var instance: TtsManager = TtsManager()
        private const val FASTSPEECH2_MODULE = "fastspeech2_quant.tflite"
        private const val MELGAN_MODULE = "mbmelgan.tflite"
    }
}