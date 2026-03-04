package com.tensorspeech.tensorflowtts.dispatcher

/**
 * Listener interface for TTS lifecycle events.
 *
 * Implementations are notified on the main thread via [TtsStateDispatcher].
 */
interface OnTtsStateListener {
    /** Called when the TTS engine has finished initialisation. */
    fun onTtsReady()
    /** Called when speech synthesis begins for the given [inputIds]. */
    fun onTtsStart(inputIds: List<Int>)
    /** Called when speech synthesis or playback is stopped. */
    fun onTtsStop()
}