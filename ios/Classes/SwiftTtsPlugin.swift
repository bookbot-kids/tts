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
            let fastSpeechModel = argurments["fastSpeechModel"] as! String
            let melganModel = argurments["melganModel"] as! String
            tts.initModel(fastSpeechModel: fastSpeechModel, melGanModel: melganModel) { completedResult in
              result(completedResult)
            }
            break
          case "speakText":
            let argurments = call.arguments as! Dictionary<String, Any>
            let fastSpeechModel = argurments["fastSpeechModel"] as! String
            let melganModel = argurments["melganModel"] as! String
            let inputIds = argurments["inputIds"] as! Array<Int32>
            let speed = argurments["speed"] as! NSNumber
            let speakerId = argurments["speakerId"] as! Int
            let sampleRate = argurments["sampleRate"] as! Int
            let hopSize = argurments["hopSize"] as! Int
            tts.speak(fastSpeechModel: fastSpeechModel, melGanModel: melganModel, inputIds: inputIds, speakerId: Int32(speakerId), speed: Float(truncating: speed), sampleRate: sampleRate, hopSize: hopSize, result: result)
            break
          default :
              result(FlutterMethodNotImplemented)
      }
  }
}
