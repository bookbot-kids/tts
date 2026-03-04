package com.tensorspeech.tensorflowtts.module

import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession


/**
 * Base class for ONNX Runtime model processors on Android.
 *
 * Creates an [OrtSession] from the given model file path and configures
 * the number of intra-op threads. Concrete subclasses ([Opti],
 * [FastSpeech2], [MBMelGan]) add model-specific inference logic.
 *
 * @param threadCount Number of intra-op threads for ONNX Runtime.
 * @param modulePath  Absolute path to the ONNX model file.
 * @param ortEnv      ONNX Runtime environment.
 */
abstract class AbstractModule(private val threadCount: Int, modulePath: String, protected val ortEnv: OrtEnvironment) {
    /** Session options configured with the requested thread count. */
    private var sessionOptions: OrtSession.SessionOptions = OrtSession.SessionOptions().apply {
        setIntraOpNumThreads(threadCount)
    }
    /** ONNX Runtime session used for inference. */
    protected var session: OrtSession = ortEnv.createSession(modulePath, sessionOptions)
}