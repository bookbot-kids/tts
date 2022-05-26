package com.tensorspeech.tensorflowtts.dispatcher

import android.os.Handler
import android.os.Looper
import android.util.Log
import java.util.concurrent.CopyOnWriteArrayList

/**
 * @author []" "Xuefeng Ding"">&quot;mailto:xuefeng.ding@outlook.com&quot; &quot;Xuefeng Ding&quot;
 * Created 2020-07-28 14:25
 */
class TtsStateDispatcher {
    private val handler = Handler(Looper.getMainLooper())
    private val mListeners = CopyOnWriteArrayList<OnTtsStateListener>()
    fun release() {
        Log.d(TAG, "release: ")
        mListeners.clear()
    }

    fun addListener(listener: OnTtsStateListener) {
        if (mListeners.contains(listener)) {
            return
        }
        Log.d(TAG, "addListener: " + listener.javaClass)
        mListeners.add(listener)
    }

    fun removeListener(listener: OnTtsStateListener) {
        if (mListeners.contains(listener)) {
            Log.d(TAG, "removeListener: " + listener.javaClass)
            mListeners.remove(listener)
        }
    }

    fun onTtsStart(inputIds: List<Int>) {
        Log.d(TAG, "onTtsStart: ")
        if (!mListeners.isEmpty()) {
            for (listener in mListeners) {
                handler.post { listener.onTtsStart(inputIds) }
            }
        }
    }

    fun onTtsStop() {
        Log.d(TAG, "onTtsStop: ")
        if (!mListeners.isEmpty()) {
            for (listener in mListeners) {
                handler.post { listener.onTtsStop() }
            }
        }
    }

    fun onTtsReady() {
        Log.d(TAG, "onTtsReady: ")
        if (!mListeners.isEmpty()) {
            for (listener in mListeners) {
                handler.post { listener.onTtsReady() }
            }
        }
    }

    companion object {
        private const val TAG = "TtsStateDispatcher"

        @JvmStatic
        @Volatile
        var instance: TtsStateDispatcher = TtsStateDispatcher()
        private val INSTANCE_WRITE_LOCK = Any()
    }
}