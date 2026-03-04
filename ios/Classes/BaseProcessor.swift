import onnxruntime_objc

/// Base class for ONNX Runtime model processors on iOS.
///
/// Provides lazy, thread-safe session initialisation shared by all concrete
/// processors (``Opti``, ``FastSpeech2``, ``MBMelGan``).
class BaseProcessor {
    /// Local URL pointing to the ONNX model file.
    var url: URL
    /// ONNX Runtime session; lazily created by ``initSession()``.
    var ortSession: ORTSession?
    /// ONNX Runtime environment shared across processors.
    var ortEnv: ORTEnv?
    /// Number of intra-op threads to use for inference.
    var threadCount: Int
    /// Lock that serialises session creation to prevent races.
    private let locker = NSLock()

    /// Designated initialiser.
    init(ortEnv: ORTEnv?, url: URL, threadCount: Int) {
        self.url = url
        self.ortEnv = ortEnv
        self.threadCount = threadCount
    }

    /// Creates the ONNX Runtime session if it has not been created yet.
    /// Thread-safe via an `NSLock`.
    func initSession() {
        guard let env = ortEnv else {
            return
        }
        
        locker.lock()
        if ortSession == nil {
            let options = try? ORTSessionOptions()
            try? options?.setIntraOpNumThreads(Int32(threadCount))
            ortSession = try? ORTSession(env: env, modelPath: url.path, sessionOptions: options)
        }
        locker.unlock()
    }
}
