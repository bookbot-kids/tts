
import Foundation
import onnxruntime_objc

struct PiperOutputs {
    let audio: [Float]
    let durations: [Float]
    
    func hasData() -> Bool {
        return audio.count > 0 && durations.count > 0
    }
}

class Piper: BaseProcessor {
    override init(ortEnv: ORTEnv?, url: URL, threadCount: Int) {
        super.init(ortEnv: ortEnv, url: url, threadCount: threadCount)
    }
    
    private func sumVertically(array: [[Float]]) -> [Float] {
        let numRows = array.count
        let numCols = array[0].count
        
        var sumArray = [Float](repeating: 0.0, count: numCols)
        
        for col in 0..<numCols {
            var sum: Float = 0.0
            for row in 0..<numRows {
                sum += array[row][col]
            }
            sumArray[col] = sum
        }
        
        return sumArray
    }
    
    func infer(inputIds: [Int64], speedRatio: Float, speakerId: Int32 = 0,
                           isCancelled: (() -> Bool)) throws -> PiperOutputs {
        var result = PiperOutputs(audio: [], durations: [])
        
        if isCancelled() { return result }
        initSession()
        
        let inputLength = [Int64(inputIds.count)]
        let scales: [Float] = [0.667, 1.2, 0.8]
        //let sid: Any? = nil
        
        let inputShape: [Int64] = [1, Int64(inputIds.count)]
        let inputLengthShape: [Int64] = [1]
        let scalesShape: [Int64] = [3]
        
        let inputNames = ["input", "input_lengths", "scales"]
        
        let inputTensor = try! ORTValue(tensorData: NSMutableData(bytes: inputIds, length: inputIds.count * MemoryLayout<Int64>.size), elementType: ORTTensorElementDataType.int64, shape: inputShape.map { NSNumber(value: $0) })
        
        let inputLengthTensor = try! ORTValue(tensorData: NSMutableData(bytes: inputLength, length: inputLength.count * MemoryLayout<Int64>.size), elementType: ORTTensorElementDataType.int64, shape: inputLengthShape.map { NSNumber(value: $0) })
        
        let scalesTensor = try! ORTValue(tensorData: NSMutableData(bytes: scales, length: scales.count * MemoryLayout<Float>.size), elementType: ORTTensorElementDataType.float, shape: scalesShape.map { NSNumber(value: $0) })
        
        let inputTensors = [inputTensor, inputLengthTensor, scalesTensor]
//        if isCancelled() { return result }
        
        // create input name -> input tensor map
        var inputMap: [String: ORTValue] = [:]
        for (index, name) in inputNames.enumerated() {
            inputMap[name] = inputTensors[index]
        }
        
//        if isCancelled() { return result }
        
        guard let session = ortSession else {
            return result
        }
        
        let output = try! session.run(withInputs: inputMap, outputNames: ["audio", "attention"], runOptions: nil)
        
        let audio = try! output["audio"]!.tensorData()
        let durations = try! output["attention"]!.tensorData()
        let durationShapeInfo = try! output["attention"]?.tensorTypeAndShapeInfo()
        let audioShapeInfo = try! output["audio"]?.tensorTypeAndShapeInfo()
        
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

        if isCancelled() { return result }
        
        // Convert durations NSMutableData to [Float]
        let durationsPointer = durations.bytes.assumingMemoryBound(to: Float.self)
        let durationsDims = durationShapeInfo!.shape.map{ Int(truncating: $0) }
        
        var durationsArray: [[Float]] = Array(repeating: Array(repeating: 0, count: durationsDims[3]), count: durationsDims[2])

        for i in 0..<durationsDims[2] {
            for j in 0..<durationsDims[3] {
                durationsArray[i][j] = durationsPointer[i*durationsDims[3] + j]
            }
        }
        
        
        let dur = sumVertically(array: durationsArray)
        result = PiperOutputs(audio: audioArray[0][0], durations: dur)
        return result
    }
}
