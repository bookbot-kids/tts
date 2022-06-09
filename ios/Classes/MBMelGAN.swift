//
//  MBMelGAN.swift
//  HelloTensorFlowTTS
//
//  Created by 안창범 on 2021/03/09.
//

import Foundation
import TensorFlowLite

class MBMelGan {
    let interpreter: Interpreter
    
    init(url: URL) throws {
        var options = Interpreter.Options()
        options.threadCount = 1
        interpreter = try Interpreter(modelPath: url.path, options: options)
    }
    
    func getAudio(input: Tensor, isCancelled: (() -> Bool)) throws -> Data {
        if isCancelled() {
            return Data()
        }
        
        try interpreter.resizeInput(at: 0, to: input.shape)
        
        if isCancelled() {
            return Data()
        }
        
        try interpreter.allocateTensors()
        
        if isCancelled() {
            return Data()
        }
        
        try interpreter.copy(input.data, toInputAt: 0)

        if isCancelled() {
            return Data()
        }
        
        try interpreter.invoke()

        if isCancelled() {
            return Data()
        }
        return try interpreter.output(at: 0).data
    }
}
