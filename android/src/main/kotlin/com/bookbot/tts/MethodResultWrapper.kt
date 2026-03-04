package com.bookbot.tts

import io.flutter.plugin.common.MethodChannel

/**
 * Thread-safe wrapper around [MethodChannel.Result] that ensures only the
 * first call to [success], [error], or [notImplemented] is forwarded.
 *
 * Prevents `IllegalStateException` when a result is submitted multiple
 * times due to concurrent or racing callbacks.
 */
class TtsMethodResultWrapper(private val methodResult: MethodChannel.Result): MethodChannel.Result {
    /** Guards against duplicate submissions. */
    private var hasSubmitted: Boolean

    init {
        hasSubmitted = false
    }

    override fun success(result: Any?) {
        if(!hasSubmitted) {
            hasSubmitted = true
            methodResult.success(result)
        }
    }

    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
        if(!hasSubmitted) {
            hasSubmitted = true
            methodResult.error(errorCode, errorMessage, errorDetails)
        }
    }

    override fun notImplemented() {
        if(!hasSubmitted) {
            hasSubmitted = true
            methodResult.notImplemented()
        }
    }
}