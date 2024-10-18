//
//  Opti.swift
//  HelloTensorFlowTTS
//
//  Created by 안창범 on 2021/03/09.
//

import Foundation
import onnxruntime_objc

struct OptiOutputs {
    let audio: [Float]
    let durations: [Double]
    
    func hasData() -> Bool {
        return audio.count > 0 && durations.count > 0
    }
    
    func audioData() -> Data {
        return audio.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}

class Opti: BaseProcessor {
    override init(ortEnv: ORTEnv?, url: URL, threadCount: Int) {
        super.init(ortEnv: ortEnv, url: url, threadCount: threadCount)
    }
    
    func process(inputIds: [Int64], speedRatio: Float, speakerId: Int64 = 0, hopSize: Int, sampleRate: Int,
                 isCancelled: (() -> Bool)) throws -> OptiOutputs{
        var result = OptiOutputs(audio: [], durations: [])
                
        guard !isCancelled() else {
            return result
        }
        
        // Initialize the session
        initSession()
        guard let session = ortSession else {
            return result
        }
        
        // Prepare inputs
        let x = inputIds
        let x_lengths: [Int64] = [Int64(inputIds.count)]
        let scales: [Float] = [speedRatio, 1.0, 1.0]
        
        // Shapes for inputs
        let xShape: [NSNumber] = [1, NSNumber(value: x.count)]
        let xLengthsShape: [NSNumber] = [1]
        let scalesShape: [NSNumber] = [3]
        
        var inputNames = ["x", "x_lengths", "scales"]
        
        // Create input tensors
        let xTensor = try createTensor(data: x, shape: xShape, dataType: .int64)
        let xLengthsTensor = try createTensor(data: x_lengths, shape: xLengthsShape, dataType: .int64)
        let scalesTensor = try createTensor(data: scales, shape: scalesShape, dataType: .float)
        var inputTensors = [xTensor, xLengthsTensor, scalesTensor]
        
        if speakerId >= 0 {
            let sids: [Int64] = [speakerId]
            let sidsShape: [NSNumber] = [1]
            inputNames.append("sids")
            let sidsTensor = try createTensor(data: sids, shape: sidsShape, dataType: .int64)
            inputTensors.append(sidsTensor)
        }
        
        
        // Map input names to tensors
        var inputMap: [String: ORTValue] = [:]
        for (index, name) in inputNames.enumerated() {
            inputMap[name] = inputTensors[index]
        }
        
        guard !isCancelled() else {
            return result
        }
        
        // Run the session
        let outputs = try session.run(withInputs: inputMap, outputNames: ["wav", "wav_lengths", "durations"], runOptions: nil)
        
        guard !isCancelled() else {
            return result
        }
        
        // Extract outputs
        guard let audioOrtValue = outputs["wav"], let durationsOrtValue = outputs["durations"] else {
            return result
        }
        
        // Process audio output
        let audioData = try audioOrtValue.tensorData()
        let audioShapeInfo = try audioOrtValue.tensorTypeAndShapeInfo()
        let audioDims = audioShapeInfo.shape.map { Int(truncating: $0) }

        let audioCount = audioDims.reduce(1, *)
        var audioArray = [Float](repeating: 0, count: audioCount)
        _ = audioArray.withUnsafeMutableBytes { audioPointer in
            audioData.copyBytes(to: audioPointer, count: audioCount * MemoryLayout<Float>.size)
        }

        // Process durations output
        let durationsData = try durationsOrtValue.tensorData()
        let durationsShapeInfo = try durationsOrtValue.tensorTypeAndShapeInfo()
        let durationsDims = durationsShapeInfo.shape.map { Int(truncating: $0) }

        let durationsCount = durationsDims.reduce(1, *)
        var durationsArray = [Int64](repeating: 0, count: durationsCount)
        _ = durationsArray.withUnsafeMutableBytes { durationsPointer in
            durationsData.copyBytes(to: durationsPointer, count: durationsCount * MemoryLayout<Int64>.size)
        }
        
        let durationsInSeconds = durationsArray.map { Double($0) * Double(hopSize) / Double(sampleRate) }
        result = OptiOutputs(audio: audioArray, durations: durationsInSeconds)
        return result
    }
    
    private func createTensor<T>(data: [T], shape: [NSNumber], dataType: ORTTensorElementDataType) throws -> ORTValue{
        let dataSize = data.count * MemoryLayout<T>.stride
        let tensorData = NSMutableData(bytes: data, length: dataSize)
        return try ORTValue(tensorData: tensorData, elementType: dataType, shape: shape)
    }
}
