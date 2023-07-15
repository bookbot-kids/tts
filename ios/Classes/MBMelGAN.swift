//
//  MBMelGAN.swift
//  HelloTensorFlowTTS
//
//  Created by 안창범 on 2021/03/09.
//

import Foundation
import onnxruntime_objc

class MBMelGan : BaseProcessor {
    
    override init(ortEnv: ORTEnv?, url: URL, threadCount: Int) {
        super.init(ortEnv: ortEnv, url: url, threadCount: threadCount)
    }
    
    func getAudio(mels: [[[Float]]], isCancelled: (() -> Bool)) throws -> Data {        
        guard !isCancelled() else {
            return Data()
        }
        
        initSession()        
        guard let session = ortSession else {
            return Data()
        }
        
        // unpack 3d FloatArray and get size along each dimension := (1, L, 80)
        let melsShape: [NSNumber] = [NSNumber(value: mels.count), NSNumber(value: mels[0].count), NSNumber(value: mels[0][0].count)]
        
        let totalElements = mels.count * mels[0].count * mels[0][0].count
        var flattenedMels = [Float](repeating: 0, count: totalElements)
        for i in 0..<mels.count {
            for j in 0..<mels[0].count {
                for k in 0..<mels[0][0].count {
                    let index = i * mels[0].count * mels[0][0].count + j * mels[0][0].count + k
                    flattenedMels[index] = mels[i][j][k]
                }
            }
        }
        
        // create input tensors from raw vectors
        let melTensor = try! ORTValue(tensorData: NSMutableData(bytes: flattenedMels, length: flattenedMels.count * MemoryLayout<Float>.size), elementType: ORTTensorElementDataType.float, shape: melsShape)
        
        // create input name -> input tensor map
        let inputTensors: [String: ORTValue] = ["mels": melTensor]

        let output = try! session.run(withInputs: inputTensors, outputNames: ["Identity"], runOptions: nil)
        let audio = try! output["Identity"]!.tensorData()
        let audioShapeInfo = try! output["Identity"]?.tensorTypeAndShapeInfo()
        
        // Convert audio NSMutableData to [[[Float]]]
        let audioPointer = audio.bytes.assumingMemoryBound(to: Float.self)
        let audioDims = audioShapeInfo!.shape.map{ Int(truncating: $0) }

        var audioArray: [[[Float]]] = Array(repeating: Array(repeating: Array(repeating: 0.0, count: audioDims[2]), count: audioDims[1]), count: audioDims[0])

        for i in 0..<audioDims[0] {
            for j in 0..<audioDims[1] {
                for k in 0..<audioDims[2] {
                    audioArray[i][j][k] = audioPointer[i*audioDims[1]*audioDims[2] + j*audioDims[2] + k]
                }
            }
        }
        
        let audioFloatArr = audioArray[0].flatMap { $0 }.map { Float($0) }
        let data = audioFloatArr.withUnsafeBufferPointer { Data(buffer: $0) }
        return data
    }
}
