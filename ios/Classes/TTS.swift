//
//  TTS.swift
//  TF TTS Demo
//
//  Created by 안창범 on 2021/03/16.
//

import Foundation
import AVFoundation
import Flutter
import onnxruntime_objc

/// Thread-safe singleton that caches generated audio buffers keyed by request ID.
///
/// Audio is stored as raw `Data` (PCM Float32) so it can be played later
/// without re-running ONNX inference.
public class BufferHolder {
    /// Shared singleton instance.
    static let shared: BufferHolder = BufferHolder()

    /// Map of request ID → raw PCM audio data.
    var audioBuffers = Dictionary<String, Data>()
}

/// Deserialized TTS request parameters received from the Dart side.
///
/// Populated from the `FlutterMethodCall.arguments` dictionary.
public class RequestInfo {
    /// ONNX model file names to load (typically a single entry).
    let models: [String]
    /// Phoneme token IDs to feed to the ONNX model.
    let inputIds: [Int64]
    /// Speech speed ratio (lower = slower).
    let speed: Float
    /// Speaker embedding index for multi-speaker models.
    let speakerId: Int64
    /// Audio sample rate in Hz (e.g. 44100).
    let sampleRate: Int
    /// Hop size used to convert duration frames to seconds.
    let hopSize: Int
    /// Unique identifier for this request, used as the buffer cache key.
    let requestId: String
    /// When `true`, previous operations are cancelled before starting a new one.
    let singleThread: Bool
    /// Delay in milliseconds after playback completes before returning the result.
    let playerCompletedDelayed: Int
    /// Whether debug logging is enabled.
    let logEnabled: Bool
    /// Number of ONNX Runtime intra-op threads.
    let threadCount: Int
    /// Whether to include language ID (`lids`) as an ONNX input.
    let enableLids: Bool

    /// Initialises from a Flutter method-call arguments dictionary.
    init(args: [String: Any]) {
        self.models = args["models"] as! Array<String>
        self.inputIds = args["inputIds"] as! Array<Int64>
        self.speed = Float(truncating: args["speed"] as! NSNumber)
        self.speakerId = Int64(args["speakerId"] as! Int)
        self.sampleRate = args["sampleRate"] as! Int
        self.hopSize = args["hopSize"] as! Int
        self.requestId = args["requestId"] as! String
        self.singleThread = args["singleThread"] as! Bool
        self.playerCompletedDelayed = args["playerCompletedDelayed"] as? Int ?? 0
        self.logEnabled = args["logEnabled"] as? Bool ?? true
        self.threadCount = args["threadCount"] as? Int ?? 1
        self.enableLids = args["enableLids"] as? Bool ?? false        
    }
}


/// Core TTS engine for iOS.
///
/// Manages ONNX model loading (via ``Opti``), speech synthesis, audio
/// playback (via `AVAudioEngine` / `AVAudioPlayerNode`), and request
/// queueing through serial `OperationQueue`s.
public class TTS {
    /// ONNX inference processor; `nil` until a model is loaded.
    var opti: Opti?
    /// Tracks which model keys have already been loaded (key → `true`).
    private var modelMap = [String:Bool]()

    /// Audio engine used for standalone playback (when no external processor is set).
    private var engine: AVAudioEngine?
    /// Audio player node attached to `engine`.
    private var player: AVAudioPlayerNode?
    /// Sample buffer synchronizer (reserved for advanced playback scenarios).
    private let sampleBufferRenderSynchronizer = AVSampleBufferRenderSynchronizer()

    /// Sample buffer audio renderer (reserved for advanced playback scenarios).
    private let sampleBufferAudioRenderer = AVSampleBufferAudioRenderer()
    /// Serial queue for inference operations (speak / generateVoice).
    var operationQueue: OperationQueue = OperationQueue()
    /// Serial queue for audio playback operations (playVoice).
    var audioOperationQueue: OperationQueue = OperationQueue()
    /// Whether debug logging is enabled.
    var logEnabled = true
    /// Number of ONNX Runtime intra-op threads.
    var threadCount = 1

    /// Configures serial operation queues and initialises the audio engine
    /// (only when no external processor strategy delegate is set).
    init() {
        sampleBufferRenderSynchronizer.addRenderer(sampleBufferAudioRenderer)
        operationQueue.maxConcurrentOperationCount = 1
        audioOperationQueue.maxConcurrentOperationCount = 1
        if(MlProcessorStrategy.shared().delegate == nil) {
            initAudioEngine()
        }
    }

    /// Creates a fresh `AVAudioEngine` and `AVAudioPlayerNode` for standalone playback.
    private func initAudioEngine() {
        engine = AVAudioEngine()
        player = AVAudioPlayerNode()
    }
    
    /// Loads an ONNX model from the bundle or via the external processor strategy.
    ///
    /// The model is cached by its key (first element of `models`). Subsequent
    /// calls with the same key return immediately via `onCompleted(true)`.
    ///
    /// - Parameters:
    ///   - models: Array of model file names (only the first is used).
    ///   - onCompleted: Callback indicating whether loading succeeded.
    public func initModel(models: [String], onCompleted:@escaping((Bool) -> Void)) {
        let key  = models.first ?? ""
        if(modelMap[key] == nil) {
            modelMap.removeAll()
            if(MlProcessorStrategy.shared().delegate != nil) {
                MlProcessorStrategy.shared().delegate.urls(for: models) { urls in
                    guard let modelUrls = urls, let modelUrl = modelUrls[0] as? URL else {
                        onCompleted(false)
                        return
                    }
                    
                    let ortEnv = try? ORTEnv(loggingLevel: ORTLoggingLevel.warning)
                    self.opti = Opti(ortEnv: ortEnv, url: modelUrl, threadCount: self.threadCount)
                    self.modelMap[key] = true
                    onCompleted(self.opti != nil)
                }
            } else {
                let modelUrl =  Bundle.main.url(forResource: (key as NSString).deletingPathExtension, withExtension: "onnx")
                guard let modelUrl = modelUrl else {
                    if self.logEnabled {
                        print("can't read model url \(key) ")
                    }
                    
                    onCompleted(false)
                    return
                }
                
                let ortEnv = try? ORTEnv(loggingLevel: ORTLoggingLevel.warning)
                self.opti = Opti(ortEnv: ortEnv, url: modelUrl, threadCount: self.threadCount)
                modelMap[key] = true
                onCompleted(opti != nil)
            }
        } else {
            onCompleted(true)
        }
    }

    /// Runs ONNX inference and immediately plays the generated audio.
    ///
    /// Cancels any previously queued operations before submitting a new
    /// ``RequesTask`` to the serial `operationQueue`.
    public func speak(requestInfo: RequestInfo, result: @escaping FlutterResult) {
        
        self.initModel(models: requestInfo.models) { modelCompletedResult in
            guard modelCompletedResult, let opti = self.opti else {
                if self.logEnabled {
                    print("model initialzed failed")
                }
                
                return
            }
            
            self.operationQueue.cancelAllOperations()
            let requestTask = RequesTask(opti: opti, inputIds: requestInfo.inputIds, speakerId: requestInfo.speakerId, speed: requestInfo.speed, sampleRate: requestInfo.sampleRate, hopSize: requestInfo.hopSize, engine: self.engine, player: self.player, logEnabled: self.logEnabled, enableLids: requestInfo.enableLids, result: result)
            self.operationQueue.addOperation(requestTask)
        }
    }
    
    /// Runs ONNX inference and caches the audio buffer for later playback.
    ///
    /// The generated PCM data is stored in ``BufferHolder`` under the request's
    /// `requestId`. Per-phoneme durations are returned via `result`.
    public func generateVoice(requestInfo: RequestInfo, result: @escaping FlutterResult) {
        
        self.initModel(models: requestInfo.models) { modelCompletedResult in
            guard modelCompletedResult, let opti = self.opti else {
                if self.logEnabled {
                    print("model initialzed failed")
                }
                 
                return
            }
            
            if requestInfo.singleThread {
                self.operationQueue.cancelAllOperations()
            }
            
            let requestTask = GenerateTask(requestId: requestInfo.requestId, opti: opti, inputIds: requestInfo.inputIds, speakerId: requestInfo.speakerId, speed: requestInfo.speed, sampleRate: requestInfo.sampleRate, hopSize: requestInfo.hopSize, engine: self.engine, player: self.player, logEnabled: self.logEnabled, enableLids: requestInfo.enableLids, result: result)
            self.operationQueue.addOperation(requestTask)
        }
    }
    
    /// Plays a previously cached audio buffer identified by `requestInfo.requestId`.
    ///
    /// Submits a ``PlayVoiceTask`` to the serial `audioOperationQueue`.
    public func playVoice(requestInfo: RequestInfo, result: @escaping FlutterResult) {
        
        if requestInfo.singleThread {
            self.audioOperationQueue.cancelAllOperations()
        }
        
        let requestTask = PlayVoiceTask(requestId: requestInfo.requestId, sampleRate: requestInfo.sampleRate, player: self.player, engine: self.engine, playerCompletedDelayed: requestInfo.playerCompletedDelayed, logEnabled: self.logEnabled, enableLids: requestInfo.enableLids, result: result)
        self.audioOperationQueue.addOperation(requestTask)
    }
    
    /// Releases all cached audio buffers.
    public func dispose() {
        BufferHolder.shared.audioBuffers.removeAll()
    }

    /// `Operation` subclass that runs ONNX inference and caches the resulting
    /// audio in ``BufferHolder`` without playing it.
    ///
    /// Returns per-phoneme durations (in seconds) to the Flutter side via the
    /// `result` callback on the main queue.
    class GenerateTask: Operation {
        let opti: Opti
        let inputIds: [Int64]
        let speakerId: Int64
        let speed: Float
        let sampleRate: Int
        let hopSize: Int
        let result: FlutterResult
        let engine: AVAudioEngine?
        let player: AVAudioPlayerNode?
        let requestId: String
        let logEnabled: Bool
        let enableLids: Bool
        
        init(requestId: String, opti: Opti, inputIds: [Int64], speakerId: Int64, speed: Float, sampleRate: Int, hopSize: Int,engine: AVAudioEngine?, player: AVAudioPlayerNode?, logEnabled: Bool, enableLids: Bool, result: @escaping FlutterResult) {
            self.requestId = requestId
            self.opti = opti
            self.inputIds = inputIds
            self.speakerId = speakerId
            self.speed = speed
            self.sampleRate = sampleRate
            self.hopSize = hopSize
            self.result = result
            self.engine = engine
            self.player = player
            self.logEnabled = logEnabled
            self.enableLids = enableLids
        }
        
        func onCancelled() {
            BufferHolder.shared.audioBuffers.removeValue(forKey: requestId)
            if logEnabled {
                print("[Voice request] [generate cancelled] \(requestId), \(BufferHolder.shared.audioBuffers.count)")
            }
            let ret: [Double] = []
            result(ret)
        }
        
        override func main() {
               guard !isCancelled else {
                   onCancelled()
                   return
               }
                
                do {
                    if BufferHolder.shared.audioBuffers.count > 3 {
                        if logEnabled {
                            print("[Voice request] [generate something wrong] \(requestId), there are \(BufferHolder.shared.audioBuffers.count) cached items")
                        }
                        
                        BufferHolder.shared.audioBuffers.removeAll()
                    }
                    
                    if logEnabled {
                        print("[Voice request] [generate start] \(requestId), \(BufferHolder.shared.audioBuffers.count)")
                    }
                    
                    let optiResult = try opti.process(inputIds: inputIds, speedRatio: speed, speakerId: speakerId, hopSize: hopSize, sampleRate: sampleRate, enableLids: enableLids, isCancelled: {
                        return isCancelled
                    })
                    
                    guard optiResult.hasData() else {
                        onCancelled()
                        return                        
                    }
                    
                    guard !isCancelled else {
                        onCancelled()
                        return
                    }
                    
                    let data = optiResult.audioData()
                    BufferHolder.shared.audioBuffers[requestId] = data
                    let duration = optiResult.durations
                    if logEnabled {
                        print("[Voice request] [generate end] \(requestId), \(BufferHolder.shared.audioBuffers.count)")
                    }
                    
                    DispatchQueue.main {
                        self.result(duration)
                    }
                }
                catch {
                    print(error)
                }
           }
    }
    
    /// `Operation` subclass that plays a cached audio buffer from ``BufferHolder``.
    ///
    /// Uses either the external processor strategy delegate or the built-in
    /// `AVAudioEngine` / `AVAudioPlayerNode` for playback.
    class PlayVoiceTask: Operation {
        let engine: AVAudioEngine?
        let player: AVAudioPlayerNode?
        let requestId: String
        let result: FlutterResult
        let sampleRate: Int
        let playerCompletedDelayed: Int
        let logEnabled: Bool
        let enableLids: Bool
        init(requestId: String, sampleRate: Int, player: AVAudioPlayerNode?, engine: AVAudioEngine?, playerCompletedDelayed: Int, logEnabled: Bool, enableLids: Bool, result: @escaping FlutterResult) {
            self.requestId = requestId
            self.result = result
            self.engine = engine
            self.player = player
            self.sampleRate = sampleRate
            self.playerCompletedDelayed = playerCompletedDelayed
            self.logEnabled = logEnabled
            self.enableLids = enableLids
        }
        
        func onCancelled() {
            BufferHolder.shared.audioBuffers.removeValue(forKey: requestId)
            if logEnabled {
                print("[Voice request] [play cancelled] \(requestId), \(BufferHolder.shared.audioBuffers.count)")
            }
            
            result(nil)
        }
        
        override func main() {
               guard !isCancelled else {
                   onCancelled()
                   return
               }
               
            if logEnabled {
                print("[Voice request] [play start] \(requestId), \(BufferHolder.shared.audioBuffers.count)")
            }
            
            
            guard let buffer = BufferHolder.shared.audioBuffers[requestId] else {
                if logEnabled {
                    print("buffer is null")
                }
                
                onCancelled()
                return
            }
            
            if MlProcessorStrategy.shared().delegate != nil {
                MlProcessorStrategy.shared().delegate?.playBuffer(buffer, withSampleRate: Int32(sampleRate), withCancelled: {
                    if self.isCancelled {
                        self.onCancelled()
                    }
                    
                    return self.isCancelled
                }, withCompleted: {
                    if self.logEnabled {
                        print("[Voice request] [play end] \(self.requestId), \(BufferHolder.shared.audioBuffers.count)")
                    }
                    BufferHolder.shared.audioBuffers.removeValue(forKey: self.requestId)
                    if self.playerCompletedDelayed == 0 {
                        self.result(nil)
                    } else {
                        DispatchQueue.main(delay: Double(self.playerCompletedDelayed) / 1000) {
                            self.result(nil)
                        }
                    }
                    
                })
            } else {
                self.playBuffer(data: buffer, sampleRate: sampleRate)
            }
        }
        
        private func playBuffer(data: Data, sampleRate: Int) {
            guard let player = self.player, let engine = self.engine, let audioFormat = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1) else {
                print("engine does not initialize yet")
                result(nil)
                return
            }
            
            guard !isCancelled else { return result(nil)}
            let mixer = engine.mainMixerNode
            engine.attach(player)
            engine.connect(player, to: mixer, format: audioFormat)
            
            do {
                engine.prepare()
                try engine.start()
            } catch {
                print("Error info: \(error)")
            }
            
            guard !isCancelled else { return result(nil)}
            guard let buffer = data.makePCMBuffer(format: audioFormat)  else {
                result(nil)
               return
            }
            
            guard !isCancelled else {
                result(nil)
                return
            }
            guard player.engine?.isRunning == true else {
                print("engine does not start yet")
                result(nil)
                return
            }
            
            guard !isCancelled else { return }
            player.play()
            guard !isCancelled else { return }
            player.scheduleBuffer(buffer) {
                if self.playerCompletedDelayed == 0 {
                    self.result(nil)
                } else {
                    DispatchQueue.main(delay: Double(self.playerCompletedDelayed) / 1000) {
                        self.result(nil)
                    }
                }
            }
        }
    }
    
    
    /// `Operation` subclass that runs ONNX inference **and** immediately plays
    /// the resulting audio (speak-and-play in a single step).
    ///
    /// Returns per-phoneme durations to the Flutter side on the main queue,
    /// then starts audio playback.
    class RequesTask: Operation {
        let opti: Opti
        let inputIds: [Int64]
        let speakerId: Int64
        let speed: Float
        let sampleRate: Int
        let hopSize: Int
        let result: FlutterResult
        let engine: AVAudioEngine?
        let player: AVAudioPlayerNode?
        let logEnabled: Bool
        let enableLids: Bool
        
        init(opti: Opti, inputIds: [Int64], speakerId: Int64, speed: Float, sampleRate: Int, hopSize: Int,engine: AVAudioEngine?, player: AVAudioPlayerNode?, logEnabled: Bool, enableLids: Bool, result: @escaping FlutterResult) {
            self.opti = opti
            self.inputIds = inputIds
            self.speakerId = speakerId
            self.speed = speed
            self.sampleRate = sampleRate
            self.hopSize = hopSize
            self.result = result
            self.engine = engine
            self.player = player
            self.logEnabled = logEnabled
            self.enableLids = enableLids
        }
        
        override func main() {
               guard !isCancelled else { return }
                if logEnabled {
                    print("Running..")
                }
               
            
                do {
                    let optiResult = try opti.process(inputIds: inputIds, speedRatio: speed, speakerId: speakerId, hopSize: hopSize, sampleRate: sampleRate, enableLids: enableLids, isCancelled: {
                        return isCancelled
                    })
                    
                    guard optiResult.hasData() else { return }
                    guard !isCancelled else { return }
                    let data = optiResult.audioData()
                    
                    guard !isCancelled, !data.isEmpty else { return }
                    let duration = optiResult.durations
                    DispatchQueue.main {
                        self.result(duration)
                    }
                    
                    guard !isCancelled, !data.isEmpty else { return }
                    if MlProcessorStrategy.shared().delegate != nil {
                        MlProcessorStrategy.shared().delegate?.playBuffer(data, withSampleRate: Int32(sampleRate), withCancelled: {
                            return self.isCancelled
                        }, withCompleted: {
                          
                        })
                    } else {
                        self.playBuffer(data: data, sampleRate: sampleRate)
                    }
                }
                catch {
                    print(error)
                }
           }
        
        private func playBuffer(data: Data, sampleRate: Int) {
            guard let player = self.player, let engine = self.engine, let audioFormat = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1) else {
                if self.logEnabled {
                    print("engine does not initialize yet")
                }
                
                return
            }
            
            guard !isCancelled else { return }
            let mixer = engine.mainMixerNode
            engine.attach(player)
            engine.connect(player, to: mixer, format: audioFormat)
            
            do {
                engine.prepare()
                try engine.start()
            } catch {
                if self.logEnabled {
                    print("Error info: \(error)")
                }
            }
            
            guard !isCancelled else { return }
            guard let buffer = data.makePCMBuffer(format: audioFormat)  else {
               return
            }
            
            guard !isCancelled else { return }
            guard player.engine?.isRunning == true else {
                if self.logEnabled {
                    print("engine does not start yet")
                }
                return
            }
            
            guard !isCancelled else { return }
            player.play()
            guard !isCancelled else { return }
            player.scheduleBuffer(buffer) {
                if self.isCancelled {
                    DispatchQueue.main {
                        player.stop()
                    }
                }
            }
        }
    }
}

extension Array {
  /// Creates a new array from the bytes of the given unsafe data.
  ///
  /// - Warning: The array's `Element` type must be trivial in that it can be copied bit for bit
  ///     with no indirection or reference-counting operations; otherwise, copying the raw bytes in
  ///     the `unsafeData`'s buffer to a new array returns an unsafe copy.
  /// - Note: Returns `nil` if `unsafeData.count` is not a multiple of
  ///     `MemoryLayout<Element>.stride`.
  /// - Parameter unsafeData: The data containing the bytes to turn into an array.
  init?(unsafeData: Data) {
    guard unsafeData.count % MemoryLayout<Element>.stride == 0 else { return nil }
    self = unsafeData.withUnsafeBytes { .init($0.bindMemory(to: Element.self)) }
  }
}

/// Convenience helpers for dispatching work on background and main queues.
extension DispatchQueue {
    /// Dispatches `background` on a global queue, then `completion` on the main queue after `delay`.
    static func background(delay: Double = 0.0, background: (()->Void)? = nil, completion: (() -> Void)? = nil) {
        DispatchQueue.global(qos: .background).async {
            background?()
            if let completion = completion {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: {
                    completion()
                })
            }
        }
    }
    
    /// Dispatches `task` asynchronously on the main queue.
    static func main(_ task: @escaping () -> ()) {
        DispatchQueue.main.async {
           task()
        }
    }
    
    /// Dispatches `task` on the main queue after `delay` seconds.
    static func main(delay: Double = 0.0, _ task: @escaping () -> ()) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: {
            task()
        })
    }
}

/// Helpers for converting between raw `Data` and `AVAudioPCMBuffer`.
extension Data {
    /// Creates raw byte data from a PCM audio buffer.
    init(buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        let audioBuffer = buffer.audioBufferList.pointee.mBuffers
        self.init(bytes: audioBuffer.mData!, count: Int(audioBuffer.mDataByteSize))
    }

    /// Converts raw byte data back into an `AVAudioPCMBuffer` suitable for playback.
    func makePCMBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let streamDesc = format.streamDescription.pointee
        let frameCapacity = UInt32(count) / streamDesc.mBytesPerFrame
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else { return nil }

        buffer.frameLength = buffer.frameCapacity
        let audioBuffer = buffer.audioBufferList.pointee.mBuffers

        withUnsafeBytes { (bufferPointer) in
            guard let addr = bufferPointer.baseAddress else { return }
            audioBuffer.mData?.copyMemory(from: addr, byteCount: Int(audioBuffer.mDataByteSize))
        }

        return buffer
    }
}
