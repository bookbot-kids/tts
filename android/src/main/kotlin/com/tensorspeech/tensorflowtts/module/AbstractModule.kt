package com.tensorspeech.tensorflowtts.module

import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession


/**
 * Base class for ONNX Runtime model processors on Android.
 *
 * Creates an [OrtSession] from the given model file path and configures
 * the number of intra-op threads and execution provider. Concrete
 * subclasses ([Opti], [FastSpeech2], [MBMelGan]) add model-specific
 * inference logic.
 *
 * @param threadCount Number of intra-op threads for ONNX Runtime.
 * @param modulePath  Absolute path to the ONNX model file.
 * @param ortEnv      ONNX Runtime environment.
 * @param provider    Execution provider (CPU, XNNPACK, NNAPI).
 */
abstract class AbstractModule(
    private val threadCount: Int,
    modulePath: String,
    protected val ortEnv: OrtEnvironment,
    provider: Provider = Provider.CPU,
) {
    /** ONNX Runtime execution provider. */
    enum class Provider {
        /** Default ONNX Runtime CPU execution provider. */
        CPU,
        /** XNNPACK EP — typically fastest on ARM with multi-threading. */
        XNNPACK,
        /** Android NNAPI EP — may fail on unsupported ops (e.g. GATHER rank mismatch). */
        NNAPI;

        companion object {
            /** Parses a case-insensitive provider name. Falls back to [CPU]. */
            fun fromString(name: String?): Provider = when (name?.uppercase()) {
                "XNNPACK" -> XNNPACK
                "NNAPI" -> NNAPI
                else -> CPU
            }
        }
    }

    /** Session options configured with the requested thread count and provider. */
    private var sessionOptions: OrtSession.SessionOptions = OrtSession.SessionOptions().apply {
        setIntraOpNumThreads(threadCount)
        when (provider) {
            Provider.CPU -> { /* default EP, nothing to add */ }
            Provider.XNNPACK -> addXnnpack(mapOf("intra_op_num_threads" to threadCount.toString()))
            Provider.NNAPI -> addNnapi()
        }
    }

    /** ONNX Runtime session used for inference. */
    protected var session: OrtSession = ortEnv.createSession(modulePath, sessionOptions)
}
