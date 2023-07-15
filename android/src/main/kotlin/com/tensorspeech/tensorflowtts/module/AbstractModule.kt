package com.tensorspeech.tensorflowtts.module

import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession


/**
 * @author []" "Xuefeng Ding"">&quot;mailto:xuefeng.ding@outlook.com&quot; &quot;Xuefeng Ding&quot;
 * Created 2020-07-20 17:25
 */
abstract class AbstractModule(private val threadCount: Int, modulePath: String, protected val ortEnv: OrtEnvironment) {
    private var sessionOptions: OrtSession.SessionOptions = OrtSession.SessionOptions().apply {
        setIntraOpNumThreads(threadCount)
    }
    protected var session: OrtSession = ortEnv.createSession(modulePath, sessionOptions)
}