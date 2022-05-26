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

@available(iOS 13.0, *)
public class TTS {
    var fastSpeech2: FastSpeech2?
    var mbMelGan: MBMelGan?
    private var modelMap = [String:Bool]()

    /// Mel spectrogram hop size
    public let hopSize = 512

    /// Vocoder sample rate
    let sampleRate = 44_100

    private let sampleBufferRenderSynchronizer = AVSampleBufferRenderSynchronizer()

    private let sampleBufferAudioRenderer = AVSampleBufferAudioRenderer()

    init() {
        sampleBufferRenderSynchronizer.addRenderer(sampleBufferAudioRenderer)
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

    public func speak(fastSpeechModel:String, melGanModel: String, inputIds: [Int32], speakerId: Int32 = 0, speed: Float = 1.0, result: @escaping FlutterResult) {
        initModel(fastSpeechModel: fastSpeechModel, melGanModel: melGanModel)
        
        guard let fastSpeech2 = self.fastSpeech2, let mbMelGan = self.mbMelGan else {
            print("model initialzed failed")
            return
        }
        
        do {
            let melSpectrogram = try fastSpeech2.getMelSpectrogram(inputIds: inputIds, speedRatio: 2 - speed, speakerId: speakerId)
            let duration = Array<Int32>(unsafeData: melSpectrogram[1].data)!
            let arr = duration.map( { Double($0) })
            result(arr)
            let data = try mbMelGan.getAudio(input: melSpectrogram[0])
            print(data)

            let blockBuffer = try CMBlockBuffer(length: data.count)
            try data.withUnsafeBytes { try blockBuffer.replaceDataBytes(with: $0) }

            let audioStreamBasicDescription = AudioStreamBasicDescription(mSampleRate: Float64(sampleRate), mFormatID: kAudioFormatLinearPCM, mFormatFlags: kAudioFormatFlagIsFloat, mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0)

            let formatDescription = try CMFormatDescription(audioStreamBasicDescription: audioStreamBasicDescription)

            let delay: TimeInterval = 1

            let sampleBuffer = try CMSampleBuffer(dataBuffer: blockBuffer,
                                                  formatDescription: formatDescription,
                                                  numSamples: data.count / 4,
                                                  presentationTimeStamp: sampleBufferRenderSynchronizer.currentTime()
                                                    + CMTime(seconds: delay, preferredTimescale: CMTimeScale(sampleRate)),
                                                  packetDescriptions: [])

            sampleBufferAudioRenderer.enqueue(sampleBuffer)

            sampleBufferRenderSynchronizer.rate = 1
        }
        catch {
            print(error)
        }
    }
}

@available(iOS 13.0, *)
extension TTS: ObservableObject {

}

public struct Mapper: Codable {
    public let symbol_to_id: [String: Int32]
    public let id_to_symbol: [String: String]
    public let speakers_map: [String: Int32]
    public let processor_name: String
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
