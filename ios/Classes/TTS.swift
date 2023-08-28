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

public class BufferHolder {
    static let shared: BufferHolder = BufferHolder()
    var audioBuffers = Dictionary<String, Data>()
}

public class TTS {
    var piper: Piper?
    private var modelMap = [String:Bool]()
    
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private let sampleBufferRenderSynchronizer = AVSampleBufferRenderSynchronizer()

    private let sampleBufferAudioRenderer = AVSampleBufferAudioRenderer()
    var operationQueue: OperationQueue = OperationQueue()
    var audioOperationQueue: OperationQueue = OperationQueue()
    var logEnabled = true
    var threadCount = 1

    init() {
        sampleBufferRenderSynchronizer.addRenderer(sampleBufferAudioRenderer)
        operationQueue.maxConcurrentOperationCount = 1
        audioOperationQueue.maxConcurrentOperationCount = 1
        if(MlProcessorStrategy.shared().delegate == nil) {
            initAudioEngine()
        }
    }
    
    private func initAudioEngine() {
        engine = AVAudioEngine()
        player = AVAudioPlayerNode()
    }
    
    public func initModel(fastSpeechModel:String, melGanModel: String, onCompleted:@escaping((Bool) -> Void)) {
        let key  = fastSpeechModel + melGanModel
        if(modelMap[key] == nil) {
            modelMap.removeAll()
            if(MlProcessorStrategy.shared().delegate != nil) {
                MlProcessorStrategy.shared().delegate.urls(for: [fastSpeechModel, melGanModel]) { urls in
                    guard let modelUrls = urls, let fastSpeechUrl = modelUrls[0] as? URL else {
                        onCompleted(false)
                        return
                    }
                    
                    let ortEnv = try? ORTEnv(loggingLevel: ORTLoggingLevel.warning)
                    self.piper = Piper(ortEnv: ortEnv, url: fastSpeechUrl, threadCount: self.threadCount)
                    self.modelMap[key] = true
                    onCompleted(self.piper != nil)
                }
            } else {
                let fastSpeechUrl =  Bundle.main.url(forResource: (fastSpeechModel as NSString).deletingPathExtension, withExtension: "onnx")
                guard let fastSpeechUrl = fastSpeechUrl else {
                    if self.logEnabled {
                        print("can't read model url \(fastSpeechModel) ")
                    }
                    
                    onCompleted(false)
                    return
                }
                
                let ortEnv = try? ORTEnv(loggingLevel: ORTLoggingLevel.warning)
                piper = Piper(ortEnv: ortEnv, url: fastSpeechUrl, threadCount: self.threadCount)
                modelMap[key] = true
                onCompleted(piper != nil)
            }
        } else {
            onCompleted(true)
        }
    }

    public func speak(fastSpeechModel:String, melGanModel: String, inputIds: [Int32], speakerId: Int32 = 0, speed: Float = 1.0, sampleRate: Int, hopSize: Int, result: @escaping FlutterResult) {
        
        self.initModel(fastSpeechModel: fastSpeechModel, melGanModel: melGanModel) { modelCompletedResult in
            guard modelCompletedResult, let piper = self.piper else {
                if self.logEnabled {
                    print("model initialzed failed")
                }
                
                return
            }
            
            self.operationQueue.cancelAllOperations()
            let requestTask = RequesTask(piper: piper, inputIds: inputIds.map { Int64($0) }, speakerId: speakerId, speed: speed, sampleRate: sampleRate, hopSize: hopSize, engine: self.engine, player: self.player, logEnabled: self.logEnabled, result: result)
            self.operationQueue.addOperation(requestTask)
        }
    }
        
    public func dispose() {
        BufferHolder.shared.audioBuffers.removeAll()
    }
    
    class RequesTask: Operation {
        let piper: Piper
        let inputIds: [Int64]
        let speakerId: Int32
        let speed: Float
        let sampleRate: Int
        let hopSize: Int
        let result: FlutterResult
        let engine: AVAudioEngine?
        let player: AVAudioPlayerNode?
        let logEnabled: Bool
        
        init(piper: Piper, inputIds: [Int64], speakerId: Int32, speed: Float, sampleRate: Int, hopSize: Int,engine: AVAudioEngine?, player: AVAudioPlayerNode?, logEnabled: Bool, result: @escaping FlutterResult) {
            self.piper = piper
            self.inputIds = inputIds
            self.speakerId = speakerId
            self.speed = speed
            self.sampleRate = sampleRate
            self.hopSize = hopSize
            self.result = result
            self.engine = engine
            self.player = player
            self.logEnabled = logEnabled
        }
        
        override func main() {
               guard !isCancelled else { return }
                if logEnabled {
                    print("Running..")
                }
               
            
                do {
                    let output = try piper.infer(inputIds: inputIds, speedRatio: speed, speakerId: speakerId, isCancelled: {
                        return isCancelled
                    })
                    
                    guard output.hasData() else { return }
                    guard !isCancelled else { return }
                    let data = output.mels.withUnsafeBufferPointer { Data(buffer: $0) }
                    
                    guard !isCancelled, !data.isEmpty else { return }
                    let duration = output.durations.compactMap { $0 }.map { Double($0) }
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

extension DispatchQueue {
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
    
    static func main(_ task: @escaping () -> ()) {
        DispatchQueue.main.async {
           task()
        }
    }
    
    static func main(delay: Double = 0.0, _ task: @escaping () -> ()) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: {
            task()
        })
    }
}

extension Data {
    init(buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        let audioBuffer = buffer.audioBufferList.pointee.mBuffers
        self.init(bytes: audioBuffer.mData!, count: Int(audioBuffer.mDataByteSize))
    }

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
