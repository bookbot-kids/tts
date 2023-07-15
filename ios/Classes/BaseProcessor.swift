import onnxruntime_objc

class BaseProcessor {
    var url: URL
    var ortSession: ORTSession?
    var ortEnv: ORTEnv?
    var threadCount: Int
    private let locker = NSLock()
    
    init(ortEnv: ORTEnv?, url: URL, threadCount: Int) {
        self.url = url
        self.ortEnv = ortEnv
        self.threadCount = threadCount
    }
    
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
