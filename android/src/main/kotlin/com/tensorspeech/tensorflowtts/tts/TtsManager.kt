package com.tensorspeech.tensorflowtts.tts

import ai.onnxruntime.OrtEnvironment
import android.content.Context
import android.os.Build
import android.util.Log
import com.bookbot.tts.ProcessorHolder
import com.bookbot.tts.RequestInfo
import com.tensorspeech.tensorflowtts.dispatcher.OnTtsStateListener
import com.tensorspeech.tensorflowtts.dispatcher.TtsStateDispatcher
import com.tensorspeech.tensorflowtts.module.Piper
import com.tensorspeech.tensorflowtts.utils.ThreadPoolManager
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Future

/**
 * @author []" "Xuefeng Ding"">&quot;mailto:xuefeng.ding@outlook.com&quot; &quot;Xuefeng Ding&quot;
 * Created 2020-07-28 14:25
 */
class TtsManager {
    private val players = mutableMapOf<Int, TtsBufferPlayer>()
    private val threadPool = ThreadPoolManager.instance.getSingleExecutor("tts")
    private var runningTask: Future<*>? = null
    private val modelMap = mutableMapOf<String, Piper>()
    private val tasks = mutableListOf<InputTask>()
    private val audioBuffers =  mutableMapOf<String, FloatArray>()
    var logEnabled = true

    fun init(context: Context, version: Int, threadCount: Int, fastSpeechModel: String, melganModel: String, callback: (() -> Unit)? = null) {
        val key = fastSpeechModel + melganModel
        if(modelMap[key] == null) {
            ThreadPoolManager.instance.getSingleExecutor("init").execute {
                ortEnv = ortEnv ?: OrtEnvironment.getEnvironment()
                ortEnv?.let {env ->
                    try {
                        @Suppress("SpellCheckingInspection")
                        val listener = fun (fastspeech: String, vocoder: String) {
                            modelMap[key] = Piper(fastspeech, threadCount, env)
                            callback?.invoke()
                        }

                        if(ProcessorHolder.processorStrategy != null) {
                            ProcessorHolder.processorStrategy?.initModel(version, arrayListOf(fastSpeechModel, melganModel)) {
                                listener(it[0], it[1])
                            }
                        } else {
                            listener(copyFile(context, fastSpeechModel, version), copyFile(context, melganModel, version))
                        }

                    } catch (e: Exception) {
                        Log.e(TAG, "mWorker init failed", e)
                    }
                    TtsStateDispatcher.instance.onTtsReady()
                }
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

    private fun copyFile(context: Context, strOutFileName: String, version: Int): String {
        if (logEnabled) {
            Log.d(TAG, "start copy file $strOutFileName")
        }

        val dir = File(context.filesDir, "$version")
        if (!dir.exists()) {
            dir.mkdirs()
        }

        val f = File(dir.absolutePath, strOutFileName)
        if (f.exists()) {
            if (logEnabled) {
                Log.d(TAG, "file exists $strOutFileName")
            }
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
                    if (logEnabled) {
                        Log.d(TAG, "Copy task successful")
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "copyFile: Failed to copy", e)
        } finally {
            if (logEnabled) {
                Log.d(TAG, "end copy file $strOutFileName")
            }
        }
        return f.absolutePath
    }

    private fun stopTts() {
        runningTask?.cancel(true)
        tasks.forEach {
            it.stop = true
        }
    }

    private fun getPlayer(sampleRate: Int, hopSize: Int): TtsBufferPlayer? {
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

        return player
    }

    fun speak(request: RequestInfo) {
        stopTts()
        val player = getPlayer(request.sampleRate , request.hopSize)
        val key = request.fastSpeechModel + request.melganModel
        val processors = modelMap[key] ?: return
        tasks.clear()
        val task = InputTask(processors, request.inputIds.map { it.toLong() }, request.speed.toFloat(), request.speakerId, player, request.result )
        tasks.add(task)
        runningTask = threadPool.submit(task)
    }

    fun dispose() {
        audioBuffers.clear()
    }

    companion object {
        private const val TAG = "TtsManager"
        var instance: TtsManager = TtsManager()
        private var ortEnv: OrtEnvironment? = null
    }
}