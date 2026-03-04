package com.tensorspeech.tensorflowtts.dispatcher

import android.os.Handler
import android.os.Looper
import android.util.Log
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Thread-safe dispatcher that broadcasts TTS lifecycle events to registered
 * [OnTtsStateListener] instances on the main thread.
 */
class TtsStateDispatcher {
    /** Handler bound to the main looper for posting listener callbacks. */
    private val handler = Handler(Looper.getMainLooper())
    /** Thread-safe list of registered listeners. */
    private val mListeners = CopyOnWriteArrayList<OnTtsStateListener>()

    /** Removes all registered listeners. */
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