package com.tensorspeech.tensorflowtts.tts

import ai.onnxruntime.OrtEnvironment
import android.content.Context
import android.os.Build
import android.util.Log
import com.bookbot.tts.ProcessorHolder
import com.bookbot.tts.RequestInfo
import com.tensorspeech.tensorflowtts.dispatcher.OnTtsStateListener
import com.tensorspeech.tensorflowtts.dispatcher.TtsStateDispatcher
import com.tensorspeech.tensorflowtts.module.Opti
import com.tensorspeech.tensorflowtts.utils.ThreadPoolManager
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Future

/**
 * Central TTS manager for Android.
 *
 * Manages ONNX model loading (via [Opti]), speech synthesis, audio buffer
 * caching, and playback through [TtsBufferPlayer]. All inference and
 * playback tasks are submitted to dedicated single-thread executors to
 * prevent concurrent access to the ONNX Runtime session.
 */
class TtsManager {
    /** Per-sample-rate audio player cache. */
    private val players = mutableMapOf<Int, TtsBufferPlayer>()
    /** Single-thread executor for inference tasks (speak / generateVoice). */
    private val threadPool = ThreadPoolManager.instance.getSingleExecutor("tts")
    /** Single-thread executor for audio playback tasks. */
    private val audioPlayerPool = ThreadPoolManager.instance.getSingleExecutor("tts")
    /** Currently running inference task future (for cancellation). */
    private var runningTask: Future<*>? = null
    /** Loaded ONNX models keyed by model file name. */
    private val modelMap = mutableMapOf<String, Opti>()
    /** Active speak-and-play tasks (for stop/cancel). */
    private val tasks = mutableListOf<InputTask>()
    /** Active generate-only tasks (for stop/cancel). */
    private val generateTasks = mutableListOf<GenerateTask>()
    /** Active play-voice tasks (for stop/cancel). */
    private val playerTasks = mutableListOf<PlayVoiceTask>()
    /** Cached audio buffers keyed by request ID. */
    private val audioBuffers =  mutableMapOf<String, FloatArray>()
    /** Whether debug logging is enabled. */
    var logEnabled = true

    /**
     * Loads an ONNX model from assets (or via [ProcessorHolder.processorStrategy]).
     *
     * The model is cached by its key (first element of [models]). Subsequent
     * calls with the same key skip loading and invoke [callback] immediately.
     */
    fun init(context: Context, version: Int, threadCount: Int, models: List<String>, callback: (() -> Unit)? = null) {
        val key = models.first()
        if(modelMap[key] == null) {
            ThreadPoolManager.instance.getSingleExecutor("init").execute {
                ortEnv = ortEnv ?: OrtEnvironment.getEnvironment()
                ortEnv?.let {env ->
                    try {
                        @Suppress("SpellCheckingInspection")
                        val listener = fun (fastspeech: String) {
                            modelMap[key] = Opti(fastspeech, threadCount, env)
                            callback?.invoke()
                        }

                        if(ProcessorHolder.processorStrategy != null) {
                            ProcessorHolder.processorStrategy?.initModel(version, models) {
                                listener(it[0])
                            }
                        } else {
                            listener(copyFile(context, key, version))
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

    /** Copies an ONNX model from Flutter assets to internal storage (if not already present). */
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

    /** Cancels the running inference task and flags all active input tasks to stop. */
    private fun stopTts() {
        runningTask?.cancel(true)
        tasks.forEach {
            it.stop = true
        }
    }

    /** Returns (or creates) a [TtsBufferPlayer] keyed by sample-rate + hop-size. */
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

    /** Runs ONNX inference and immediately plays the audio (speak-and-play). */
    fun speak(request: RequestInfo) {
        stopTts()
        val player = getPlayer(request.sampleRate , request.hopSize)
        val key = request.models.first()
        val processors = modelMap[key] ?: return
        tasks.clear()
        val task = InputTask(processors, request.inputIds, request.speed.toFloat(),
            request.speakerId, request.hopSize, request.sampleRate, request.enableLids, player, request.result )
        tasks.add(task)
        runningTask = threadPool.submit(task)
    }

    /** Plays a previously cached audio buffer identified by [RequestInfo.requestId]. */
    fun playVoice(request: RequestInfo) {
        val buffer = audioBuffers[request.requestId]
        if (buffer != null) {
            val player = getPlayer(request.sampleRate , request.hopSize) ?: return
            val onCancelled: () -> Unit = {
                audioBuffers.remove(request.requestId)
                if(logEnabled) {
                    Log.d(TAG, "[Voice request] [playVoice cancel] ${request.requestId}, ${audioBuffers.size}")
                }
                request.result.success(null)
            }

            val onComplete: () -> Unit = {
                if(logEnabled) {
                    Log.d(TAG, "[Voice request] [playVoice end] ${request.requestId}, ${audioBuffers.size}")
                }

                audioBuffers.remove(request.requestId)
                request.result.success(null)
            }

            if(request.singleThread) {
                playerTasks.forEach {
                    it.stop = true
                }
            }

            val audioTask = PlayVoiceTask(player, buffer, request.playerCompletedDelayed, onCancelled, onComplete)
            playerTasks.add(audioTask)
            audioPlayerPool.submit(audioTask)
            if(logEnabled) {
                Log.d(TAG, "[Voice request] [playVoice start] ${request.requestId}, ${audioBuffers.size}")
            }
        } else {
            request.result.success(null)
        }
    }

    /** Runs ONNX inference and caches the audio buffer for later playback via [playVoice]. */
    fun generateVoice(request: RequestInfo) {
        val key = request.models.first()
        val processors = modelMap[key] ?: return
        val onComplete: (buffer: FloatArray, durations: DoubleArray) -> Unit = { buff, dur ->
            if(logEnabled) {
                Log.d(TAG, "[Voice request] [generate end] ${request.requestId}, ${audioBuffers.size}")
            }

            audioBuffers[request.requestId] = buff
            request.result.success(dur.toList())
        }

        val onCancelled: () -> Unit = {
            audioBuffers.remove(request.requestId)
            if(logEnabled) {
                Log.d(TAG, "[Voice request] [generateVoice cancel] ${request.requestId}, ${audioBuffers.size}")
            }
            request.result.success(listOf<Double>())
        }

        if(request.singleThread) {
            generateTasks.forEach {
                it.stop = true
            }
        }

        val task = GenerateTask(processors, request.inputIds, request.speed.toFloat(), request.speakerId,
            request.hopSize, request.sampleRate, request.enableLids, onComplete, onCancelled)
        generateTasks.add(task)
        runningTask = threadPool.submit(task)
        if(logEnabled) {
            Log.d(TAG, "[Voice request] [generate start] ${request.requestId}, ${audioBuffers.size}")
        }
    }

    /** Releases all cached audio buffers. */
    fun dispose() {
        audioBuffers.clear()
    }

    companion object {
        private const val TAG = "TtsManager"
        var instance: TtsManager = TtsManager()
        private var ortEnv: OrtEnvironment? = null
    }
}