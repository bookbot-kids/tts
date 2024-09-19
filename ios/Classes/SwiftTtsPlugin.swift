import Flutter
import UIKit

public class SwiftTtsPlugin: NSObject, FlutterPlugin {
    private let tts = TTS()
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "tts", binaryMessenger: registrar.messenger())
    let instance = SwiftTtsPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
      switch call.method {
          case "initModels":
            let argurments = call.arguments as! Dictionary<String, Any>
            let models = argurments["models"] as! Array<String>
            tts.logEnabled = argurments["logEnabled"] as? Bool ?? true
            tts.threadCount = argurments["threadCount"] as? Int ?? 1
            tts.initModel(models: models) { completedResult in
              result(completedResult)
            }
            break
          case "speakText":
            let argurments = call.arguments as! Dictionary<String, Any>
            let models = argurments["models"] as! Array<String>
            let inputIds = argurments["inputIds"] as! Array<Int64>
            let speed = argurments["speed"] as! NSNumber
            let speakerId = argurments["speakerId"] as! Int
            let sampleRate = argurments["sampleRate"] as! Int
            let hopSize = argurments["hopSize"] as! Int
            tts.logEnabled = argurments["logEnabled"] as? Bool ?? true
            tts.threadCount = argurments["threadCount"] as? Int ?? 1
            tts.speak(models: models, inputIds: inputIds, speakerId: Int64(speakerId), speed: Float(truncating: speed), sampleRate: sampleRate, hopSize: hopSize, result: result)
            break
          case "generateVoice":
            let argurments = call.arguments as! Dictionary<String, Any>
            let models = argurments["models"] as! Array<String>
            let inputIds = argurments["inputIds"] as! Array<Int64>
            let speed = argurments["speed"] as! NSNumber
            let speakerId = argurments["speakerId"] as! Int
            let sampleRate = argurments["sampleRate"] as! Int
            let hopSize = argurments["hopSize"] as! Int
            let requestId = argurments["requestId"] as! String
            let singleThread = argurments["singleThread"] as! Bool
            tts.logEnabled = argurments["logEnabled"] as? Bool ?? true
            tts.threadCount = argurments["threadCount"] as? Int ?? 1
            tts.generateVoice(requestId: requestId, models: models, inputIds: inputIds, speakerId: Int64(speakerId), speed: Float(truncating: speed), sampleRate: sampleRate, hopSize: hopSize, singleThread:singleThread, result: result)
            break
          case "playVoice":
            let argurments = call.arguments as! Dictionary<String, Any>
            let models = argurments["models"] as! Array<String>
            let inputIds = argurments["inputIds"] as! Array<Int64>
            let speed = argurments["speed"] as! NSNumber
            let speakerId = argurments["speakerId"] as! Int
            let sampleRate = argurments["sampleRate"] as! Int
            let hopSize = argurments["hopSize"] as! Int
            let requestId = argurments["requestId"] as! String
            let singleThread = argurments["singleThread"] as! Bool
            let playerCompletedDelayed = argurments["playerCompletedDelayed"] as! Int
            tts.logEnabled = argurments["logEnabled"] as? Bool ?? true
            tts.threadCount = argurments["threadCount"] as? Int ?? 1
            tts.playVoice(requestId: requestId, models: models, inputIds: inputIds, speakerId: Int64(speakerId), speed: Float(truncating: speed), sampleRate: sampleRate, hopSize: hopSize, singleThread:singleThread, playerCompletedDelayed: playerCompletedDelayed, result: result)
            break
            case "dispose":
            tts.dispose()
            break
          default :
              result(FlutterMethodNotImplemented)
      }
  }
}
