//
//  FastSpeech2.swift
//  HelloTensorFlowTTS
//
//  Created by 안창범 on 2021/03/09.
//

import Foundation
import TensorFlowLite

class FastSpeech2 {
    
    var f0Ratio: Float = 1
    
    var energyRatio: Float = 1
    
    var url: URL
    
    var options: Interpreter.Options
    
    init(url: URL, threadCount: Int) {
        self.url = url
        self.options = Interpreter.Options()
        self.options.threadCount = threadCount
    }
    
    func getMelSpectrogram(inputIds: [Int32], speedRatio: Float, speakerId: Int32 = 0,
                           isCancelled: (() -> Bool)) throws -> [Tensor] {
        if isCancelled() {
            return []
        }
        
        let interpreter = try Interpreter(modelPath: url.path, options: self.options)
        if isCancelled() {
            return []
        }
        
        var speedRatio = speedRatio
        try interpreter.resizeInput(at: 0, to: [1, inputIds.count])
        if isCancelled() {
            return []
        }
        
        try interpreter.allocateTensors()
        if isCancelled() {
            return []
        }
        
        var speaker = speakerId
        if isCancelled() {
            return []
        }
        
        let data = inputIds.withUnsafeBufferPointer(Data.init)
        if isCancelled() {
            return []
        }
        
        try interpreter.copy(data, toInputAt: 0)
        
        if isCancelled() {
            return []
        }
        
        try interpreter.copy(Data(bytes: &speaker, count: 4), toInputAt: 1)
        
        if isCancelled() {
            return []
        }
        
        try interpreter.copy(Data(bytes: &speedRatio, count: 4), toInputAt: 2)
        
        if isCancelled() {
            return []
        }
        
        try interpreter.copy(Data(bytes: &f0Ratio, count: 4), toInputAt: 3)
        
        if isCancelled() {
            return []
        }
        
        try interpreter.copy(Data(bytes: &energyRatio, count: 4), toInputAt: 4)

        let t0 = Date()
        
        if isCancelled() {
            return []
        }
        
        try interpreter.invoke()
        print("fastspeech2: \(Date().timeIntervalSince(t0))s")
        
        if isCancelled() {
            return []
        }
        
        return [try interpreter.output(at: 1), try interpreter.output(at: 2)]
    }
}
