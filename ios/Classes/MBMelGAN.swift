//
//  MBMelGAN.swift
//  HelloTensorFlowTTS
//
//  Created by 안창범 on 2021/03/09.
//

import Foundation
import TensorFlowLite

class MBMelGan {
    var options: Interpreter.Options
    var url: URL
    
    init(url: URL) {
        self.url = url
        options = Interpreter.Options()
        options.threadCount = 1        
    }
    
    func getAudio(input: Tensor, isCancelled: (() -> Bool)) throws -> Data {
        if isCancelled() {
            return Data()
        }
        
        let interpreter = try Interpreter(modelPath: self.url.path, options: self.options)
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
