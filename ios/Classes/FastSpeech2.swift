//
//  FastSpeech2.swift
//  HelloTensorFlowTTS
//
//  Created by 안창범 on 2021/03/09.
//

import Foundation
import onnxruntime_objc

/// Output of a ``FastSpeech2`` inference pass.
struct LightSpeechOutputs {
    /// 3-D mel spectrogram array (batch × time × mel_channels).
    let mels: [[[Float]]]
    /// Per-phoneme duration frames (batch × phonemes).
    let durations: [[Int32]]

    /// Returns `true` if both mels and durations contain data.
    func hasData() -> Bool {
        return mels.count > 0 && durations.count > 0
    }
}

/// FastSpeech 2 acoustic model processor (legacy two-stage pipeline).
///
/// Converts phoneme token IDs into a mel spectrogram and per-phoneme
/// duration frames. The mel output is then fed to ``MBMelGan`` to
/// synthesise raw PCM audio.
class FastSpeech2: BaseProcessor {
    /// F0 (pitch) scaling ratio.
    var f0Ratio: Float = 1
    /// Energy scaling ratio.
    var energyRatio: Float = 1

    override init(ortEnv: ORTEnv?, url: URL, threadCount: Int) {
        super.init(ortEnv: ortEnv, url: url, threadCount: threadCount)
    }

    /// Runs FastSpeech 2 inference to produce a mel spectrogram.
    ///
    /// - Parameters:
    ///   - inputIds: Phoneme token IDs.
    ///   - speedRatio: Speech speed multiplier.
    ///   - speakerId: Speaker embedding index.
    ///   - isCancelled: Closure checked at key points to allow early exit.
    /// - Returns: ``LightSpeechOutputs`` with mel spectrogram and durations.
    func getMelSpectrogram(inputIds: [Int32], speedRatio: Float, speakerId: Int32 = 0,
                           isCancelled: (() -> Bool)) throws -> LightSpeechOutputs {
        var result = LightSpeechOutputs(mels: [], durations: [])
        
        guard !isCancelled() else {
            return result
        }
        
        initSession()        
        guard let session = ortSession else {
            return result
        }
        
        let speakerIDs: [Int32] = [speakerId]
        let speedRatios: [Float] = [speedRatio]
        let f0Ratios: [Float] = [1.0]
        let energyRatios: [Float] = [1.0]

        // this is the shape of the inputs, our equivalent to tf.expand_dims.
        let inputIDsShape: [NSNumber]  = [1, NSNumber(value: inputIds.count)]
        let speakerIDsShape: [NSNumber] = [NSNumber(value: 1)]
        let speedRatiosShape: [NSNumber] = [NSNumber(value: 1)]
        let f0RatiosShape: [NSNumber] = [NSNumber(value: 1)]
        let energyRatiosShape: [NSNumber] = [NSNumber(value: 1)]

        let inputNames = ["input_ids", "speaker_ids", "speed_ratios", "f0_ratios", "energy_ratios"]

        // create input tensors from raw vectors
        let inputIDsTensor = try! ORTValue(tensorData: NSMutableData(bytes: inputIds, length: inputIds.count * MemoryLayout<Int32>.size), elementType: ORTTensorElementDataType.int32, shape: inputIDsShape)
        let speakerIDsTensor = try! ORTValue(tensorData: NSMutableData(bytes: speakerIDs, length: speakerIDs.count * MemoryLayout<Int32>.size), elementType: ORTTensorElementDataType.int32, shape: speakerIDsShape)
        let speedRatiosTensor = try! ORTValue(tensorData: NSMutableData(bytes: speedRatios, length: speedRatios.count * MemoryLayout<Float>.size), elementType: ORTTensorElementDataType.float, shape: speedRatiosShape)
        let f0RatiosTensor = try! ORTValue(tensorData: NSMutableData(bytes: f0Ratios, length: f0Ratios.count * MemoryLayout<Float>.size), elementType: ORTTensorElementDataType.float, shape: f0RatiosShape)
        let energyRatiosTensor = try! ORTValue(tensorData: NSMutableData(bytes: energyRatios, length: energyRatios.count * MemoryLayout<Float>.size), elementType: ORTTensorElementDataType.float, shape: energyRatiosShape)
        
        let inputTensors = [inputIDsTensor, speakerIDsTensor, speedRatiosTensor, f0RatiosTensor, energyRatiosTensor]

        // create input name -> input tensor map
        var inputMap: [String: ORTValue] = [:]
        for (index, name) in inputNames.enumerated() {
            inputMap[name] = inputTensors[index]
        }
        
        if isCancelled() {
            return result
        }
        
        let output = try! session.run(withInputs: inputMap, outputNames: ["Identity", "Identity_1", "Identity_2"], runOptions: nil)
        let mels = try! output["Identity"]!.tensorData()
        let durations = try! output["Identity_1"]!.tensorData()
        let durationShapeInfo = try! output["Identity_1"]?.tensorTypeAndShapeInfo()
        let melsShapeInfo = try! output["Identity"]?.tensorTypeAndShapeInfo()
        
        if isCancelled() {
            return result
        }
        // Convert mels NSMutableData to [[[Float]]]
        let melsPointer = mels.bytes.assumingMemoryBound(to: Float.self)
        let melsDims = melsShapeInfo!.shape.map{ Int(truncating: $0) }

        var melsArray: [[[Float]]] = Array(repeating: Array(repeating: Array(repeating: 0.0, count: melsDims[2]), count: melsDims[1]), count: melsDims[0])

        for i in 0..<melsDims[0] {
            for j in 0..<melsDims[1] {
                for k in 0..<melsDims[2] {
                    melsArray[i][j][k] = melsPointer[i*melsDims[1]*melsDims[2] + j*melsDims[2] + k]
                }
            }
        }

        if isCancelled() {
            return result
        }
        
        // Convert durations NSMutableData to [[Int32]]
        let durationsPointer = durations.bytes.assumingMemoryBound(to: Int32.self)
        let durationsDims = durationShapeInfo!.shape.map{ Int(truncating: $0) }
        
        var durationsArray: [[Int32]] = Array(repeating: Array(repeating: 0, count: durationsDims[1]), count: durationsDims[0])

        for i in 0..<durationsDims[0] {
            for j in 0..<durationsDims[1] {
                durationsArray[i][j] = durationsPointer[i*durationsDims[1] + j]
            }
        }
        
        // convert to array
        result = LightSpeechOutputs(mels: melsArray, durations: durationsArray)        
        return result
    }
}
