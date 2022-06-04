//
//  TTS.swift
//  TF TTS Demo
//
//  Created by 안창범 on 2021/03/16.
//

import Foundation
import AVFoundation
import TensorFlowLite
import Flutter

public class TTS {
    var fastSpeech2: FastSpeech2?
    var mbMelGan: MBMelGan?
    private var modelMap = [String:Bool]()
    
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?

    private let sampleBufferRenderSynchronizer = AVSampleBufferRenderSynchronizer()

    private let sampleBufferAudioRenderer = AVSampleBufferAudioRenderer()
    var operationQueue: OperationQueue = OperationQueue()

    init() {
        sampleBufferRenderSynchronizer.addRenderer(sampleBufferAudioRenderer)
        operationQueue.maxConcurrentOperationCount = 1
        if(MlProcessorStrategy.shared().delegate == nil) {
            initAudioEngine()
        }
    }
    
    public func initModel(fastSpeechModel:String, melGanModel: String) {
        let key  = fastSpeechModel + melGanModel
        if(modelMap[key] == nil) {
            modelMap.removeAll()
            let fastSpeechUrl = MlProcessorStrategy.shared().delegate?.url(for: fastSpeechModel) ?? Bundle.main.url(forResource: (fastSpeechModel as NSString).deletingPathExtension, withExtension: "tflite")
            let melganUrl = MlProcessorStrategy.shared().delegate?.url(for: melGanModel) ?? Bundle.main.url(forResource: (melGanModel as NSString).deletingPathExtension, withExtension: "tflite")
            guard let fastSpeechUrl = fastSpeechUrl, let melganUrl = melganUrl else {
                print("can't read model url \(fastSpeechModel), \(melGanModel) ")
                return
            }
            
            fastSpeech2 = try? FastSpeech2(url: fastSpeechUrl)
            mbMelGan = try? MBMelGan(url: melganUrl)
            modelMap[key] = true
        }
    }

    public func speak(fastSpeechModel:String, melGanModel: String, inputIds: [Int32], speakerId: Int32 = 0, speed: Float = 1.0, sampleRate: Int, hopSize: Int, result: @escaping FlutterResult) {
        let operation = BlockOperation {
            self.initModel(fastSpeechModel: fastSpeechModel, melGanModel: melGanModel)
            
            guard let fastSpeech2 = self.fastSpeech2, let mbMelGan = self.mbMelGan else {
                print("model initialzed failed")
                return
            }
            
            do {
                let melSpectrogram = try fastSpeech2.getMelSpectrogram(inputIds: inputIds, speedRatio: 2 - speed, speakerId: speakerId)
                let duration = Array<Int32>(unsafeData: melSpectrogram[1].data)!
                let arr = duration.map( { Double($0) })
                DispatchQueue.main {
                    result(arr)
                }
                
                let data = try mbMelGan.getAudio(input: melSpectrogram[0])
                print(data)
                if MlProcessorStrategy.shared().delegate != nil {
                    MlProcessorStrategy.shared().delegate?.playBuffer(data)
                } else {
                    self.playBuffer(data: data, sampleRate: sampleRate)
                }
            }
            catch {
                print(error)
            }
        }
        
        self.operationQueue.addOperation(operation)
    }
    
    private func initAudioEngine() {
        engine = AVAudioEngine()
        player = AVAudioPlayerNode()
    }
    
    private func playBuffer(data: Data, sampleRate: Int) {
        guard let player = self.player, let engine = self.engine, let audioFormat = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1) else {
            print("engine does not initialize yet")
            return
        }
        
        let mixer = engine.mainMixerNode
        engine.attach(player)
        engine.connect(player, to: mixer, format: audioFormat)
        
        do {
            engine.prepare()
            try engine.start()
        } catch {
            print("Error info: \(error)")
        }
        
        guard let buffer = data.makePCMBuffer(format: audioFormat)  else {
           return
        }
        
        guard player.engine?.isRunning == true else {
            print("engine does not start yet")
            return
        }
        
        player.play()
        player.scheduleBuffer(buffer, completionHandler: nil)
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
